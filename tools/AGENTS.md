# tools

L2 模块地图。父级：repo://AGENTS.md。

## 本次新增检查入口

- `check-structure.sh`：结构阈值报告；用 `bash tools/check-structure.test.sh` 验证。
- `check-structure.test.sh`：结构阈值行为检查。
- `check-skills.sh`：用户级 Skill 就绪检查；用 `bash tools/check-skills.test.sh` 验证。
- `check-skills.test.sh`：Skill 缺口报告与退出码检查。

脚本直接运行；结构检查默认只报告 warn，Skill 缺失明确失败。
