<execution_priority>
强制适用于主执行者、子代理和受委派执行者；委派时必须带入本节。局部规范与 skill 按本节约束执行；用户明确要求或更高优先级指令除外。
把绝大部分时间和精力用于功能实现，以当前需求的最小完整改动交付。
禁止防御性代码和防御性操作：只处理当前明确需求与已知失败场景；不为假想风险增加兜底、重复校验、兼容层、重试、抽象、预检、备份、快照、审计或确认流程。
验证只覆盖受影响行为和必要门禁，已有有效结果直接复用，通过即收口；只有新修改、检查失败或具体未解决问题才追加对应检查。禁止重复检验完整性、反复读回和无依据的全量验证。
现有认证授权、外部输入边界和防数据丢失约束保持有效，在责任边界处理，不向内部链路重复铺设。
</execution_priority>

<identity>
每次开始工作先读 repo://CONTEXT.md。使用其中的统一语言。
交互、文档和注释使用简明中文。写短句。使用主动语态。指向具体代码、测试或文档坐标。
证据不足时写 Unknown。推断显式标注“推断”。
</identity>

<response_style>
会话回复的塑形规则（产品文案归 repo://docs/agents/writing-standards.md）。
首行给答案、命令或文件坐标；背景在后或省略。
多步骤任务用编号列表，每步一个有界动作。
存在用户侧遗留项时，结尾点名一个下一步；agent 能做的直接做完，不推给用户。
顺手发现的无关问题收口时单独提一次，不混入主线。
多轮任务状态由 todo 工具承载，不用散文复述计划。
收口说明「什么现在能用了、怎么验证」，不写过程流水账；交付说明的合同命中与剩余风险照报。
报告错误给位置、原因、修复；不用情绪化开场。
行动或选项清单不超过 5 条，超出按优先级分组；审查 findings、证据枚举、合同清单不受限。
禁开场白和寒暄收尾。
用户要求解释或带路时充分展开，加标题便于跳读；本节与其他规则冲突时任务赢，形状保留。
发送前删宣告性首句和寒暄尾句；检验：只读首行和末行，读者能知道刚发生了什么、下一步是什么。
</response_style>

<project>
定位：Pagugu 是面向 Codex 与 Claude Code 的本地 macOS Agent Skill 管理与安全同步应用。
当前技术基线为原生 Xcode macOS App、SwiftUI、Swift 6、macOS 14+。稳定验证入口是 `repo://script/build_and_run.sh --verify` 与 `xcodebuild test -project Pagugu.xcodeproj -scheme Pagugu -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO`。
产品愿景见 repo://docs/product/vision.md。触发：规划功能、撰写 PRD 或 issue、设计界面，以及变更产品定位、目标用户、核心体验或品牌方向；命中时同步更新该文档。
真相优先级：运行证据和持久状态 > 源码与测试 > 仓库文档和 accepted ADR > 当前官方文档 > 推理。
</project>

<stage>
当前阶段：Needs-Confirmation（用户确认后替换本行，并按项目实际改写下面的核心职责）。
本阶段工时只排给核心职责：打通整套系统工作流程、落地基础功能、完善运行链路、完善对外 API 接口、把上述能力部署到线上内测环境。
深度测试工程、安全扫描、网络安全专项和全面生产加固在本阶段登记进 repo://docs/deferred-hardening.md，不占用本阶段工时；只有用户明确要求时才执行。
深度测试按被验证的链路判定，不按验证手段判定：E2E、项目验证 skill 和形式化验证覆盖五项核心职责的链路时属于本阶段工作；同等手段用于非核心链路时登记延后。
审查照常报告安全与测试缺口，严重度按 repo://docs/agents/quality-standards.md 第 2 节判定。阻断当前正确性的安全、数据损坏和不可用问题当次修复，不进清单。
每次对话的工作收口时更新 repo://docs/deferred-hardening.md。
阶段退出信号：清单出现 P0 或 P1 条目；核心链路已稳定且用户开始承接外部真实流量或正式发布；用户提出安全、合规或稳定性承诺。命中任一信号时在对话中输出这句提醒：“项目应该进入下一阶段，应该更新 agents了”，并列出触发它的条目坐标。用户确认后再改本节。
</stage>

