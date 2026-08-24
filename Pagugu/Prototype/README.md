# PROTOTYPE / THROWAWAY — MVP 1.0 主窗口闭环原型（issue #10）

本目录是 Wayfinder map #1 / ticket #10 的一次性 UI 原型。它回答的问题是：

> 什么样的主窗口信息架构和交互能让目标用户在不理解软链接或 Git 分支细节的前提下，完成发现、理解关系、维护映射、手动检查、单个安全更新和阻断恢复的完整闭环？

**这不是生产实现，不得直接晋升生产。** 全部状态只在内存；Git、扫描、Registry、Audit 均为 stub；不读写任何真实用户数据。

**Verdict 已确认（2026-08-24，HITL）：Variant F「主从（目录 + 详情 + 原文）」。** 完整裁决、被否决方向、为 #11 的验收场景与剩余 Unknown 见 `Pagugu/Prototype/DECISION.md`。

## 运行

```bash
./script/build_and_run.sh
```

窗口标题为 `Pagugu · PROTOTYPE`。顶部紫色条是原型工具（场景 + 模拟 + 提示），底部浮层切换 variant（也可按 ← / →；文本输入聚焦时不截获方向键）。状态栏入口行为不变：只打开主窗口 / 退出。

## Variants（A–E 已淘汰，F 为 validated verdict）

| Variant | 信息架构核心 | 结局 |
| --- | --- | --- |
| A「Skill 目录」 | Skill 聚合 master-detail | 淘汰：与 B/C 一起被评为「乱」 |
| B「行动工作台」 | 任务/状态队列 | 淘汰 |
| C「来源地图」 | 来源树双栏 | 淘汰 |
| D「单列表」 | Skill 条目 + 分组 bands | 淘汰：条目粒度与更新单位不一致；分组过早暴露筛选决策 |
| E「平铺按仓库」 | 仓库行 + Disclosure 展开 | 淘汰：展开/导航嵌套点击冲突；不如主从直接 |
| **F「主从」** | 左目录（仓库 + 子 Skill + 无仓库 Skill 行）+ 右详情（含 SKILL.md 原文） | **validated verdict** |

各 variant 共用同一内存世界与 workflow 语义（更新确认、映射选择、Registry 受限恢复、审计详情），差异在信息架构与呈现。

## 场景（顶部紫色条切换；切换会重置内存世界）

1. **首次启动**：空 Registry 正常态、Personal Skill Root 自动发现说明、添加 Project Scan Root 引导。
2. **日常闭环**：混合状态；成功更新、dirty 阻断、来源不明映射。
3. **来源映射**：建立映射、失效映射原因与删除、来源移回后自动复活。
4. **检查失败**：逐项发布、fetch 失败覆盖旧观察回「尚未检查」、run 部分完成总结、部分扫描禁用检查入口。
5. **更新与恢复**：成功 / noop / 取消后果 / tip-changed / ff-rejected / 双检出当次选择 / 阻断画廊（其余主状态 + 恢复方向）。
6. **Registry 与审计故障**：损坏与未来版本受限恢复模式、写失败 fail closed、孤儿更新记录「结果未知（已中断）」、清空历史。

## 合同锚点（呈现语义来源，不含布局）

- 12 个 Checkout Git State、reason code、恢复方向：ADR-0004。
- Check Run 全量、逐项发布、失败覆盖、freshness：ADR-0005。
- Update Run 重查→确认精确 SHA→ff-only、失败九类、取消后果、刷新失败独立呈现：ADR-0006。
- 审计三语义面、「当时记录」标注、孤儿呈现、无命令复制/一键重试：ADR-0007。
- Registry 五条稳定用户语义（空 Registry 正常、Scan Root 失效派生、写失败 fail closed、损坏/未来版本受限恢复、清空/重置确认）：ADR-0008。

## 已知省略（prototype 边界）

- 无真实扫描 / Git / 持久化；时间延迟是模拟的。
- Skill 级聚合状态的呈现规则是原型选择（取最高 precedence 检出主状态），最终公开合同归 #5 后续呈现票。
- 无辅助功能审计、无本地化、无错误处理抽象。
