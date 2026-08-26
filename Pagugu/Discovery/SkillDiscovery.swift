import CryptoKit
import Foundation

// L3 COORD: Pagugu/Discovery/SkillDiscovery.swift
// POS: Discovery 模块（ADR-0009 §2）。owns Discovery Scan：遍历 Scan Root、发现入口标注、
//      Project Scan Root denylist 与 10 层深度保险、软链接解析、Canonical Path 去重防环、
//      SKILL.md 解析校验与原文读取、Git 工作树根检测（.git 存在性）、
//      复制投影内容指纹（确定性、fail closed）、Scan Issue。
//      does not own 身份归因与指纹聚合（归 Identity）、Git 子进程（归 Git seam，#19）。
// TEST: repo://PaguguTests/DiscoveryTests.swift（scratch 扫描测试）。
// IN: Personal 与 Project Scan Root 路径列表；OUT: ScanResult（skills + issues + outcome）。

/// Discovery Scan 的产物状态（#3 resolution §8）。
enum ScanOutcome: Sendable {
    case complete
    case partial
    case failed
}

/// 跳过的单项问题：不可读目录、断链、不可解析的 SKILL.md 等。
struct ScanIssue: Sendable, Equatable {
    let path: String
    let reason: String
}

enum DiscoveryOrigin: Sendable, Equatable {
    case personalSkillRoot
    case projectScanRoot
}

/// Discovery Scan 发现的一个候选 Skill（未归因，只产出事实）。
struct DiscoveredSkill: Sendable, Equatable {
    /// as-found 路径（展示用）。
    let asFoundPath: String
    /// 完全解析软链接后的绝对路径（归因与去重用）。
    let canonicalPath: String
    /// frontmatter `name`（展示元数据，不参与身份）。
    let name: String
    /// 发现入口。Identity 用它区分安装投影与纯来源 Skill。
    let origin: DiscoveryOrigin
    /// 包含 canonicalPath 的最内层 Git 工作树根的 canonical 路径；不在任何工作树内为 nil（复制投影）。
    let repositoryRootPath: String?
    /// Skill 目录的确定性内容指纹；nil = 已归因（不需要）或读取不完整（不可参与聚合）。
    /// 只用于复制投影之间的呈现聚合，永不用于来源归因。
    let contentFingerprint: String?

    init(
        asFoundPath: String,
        canonicalPath: String,
        name: String,
        origin: DiscoveryOrigin = .personalSkillRoot,
        repositoryRootPath: String? = nil,
        contentFingerprint: String? = nil
    ) {
        self.asFoundPath = asFoundPath
        self.canonicalPath = canonicalPath
        self.name = name
        self.origin = origin
        self.repositoryRootPath = repositoryRootPath
        self.contentFingerprint = contentFingerprint
    }
}

/// Discovery Scan 的完整产出。
struct ScanResult: Sendable {
    let outcome: ScanOutcome
    let skills: [DiscoveredSkill]
    let issues: [ScanIssue]
    /// Discovery 只证明 `.git` 存在；remote 身份归后续 Git Fact seam。
    let candidateSourceRoots: Set<String>

    init(
        outcome: ScanOutcome,
        skills: [DiscoveredSkill],
        issues: [ScanIssue],
        candidateSourceRoots: Set<String> = []
    ) {
        self.outcome = outcome
        self.skills = skills
        self.issues = issues
        self.candidateSourceRoots = candidateSourceRoots
    }
}

// MARK: - Discovery 扫描入口

enum Discovery {
    static let personalSkillRoots: [String] = [
       ("~/.claude/skills" as NSString).expandingTildeInPath,
       ("~/.agents/skills" as NSString).expandingTildeInPath,
        ("~/.codex/skills" as NSString).expandingTildeInPath,
    ]

    private static let maximumProjectScanDepth = 10
    private static let projectScanDirectoryDenylist: Set<String> = [
        ".build", ".git", ".gradle", ".swiftpm", ".venv",
        "Carthage", "DerivedData", "Pods",
        "build", "dist", "node_modules", "out", "target", "vendor", "venv",
    ]