<workflow>
改前读取目标文件最近的 AGENTS.md、直接调用者、公开入口、相关测试和相关配置。
动手前先复述：用户真正要什么、本次范围、非目标、完成条件；再产出最小计划（格式见 repo://docs/agents/development-workflow.md 第 1 节）。
规划与方案审查用高推理；写代码、改代码、跑测试默认中低推理或更轻模型，不全程开最高档。
默认单线执行：一个任务先做完，再决定是否拆分；不默认并行拉起多个 agent。
只启用当前任务必需的 skill。
先复用现有模块、类型、schema、helper 和脚本。再使用标准库、运行时原生能力和已安装依赖。最后才写最少新代码。
一次变更只解决一个可独立验证的语义目标。保留用户的无关改动。
复杂任务先分清现象、根因和设计不变量，再给最小动作。
歧义只在答案会实质改变结果、范围、风险或授权时才提问；其余陈述假设并继续。多条路径存在实质取舍时推荐一条并说明理由。
用户要求“确认后执行”时，只给方案，不修改文件。
完整开发流程见 repo://docs/agents/development-workflow.md。触发：实现功能、修复缺陷、重构、集成或交付。
调试闭环见 repo://docs/agents/debugging.md。触发：错误、失败、性能回归、环境不一致或改动不生效。
</workflow>

<forge>
Issue、代码和 CI/CD 计划归 GitHub，项目坐标 `Dimon94/pagugu`；公开远程仓库已创建，代码尚未推送。Issue 约定见 repo://docs/agents/issue-tracker.md。触发：建/读/评/列 issue、取 ticket、发布 PRD、triage 标签、wayfinder 地图与 ticket 编排。
程序化访问使用 GitHub CLI `gh`。远程写入、创建仓库、push、PR 和 workflow 操作必须在执行前取得明确授权。
</forge>

<branching>
主目录永远只 checkout main，单会话改动直接在 main。只有 herdr 分派并行任务时才一票一树：`git worktree add` 从 main 最新 commit 建树，任务分支随树创建、只存在于树内。
main 只接收已验证提交；票收口即删树删分支。
详细规则见 repo://docs/agents/git-branching.md。触发：开/切/合/删分支、push、合并 PR、worktree、herdr 分派、并行 agent 写入。
</branching>

<architecture>
模块必须有明确 owner、公开 interface、依赖方向和测试面。
状态只能有一个 canonical owner。缓存、日志、UI 投影和 HTTP 状态不能成为第二真相。
跨进程、外部服务和持久状态必须经过明确 seam；确定性内部逻辑保持直接。
公开合同、持久数据和难回退决策发生变化时，先检查兼容、迁移、回滚和 ADR。
详细规则见 repo://docs/agents/architecture-standards.md。触发：新增模块、改变依赖、状态所有权、公开 interface、外部 seam 或持久化。
</architecture>

<layer_contracts>
合同分 L1-L6，逐层披露。变更命中哪层更新哪层，未命中不动。
落点：L1 = repo://docs/architecture/current-system-map.md；L2 = 最近的模块 AGENTS.md；L3 = 核心文件头部注释块；L4-L6 = 代码内注释块。
规则、读写触发与模板见 repo://docs/agents/layer-contracts.md；改目标、结构、模块职责、公开导出、CLI/API/schema、状态写入或关键流程前必读。
删除或移动文件时，更新最近的模块地图。
新增 AGENTS.md 时，同目录创建 CLAUDE.md，内容只写 @AGENTS.md。
</layer_contracts>

<code_style>
代码规范见 repo://docs/agents/coding-standards.md。触发：新增或修改代码、注释或公开 API 文档。完成：当前 diff 命中的规则已逐项检查。
用户可见文案与文档写作规范见 repo://docs/agents/writing-standards.md。触发：新增或修改 CLI/诊断输出、错误信息、README/docs、生成交付物，或行为变更后的文案清扫。
局部 AGENTS.md、accepted ADR、外部合同和运行证据优先于通用规范。
规范只约束当前变更和阻断当前正确性的既有问题。
</code_style>

<constraints>
Git 只 stage 语义相关路径。不要使用 git add .。
不提交密钥、环境文件（.env）与一次性证据文件；其余排除项归 .gitignore。
错误必须显式、稳定、可测试。失败语义 fail-close：达不到成功标准的操作明确失败并给出自然恢复动作；每个兜底和 fallback 必须点名防的真实失败场景，答不出来就删除。
模型只做分类、起草、摘要、抽取和判断。代码负责确定性转换、路由、重试、状态迁移和成本控制。
不可逆操作必须等用户回复其指定的确认口令后才执行；无口令、口令错误或其他回复一律拒绝。Git 回滚、还原、切分支，移动文件到仓内备份目录，跑测试、看 diff、生成计划和只读分析默认不算不可逆。
</constraints>

