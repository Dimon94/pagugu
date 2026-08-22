# Issue tracker

Pagugu 计划使用 GitHub Issues，项目坐标为 `Dimon94/pagugu`：

```text
https://github.com/Dimon94/pagugu
```

公开远程仓库已创建。Issues 与 Wayfinder labels 可用；本地代码尚未推送，远程默认分支、PR 与 Actions 状态均为 Unknown。

## 约定

- 远程读取使用 GitHub Web 或 `gh issue view/list`。
- 创建、评论、关闭、打标、建仓、push、PR 与 workflow 写操作必须在执行前取得明确授权。
- 自动化写入后立即用独立读取命令验证远程状态。
- triage 五个 canonical 角色与 label 映射见 repo://docs/agents/triage-labels.md。

## Pull requests as a triage surface

**PRs as a request surface: no.**

## Skill 语义

当 skill 说 `publish to the issue tracker`，表示在本仓 GitHub Issues 创建 issue；该动作需要当次明确远程写入授权。

当 skill 说 `fetch the relevant ticket`，使用 `gh issue view <number> --repo Dimon94/pagugu --comments` 读取标题、body、labels、状态与评论。

## 阻断与依赖

在项目建立其他 canonical 机制前，阻断语义写入 issue body：

```text
Blocked by: #12 #15
```

判断阻断是否解除时读取被引用 issue 的 live 状态，不凭本地文档或缓存推断。

## Wayfinding 编排

- map：带 `wayfinder:map` label 的 issue。
- 子 ticket：带 `wayfinder:map-<number>` 与一个类型 label；body 首行写 `Map: #<number>`。
- frontier：同一 map 下 open、未 claimed、且 `Blocked by` 均已 closed 的 ticket。
- 认领与 closeout 均为远程写操作，必须取得明确授权并写后读回。

## GitHub Actions

本地 workflow 位于 repo://.github/workflows/ci.yml。代码尚未推送，远程 workflow run 不存在，因此 CI 通过状态为 Unknown。
