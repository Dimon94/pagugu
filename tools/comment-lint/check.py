import argparse
import json
import os
import subprocess
from collections import Counter
from functools import lru_cache
from pathlib import Path

from tree_sitter_language_pack import get_parser


PARSERS = json.loads(Path(__file__).with_name("languages.json").read_text())


def git(*args, data=None):
    return subprocess.run(["git", *args], input=data, stdout=subprocess.PIPE, check=True).stdout


@lru_cache(maxsize=None)
def parser(language):
    return get_parser(language)


def grammar(path, source):
    if path.name in PARSERS:
        return PARSERS[path.name]
    suffix = path.suffix.lower()
    if suffix in PARSERS:
        return PARSERS[suffix]
    if source.startswith(b"#!"):
        words = source.split(b"\n", 1)[0][2:].split()
        for word in words:
            binary = word.rsplit(b"/", 1)[-1]
            if binary in (b"bash", b"sh"):
                return "bash"
            if binary in (b"node", b"nodejs"):
                return "javascript"
            if binary.startswith(b"python"):
                return "python"
    return None


def syntax_comments(language, source, offset=0):
    if language == "gitignore":
        for row, line in enumerate(source.splitlines(), 1):
            if line.startswith(b"#"):
                yield row, line
        return
    stack = [parser(language).parse(source).root_node]
    while stack:
        node = stack.pop()
        kind = node.type.lower()
        row = offset + node.start_point.row
        if kind == "comment" or kind.endswith("_comment") or (language == "sql" and kind == "marginalia"):
            value = source[node.start_byte:node.end_byte]
            if node.start_byte == 0 and language in ("bash", "python", "javascript", "ruby") and value.startswith(b"#!"):
                continue
            yield row + 1, value
        elif language == "html" and kind == "raw_text":
            tag = node.parent.named_children[0]
            attrs = {}
            for attr in tag.named_children:
                if attr.type == "attribute" and len(attr.named_children) == 2:
                    key, val = attr.named_children
                    attrs[key.text.lower()] = val.text.strip(b"\"' ").lower()
            mime = attrs.get(b"type", b"")
            if node.parent.type == "style_element" and mime in (b"", b"text/css"):
                yield from syntax_comments("css", node.text, row)
            if node.parent.type == "script_element" and mime in (b"", b"module", b"text/javascript", b"application/javascript"):
                yield from syntax_comments("javascript", node.text, row)
        else:
            stack.extend(reversed(node.named_children))


def comments(path, mode, oid):
    if mode not in (b"100644", b"100755"):
        return ()
    if path.suffix and path.suffix.lower() not in PARSERS and path.name not in PARSERS:
        return ()
    source = git("cat-file", "blob", oid)
    language = grammar(path, source)
    return syntax_comments(language, source) if language else ()


def main():
    args = argparse.ArgumentParser(description="Reject added comments in the Git index against the selected commit.")
    args.add_argument("--base", help="comparison commit or tree (default: HEAD, empty tree for an initial commit)")
    base = args.parse_args().base
    if not base:
        head = subprocess.run(["git", "rev-parse", "--verify", "--quiet", "HEAD"], stdout=subprocess.PIPE)
        base = head.stdout.strip() if head.returncode == 0 else git("hash-object", "-t", "tree", "--stdin", data=b"").strip()
    records = iter(git("diff", "--cached", "--raw", "-z", "--no-abbrev", "--no-renames", base, "--").split(b"\0"))
    count = 0
    for record in records:
        if not record:
            break
        old_mode, mode, old_oid, oid, status = record[1:].split()
        path = Path(os.fsdecode(next(records)))
        if status == b"D":
            continue
        baseline = Counter(value for _, value in comments(path, old_mode, old_oid))
        for line, value in comments(path, mode, oid):
            if baseline[value]:
                baseline[value] -= 1
            else:
                print(f"{path}:{line}: added or edited comment")
                count += 1
    print(f"comments={count}")
    return int(count > 0)


if __name__ == "__main__":
    raise SystemExit(main())