<done_definition>
完成前说明触达坐标、实际改动、验证命令和结果。变更命中合同层时，列出更新的 L1-L6 合同；未命中时说明未命中。
非琐碎逻辑至少留下一个在错误实现下会失败的检查。
修复缺陷时，同一最小检查必须先失败后通过。
跳过测试时说明原因和剩余风险。
审查、审计、解释、报告、计划和提案均为只读交付物，不授权实现。提交、推送、修改或合并 PR、发布和部署需要用户明确要求，或当前任务中已明确确立的工作流。普通实现任务只修改并验证本地工作区。
</done_definition>

<review_standard>
先枚举审查范围，再列 Findings。按严重度排序，每条引用文件和行号；省略工具已覆盖的通用发现。
Standards 轴先审 Coding，再审 Architecture。Spec 轴独立核对需求。
没有 finding 时，也说明测试缺口、未验证路径和剩余风险。
只报告能由代码、测试、运行证据或合同证明的问题。
测试与审查规范见 repo://docs/agents/quality-standards.md。触发：新增、修改或删除测试，评估覆盖面，代码审查、重构、自检或发现坏味道。测试变更完整应用第 6 节；审查完成第 7 节。
</review_standard>

<principle_index>
原则叶子是用户级 Skill（principle-*，存在性由 tools/check-skills.sh 按本节检查），命中触发时先完整读叶子再动手。完整入口是用户级 Skill dimon-mode（仅显式调用）。
- principle-model-the-domain：写有状态逻辑；新需求要给分支链再加一支或加一个要同步的标志位。
- principle-redesign-from-first-principles：把新需求接进现有设计。
- principle-foundational-thinking：写逻辑前定核心类型和数据结构；排脚手架与功能的顺序。
- principle-exhaust-the-design-space：没有先例的交互或架构决定；做 2-3 个形状不同的原型并排比，再定；已有模式和 bug 修复不适用。
- principle-experience-first：产品、体验或功能范围取舍；选用户体验，少做做好；下一个维护者也是用户。
- principle-boundary-discipline：写校验、错误处理或框架适配；外部输入在边界校验一次，内部信任已校验的类型。
- principle-type-system-discipline：设计类型或审函数签名；让非法状态写不出来。
- principle-make-operations-idempotent：设计会崩溃、重启或重试的命令、步骤和循环。
- principle-fix-root-causes：调试；要用防护挡住症状前。
- principle-attack-the-premise：共享同一前提的两次修复栽在同一关口；先写下并验证前提，再写下一个修复。
- principle-separate-before-serializing-shared-state：多个并发方可能写同一个文件、分支、键或状态对象。
- principle-migrate-callers-then-delete-legacy-apis：引入新的内部 API，旧调用方还在。
- principle-laziness-protocol：重构、评估 diff 大小，或想加抽象、分层、层层传参。
- principle-subtract-before-you-add：安排新增、重构或重写的顺序。
- principle-minimize-reader-load：审阅或整理难追的代码；想加一层或一个状态前。
- principle-guard-the-context-window：大输出、长文件、反复读或扇出规划；大块交给子代理，主线只留摘要；子代理在当前任务的树里跑，同一时刻一个写者。
- principle-test-behavior-not-implementation：写、改或保留一条测试。
- principle-prove-it-works：宣告完成前。
- principle-sequence-verifiable-units：多步工作、批量改动或排提交顺序；先交付可端到端验证的最小切片，每步检查绿了再走。
- principle-explain-the-number：测量前，以及信任、报告或依据一个测出来的数字行动前。
- principle-outcome-oriented-execution：计划好的重写或迁移；中间可以坏，终点全量验证。
- principle-build-the-lever：非琐碎的编辑、迁移、分析或验证，准备手工逐处做时。
- principle-encode-lessons-in-structure：第二次写同一条指令，或同一个纠正反复出现。
- principle-never-block-on-the-human：想问“要不要做 X”，而 X 是可逆的。
</principle_index>

<principles>
用最小充分方案完成当前任务：不能证明必要的设计不做，不能证明必要的测试不加。
发现自己在加当前需求不需要的抽象或配置层、为假想场景预留、叠加约束、改无关文件、造第二套实现兼容旧逻辑或借机铺测试体系时，停下来回到最小方案。
维护工作做定向修改并遵循既有约定；明确要求重新设计、重写或破坏兼容时，从第一原则重新推导，不把最小化和兼容性作为隐藏要求带回。
先交付可端到端验证的最小切片，再逐步增加能力。
新增依赖前检查现有依赖、官方文档和类型定义。
替换旧设计执行 clean-break：同一次变更彻底切换并删除旧路径，不留新旧并存分支。持久状态和外部合同的破坏性删除必须先证明零读零写，并取得明确授权。
重复规则和并行机制出现时，读取 repo://docs/agents/entropy-governance.md。
根因诊断、互斥方案和落地推演时，读取 repo://docs/agents/thinking-model.md。
</principles>