    /// 扫描指定 Personal Skill Root 列表，产出完整 ScanResult。
    /// Root 不存在时视为正常空态（#3 resolution §8）；其他错误记 Scan Issue 并标记 partial。
    /// Canonical Path 去重仅在同一 root 内防环；跨 root 的同一 Skill 由 Identity 层聚合（ADR-0001 §3）。
    static func scanPersonalRoots(_ roots: [String]) -> ScanResult {
        var skills: [DiscoveredSkill] = []
        var issues: [ScanIssue] = []
        var candidateSourceRoots = Set<String>()
        var hasPartial = false

        for root in roots {
            var canonicals = Set<String>()
            let fm = FileManager.default
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else {
                // 不存在 = 正常空态，不记 Issue
                continue
            }
            scanDirectory(
                root,
                canonicalRoot: resolveCanonical(root),
                origin: .personalSkillRoot,
                depth: 0,
                canonicals: &canonicals,
                skills: &skills,
                issues: &issues,
                candidateSourceRoots: &candidateSourceRoots,
                partial: &hasPartial
            )
        }

        let outcome: ScanOutcome = hasPartial ? .partial : .complete
        return ScanResult(
            outcome: outcome,
            skills: skills,
            issues: issues,
            candidateSourceRoots: candidateSourceRoots.union(skills.compactMap(\.repositoryRootPath))
        )
    }

    /// 扫描单个 Project Scan Root。
    /// Canonical Path 去重仅在本次扫描内防环；跨 root 的同一 Skill 由 Identity 层聚合（ADR-0001 §3）。
    static func scanProjectRoot(_ root: String) -> ScanResult {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else {
            return ScanResult(outcome: .failed, skills: [], issues: [
                ScanIssue(path: root, reason: "目录不存在或不可读")
            ])
        }

        var skills: [DiscoveredSkill] = []
        var issues: [ScanIssue] = []
        var canonicals = Set<String>()
        var candidateSourceRoots = Set<String>()
        var hasPartial = false

        scanDirectory(
            root,
            canonicalRoot: resolveCanonical(root),
            origin: .projectScanRoot,
            depth: 0,
            canonicals: &canonicals,
            skills: &skills,
            issues: &issues,
            candidateSourceRoots: &candidateSourceRoots,
            partial: &hasPartial
        )

        let outcome: ScanOutcome = hasPartial ? .partial : .complete
        return ScanResult(
            outcome: outcome,
            skills: skills,
            issues: issues,
            candidateSourceRoots: candidateSourceRoots.union(skills.compactMap(\.repositoryRootPath))
        )
    }

    /// 一次完整 Discovery Scan：Personal Skill Root 与全部持久 Project Scan Root 共用同一产物。
    static func scanAll(personalRoots: [String], projectRoots: [String]) -> ScanResult {
        let personalResult = scanPersonalRoots(personalRoots)
        let projectResults = projectRoots.map(scanProjectRoot)
        let results = [personalResult] + projectResults
        let hasIncompleteResult = results.contains { result in
            switch result.outcome {
            case .complete: false
            case .partial, .failed: true
            }
        }
        let allProjectRootsFailed = !projectResults.isEmpty && projectResults.allSatisfy { result in
            if case .failed = result.outcome { return true }
            return false
        }
        let outcome: ScanOutcome = personalRoots.isEmpty && allProjectRootsFailed
            ? .failed
            : (hasIncompleteResult ? .partial : .complete)
        return ScanResult(
            outcome: outcome,
            skills: results.flatMap(\.skills),
            issues: results.flatMap(\.issues),
            candidateSourceRoots: Set(results.flatMap(\.candidateSourceRoots))
        )
    }

    // MARK: - 递归遍历

    /// L4 IN: `depth` 以当前 as-found root 为 0；origin 决定扫描几何；canonicalRoot 用于识别软链接目标。
    /// OUT: 追加发现事实；Project Scan Root 命中 denylist 时追加 Scan Issue，第 11 层另标记 partial。
    /// INVARIANT: Project Scan Root 只扫描 0...10 层，as-found 与 canonical 遍历路径均不能绕过 denylist；
    ///            Personal Skill Root 不套用该策略；两者都保持命中 Skill 后叶子停止与 Canonical Path 防环。
    /// TEST: repo://PaguguTests/DiscoveryTests.swift（denylist、软链接别名、深度 10 边界、隐藏目录与防环）。
    private static func scanDirectory(
        _ path: String,
        canonicalRoot: String,
        origin: DiscoveryOrigin,
        depth: Int,
        canonicals: inout Set<String>,
        skills: inout [DiscoveredSkill],
        issues: inout [ScanIssue],
        candidateSourceRoots: inout Set<String>,
        partial: inout Bool
    ) {
        let fm = FileManager.default
        let canonical = resolveCanonical(path)
        guard canonicals.insert(canonical).inserted else {
            return
        }
        if fm.fileExists(atPath: (path as NSString).appendingPathComponent(".git")) {
            candidateSourceRoots.insert(canonical)
        }
        let skillMD = (path as NSString).appendingPathComponent("SKILL.md")

        if fm.fileExists(atPath: skillMD) {
            // 命中 Skill：解析 frontmatter，叶子停止
            if let parsed = parseSkillMD(
                at: skillMD,
                asFoundPath: path,
                canonicalPath: canonical,
                origin: origin
            ) {
                let repositoryRoot = enclosingWorkTreeRoot(of: canonical)
                // 内容指纹只为复制投影计算（已归因 Skill 由 Skill Identity 裁决，ADR-0001 §3）；
                // 读取不完整 fail closed：不产出可合并指纹并记录 Scan Issue。
                var fingerprint: String? = nil
                if repositoryRoot == nil {
                    fingerprint = contentFingerprint(ofSkillAtCanonicalPath: canonical)
                    if fingerprint == nil {
                        issues.append(ScanIssue(
                            path: path,
                            reason: "Skill 内容读取不完整，无法计算内容指纹；该复制安装不参与聚合"
                        ))
                        partial = true
                    }
                }
                skills.append(DiscoveredSkill(
                    asFoundPath: parsed.asFoundPath,
                    canonicalPath: parsed.canonicalPath,
                    name: parsed.name,
                    origin: parsed.origin,
                    repositoryRootPath: repositoryRoot,
                    contentFingerprint: fingerprint
                ))
            } else {
                issues.append(ScanIssue(path: path, reason: "SKILL.md 不可解析（frontmatter 缺失或格式错误）"))
                partial = true
            }
            return // 命中 Skill 后叶子停止
        }

        // 非 Skill 目录：继续递归子目录
        let children: [String]
        do {
            children = try fm.contentsOfDirectory(atPath: path)
        } catch {
            issues.append(ScanIssue(path: path, reason: "目录不可读：\(error.localizedDescription)"))
            partial = true
            return
        }

        for child in children.sorted() {
            let childPath = (path as NSString).appendingPathComponent(child)

            // 跟随软链接后的 canonical 路径用于防环
            let canonical = resolveCanonical(childPath)
            if canonicals.contains(canonical) {
                continue // 环或重复，跳过
            }

            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: childPath, isDirectory: &isDir)
            guard exists, isDir.boolValue else {
                if !exists, (try? fm.destinationOfSymbolicLink(atPath: childPath)) != nil {
                    issues.append(ScanIssue(path: childPath, reason: "软链接目标不存在或不可访问"))
                    partial = true
                }
                continue // 跳过非目录条目
            }

            if origin == .projectScanRoot,
               let deniedName = deniedProjectDirectoryName(
                   asFoundName: child,
                   canonicalPath: canonical,
                   canonicalRoot: canonicalRoot
               ) {
                issues.append(ScanIssue(
                    path: childPath,
                    reason: "Project Scan Root denylist 已跳过目录：\(deniedName)"
                ))
                // denylist 定义可信扫描几何；Issue 让排除可见，但不把预期排除误判为不完整。
                continue
            }

            let childDepth = depth + 1
            if origin == .projectScanRoot, childDepth > maximumProjectScanDepth {
                issues.append(ScanIssue(
                    path: childPath,
                    reason: "Project Scan Root 已达到 \(maximumProjectScanDepth) 层深度上限"
                ))
                partial = true
                continue
            }
            // Personal Skill Root 仍只跳过 Git 内部目录，不套用 Project Scan Root denylist 或深度上限。
            if child == ".git" { continue }

            scanDirectory(
                childPath,
                canonicalRoot: canonicalRoot,
                origin: origin,
                depth: childDepth,
                canonicals: &canonicals,
                skills: &skills,
                issues: &issues,
                candidateSourceRoots: &candidateSourceRoots,
                partial: &partial
            )
        }
    }

    private static func deniedProjectDirectoryName(
        asFoundName: String,
        canonicalPath: String,
        canonicalRoot: String
    ) -> String? {
        if projectScanDirectoryDenylist.contains(asFoundName) {
            return asFoundName
        }

        let rootComponents = (canonicalRoot as NSString).pathComponents
        let pathComponents = (canonicalPath as NSString).pathComponents
        let sharedPrefixCount = zip(rootComponents, pathComponents)
            .prefix { $0.0 == $0.1 }
            .count
        return pathComponents
            .dropFirst(sharedPrefixCount)
            .first { projectScanDirectoryDenylist.contains($0) }
    }

    // MARK: - Canonical Path

    /// `realpath` 完全解析软链接后的绝对路径；解析失败时回退到原始路径。
    static func resolveCanonical(_ path: String) -> String {
        (path as NSString).resolvingSymlinksInPath
    }

    // MARK: - Git 工作树根检测（文件系统事实；Git 子进程 seam 归 #19）

    /// 返回包含 canonicalPath 的最内层 Git 工作树根：自该路径向上找第一个含 `.git` 条目
    /// （目录或文件）的目录；不在任何工作树内返回 nil（复制投影，ADR-0001 §4）。
    /// 这是纯文件系统事实，不调用 git 子进程。
    static func enclosingWorkTreeRoot(of canonicalPath: String) -> String? {
        let fm = FileManager.default
        var dir = canonicalPath
        while true {
            if fm.fileExists(atPath: (dir as NSString).appendingPathComponent(".git")) {
                return dir
            }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir { return nil }
            dir = parent
        }
    }

    // MARK: - 内容指纹（复制投影聚合的事实基础；fail closed）

    /// 计算 Skill 目录的确定性内容指纹：覆盖目录内全部常规文件的相对路径与字节，
    /// 按相对路径排序后 SHA-256；软链接只记录链接目标字符串，绝不跟随（不读 Skill 目录外内容）。
    /// 任何条目读取失败或遇到非常规文件类型（socket/pipe/设备等）返回 nil——
    /// nil 表示内容未知，调用方记 Scan Issue 且该复制不参与聚合（fail closed）。
    static func contentFingerprint(ofSkillAtCanonicalPath path: String) -> String? {
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: path, isDirectory: true)
        // .producesRelativePathURLs：枚举器会把根解析到真实路径（/tmp→/private/tmp 等），
        // 相对路径只能由枚举器自身给出，不能用字符串前缀自算。
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey],
            options: [.producesRelativePathURLs]
        ) else { return nil }

        enum EntryPayload { case file(Data), symlink(String) }
        var entries: [(relativePath: String, payload: EntryPayload)] = []

        for case let url as URL in enumerator {
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
            } catch {
                return nil
            }
            // 目录不贡献字节（其存在由文件相对路径隐含）；其余类型分支落空即 fail closed
            if values.isDirectory == true { continue }
            let relativePath = url.relativePath

            if values.isSymbolicLink == true {
                // 只记录链接目标字符串，绝不解析跟随
                guard let dest = try? fm.destinationOfSymbolicLink(atPath: url.path) else { return nil }
                entries.append((relativePath, .symlink(dest)))
            } else if values.isRegularFile == true {
                guard let data = try? Data(contentsOf: url) else { return nil }
                entries.append((relativePath, .file(data)))
            } else {
                return nil // 非常规或未知文件类型：内容未知
            }
        }

        entries.sort { $0.relativePath < $1.relativePath }

        var hasher = SHA256()
        for entry in entries {
            hasher.update(data: Data(entry.relativePath.utf8))
            hasher.update(data: Data([0x00]))
            switch entry.payload {
            case .file(let data):
                hasher.update(data: Data([0x46])) // 'F'
                hasher.update(data: data)
            case .symlink(let dest):
                hasher.update(data: Data([0x4C])) // 'L'
                hasher.update(data: Data(dest.utf8))
            }
            hasher.update(data: Data([0x00]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - SKILL.md 原文读取

    /// 读取指定 canonical 路径下的 SKILL.md 原文（只读展示用）；读取失败返回 nil。
    static func skillMarkdown(atCanonicalPath path: String) -> String? {
        try? String(
            contentsOfFile: (path as NSString).appendingPathComponent("SKILL.md"),
            encoding: .utf8
        )
    }

    // MARK: - SKILL.md frontmatter 解析

    /// 解析顶层精确 `SKILL.md`：要求 frontmatter 起止分隔符完整，且 `name`、`description` 均非空白。
    /// 不合格候选由扫描入口记为 Scan Issue，不进入 Skill 列表。展示名取 frontmatter `name`。
    private static func parseSkillMD(
        at path: String,
        asFoundPath: String,
        canonicalPath: String,
        origin: DiscoveryOrigin
    ) -> DiscoveredSkill? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil // 无 frontmatter 开头
        }

        var name: String?
        var description: String?
        var hasClosingDelimiter = false

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                hasClosingDelimiter = true
                break
            }

            if trimmed.hasPrefix("name:") {
                name = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("description:") {
                description = String(trimmed.dropFirst(12)).trimmingCharacters(in: .whitespaces)
            }
        }

        guard hasClosingDelimiter,
              let resolvedName = name,
              !resolvedName.isEmpty,
              description?.isEmpty == false else {
            return nil
        }

        return DiscoveredSkill(
            asFoundPath: asFoundPath,
            canonicalPath: canonicalPath,
            name: resolvedName,
            origin: origin
        )
    }
}
