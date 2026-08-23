// PROTOTYPE / THROWAWAY — issue #10（Wayfinder map #1）
// 本文件是「MVP 1.0 主窗口闭环」的一次性原型：全部状态只在内存，Git/扫描/持久化均为 stub。
// 不读写真實 Skill Source、App Registry 或 Audit 文件；不是生产实现，不得直接晋升。
//
// 原型计划（一行）：MVP 1.0 主窗口的 3 个结构性不同 variant
//   A = Skill 聚合列表 master-detail；B = 行动工作台；C = Skill Source 关系双栏
//   挂在现有主窗口（ContentView 挂载 PrototypeRootView），底部浮层 + ←/→ 切换 variant。
// 运行：./script/build_and_run.sh
//
// 本文件：stub 领域模型 + 场景数据集 + 全部用户动作（检查 / 更新 / 映射 / Registry / 审计）。

import Foundation

// MARK: - 12 个 Checkout Git State（reason code 与 ADR-0004 §6 一致）

enum StubCheckoutState: String, CaseIterable, Identifiable {
    case inspectionFailed = "inspection-failed"
    case noRemote = "no-remote"
    case detached = "detached"
    case noUpstream = "no-upstream"
    case upstreamMismatch = "upstream-mismatch"
    case siblingConflict = "sibling-conflict"
    case checkUnknown = "check-unknown"
    case dirty = "dirty"
    case diverged = "diverged"
    case aheadOnly = "ahead-only"
    case updateAvailable = "update-available"
    case upToDate = "up-to-date"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inspectionFailed: return "无法读取仓库状态"
        case .noRemote: return "没有远程来源"
        case .detached: return "未停留在任何分支上"
        case .noUpstream: return "分支未跟踪远程"
        case .upstreamMismatch: return "跟踪的远程与来源不一致"
        case .siblingConflict: return "分支被另一个工作树占用"
        case .checkUnknown: return "尚未检查"
        case .dirty: return "有未提交的本地改动"
        case .diverged: return "本地与远程已分叉"
        case .aheadOnly: return "本地领先远程"
        case .updateAvailable: return "有更新可用"
        case .upToDate: return "已是最新"
        }
    }

    /// 每个阻断态配一句人工恢复方向（ADR-0004 §9）。非阻断态为 nil。
    var recovery: String? {
        switch self {
        case .inspectionFailed: return "在终端确认该目录仍是完好的 Git 仓库，然后重新扫描。"
        case .noRemote: return "在终端为该仓库添加 origin 远程后才能检查更新；本地内容不受影响。"
        case .detached: return "在终端切回正常分支（例如 git switch main）后重新检查。"
        case .noUpstream: return "在终端为当前分支设置上游分支（git branch --set-upstream-to）后重新检查。"
        case .upstreamMismatch: return "在终端核对并修正该分支的上游远程，使其与 Skill 来源一致后重新检查。"
        case .siblingConflict: return "在另一个工作树中切换到其他分支，然后重新检查。"
        case .checkUnknown: return "点击「检查更新」获取远程状态。"
        case .dirty: return "在终端提交或清理本地改动后重新检查；Pagugu 不会覆盖你的改动。"
        case .diverged: return "在终端处理分叉（合并或变基）后重新检查；Pagugu 不会自动处理。"
        case .aheadOnly, .updateAvailable, .upToDate: return nil
        }
    }

    /// 可扫读分组：把 12 态收敛为 4 组（呈现层分组，合同状态不变）。
    var group: StubStateGroup {
        switch self {
        case .updateAvailable: return .updateReady
        case .upToDate, .aheadOnly: return .settled
        case .checkUnknown: return .unknown
        default: return .needsAttention
        }
    }

    var isEligible: Bool { self == .updateAvailable }

    /// Check Run 中跳过网络检查的本地可判阻断态（ADR-0005 §3）。
    var skipsNetworkCheck: Bool {
        switch self {
        case .noRemote, .detached, .noUpstream, .upstreamMismatch, .siblingConflict, .inspectionFailed:
            return true
        default:
            return false
        }
    }
}

enum StubStateGroup: String, CaseIterable, Identifiable {
    case updateReady = "可更新"
    case needsAttention = "需要处理"
    case unknown = "尚未检查"
    case settled = "无需更新"

    var id: String { rawValue }

    /// 展示顺序：可更新优先，然后是需要处理的，尚未检查，最后无需更新。
    var sortOrder: Int {
        switch self {
        case .updateReady: return 0
        case .needsAttention: return 1
        case .unknown: return 2
        case .settled: return 3
        }
    }
}

// MARK: - Update Run 失败九类（ADR-0006 §9）

enum StubUpdateFailure: String, CaseIterable, Identifiable {
    case lockBusy = "lock-busy"
    case identityChanged = "identity-changed"
    case fetchFailure = "fetch-failure"
    case preconditionChanged = "precondition-changed"
    case tipChanged = "tip-changed"
    case ffRejected = "ff-rejected"
    case commandFailure = "command-failure"
    case verificationFailed = "verification-failed"
    case interruptedUnknown = "interrupted-unknown"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lockBusy: return "仓库正被其他 Git 进程占用"
        case .identityChanged: return "仓库身份在更新过程中发生变化"
        case .fetchFailure: return "无法连接远程仓库"
        case .preconditionChanged: return "更新前状态不再满足条件"
        case .tipChanged: return "确认后远程又出现了新提交"
        case .ffRejected: return "本地与远程在执行瞬间发生分叉"
        case .commandFailure: return "Git 命令执行失败"
        case .verificationFailed: return "更新后校验未通过"
        case .interruptedUnknown: return "更新被中断，结果未知"
        }
    }

    var recovery: String {
        switch self {
        case .lockBusy: return "确认没有其他 Git 进程（终端、编辑器）正在操作该仓库后，重新发起更新。"
        case .identityChanged: return "重新扫描后重新检查，再决定是否更新。"
        case .fetchFailure: return "在终端验证网络与凭证（例如手动 git fetch）后重新发起更新。"
        case .preconditionChanged: return "按当前状态的恢复方向处理后重新发起更新。"
        case .tipChanged: return "重新发起更新即可：Pagugu 会自动重查并给出新的确认计划。"
        case .ffRejected: return "在终端处理分叉后重新检查；Pagugu 不会自动合并或覆盖。"
        case .commandFailure: return "查看当次原始错误信息，在终端核对后重新发起。"
        case .verificationFailed: return "在终端核对仓库当前状态（HEAD、分支、工作区）后重新检查。"
        case .interruptedUnknown: return "重新扫描，按当前 Git 事实处理；不要假设更新已完成。"
        }
    }
}

// MARK: - 安装与归因

enum StubHost: String, CaseIterable, Identifiable {
    case claude = "Claude Code"
    case codex = "Codex"
    var id: String { rawValue }
}

enum StubProjection: String {
    case symlink = "软链接"
    case copy = "复制"
    case repo = "仓库本体"
}

enum StubAttribution {
    case automatic      // 软链接 / 仓库本体：文件系统事实自动归因
    case mapped         // 人工来源映射
}

struct StubInstallation: Identifiable {
    let id: String
    var asFoundPath: String
    var host: StubHost
    var projection: StubProjection
    var attribution: StubAttribution
}

/// Unattributed Installation（「来源不明」）：不参与去重、不可更新、按自身路径单列。
struct StubUnattributed: Identifiable {
    let id: String
    var displayName: String
    var asFoundPath: String
    var host: StubHost
    /// 失效映射呈现：非 nil 表示这里曾有一条人工映射，因该原因失效（记录保留，可显式删除）。
    var invalidMappingReason: String?
    var invalidMappingTargetName: String?
}

// MARK: - 检出 / 来源 / Skill

struct StubObservation {
    var succeeded: Bool
    var completedAt: Date
    var remoteTipSHA: String?
}

struct StubCheckout: Identifiable {
    let id: String
    var path: String           // Canonical Path
    var branch: String
    var upstream: String
    var state: StubCheckoutState
    var behind: Int
    var headSHA: String
    var tipSHA: String
    var observation: StubObservation?
    var isChecking = false
}

struct StubSkillSource: Identifiable {
    let id: String
    var key: String            // Skill Source Key（规范化远程 URL 或 canonical 路径）
    var displayName: String
    var checkouts: [StubCheckout]
}

struct StubSkill: Identifiable {
    let id: String
    var name: String           // 展示元数据（frontmatter name），不参与身份
    var sourceID: String
    var relativePath: String   // 仓内相对路径
    var installations: [StubInstallation]
}

// MARK: - 审计记录（呈现取向的 stub；语义见 ADR-0007）

struct StubAuditRecord: Identifiable {
    enum Kind: String {
        case checkRun = "检查"
        case updateRun = "更新"
        case mapping = "来源映射"
    }

    let id: String
    var kind: Kind
    var time: Date
    var subject: String
    var outcome: String        // complete/partial/failed/success/cancelled/created/deleted
    var outcomeDisplay: String
    var reason: StubUpdateFailure?
    var detail: String
    /// Update Run 开始记录（确认绑定时刻写入）。无 terminal 配对的呈现为「结果未知（已中断）」。
    var isOrphanUpdateStart: Bool
    var planSnapshot: String?
}

// MARK: - Registry stub

enum StubRegistryMode {
    case normal
    case corrupted       // 损坏：quarantine + 阻断式受限恢复
    case futureVersion   // 未知未来版本：fail closed，绝不覆写
}

struct StubScanRoot: Identifiable {
    let id: String
    var path: String
    var isAvailable: Bool  // 派生态：路径不存在/被移动时不可用，记录保留，可显式删除
}

// MARK: - 更新流程（瞬态，不持久）

struct StubUpdatePlan {
    var skillID: String
    var candidateCheckoutIDs: [String]
    var selectedCheckoutID: String
    var sourceKey: String
    var relativePath: String
    var checkoutPath: String
    var branch: String
    var upstream: String
    var headSHA: String
    var targetSHA: String
    var behind: Int
}

enum StubUpdatePhase {
    case rechecking
    case confirming(StubUpdatePlan)
    case applying(StubUpdatePlan)
    case failed(StubUpdateFailure)
}

struct StubUpdateFlow {
    var skillID: String
    var phase: StubUpdatePhase
}

/// 场景对更新结果的预设（让成功 / noop / 各失败类可复现）。
enum StubUpdateRig {
    case success
    case noopNowUpToDate                       // 重查时别人已更新过：直接告知「已是最新」
    case recheckBlocked(StubCheckoutState)     // 重查命中阻断态：不弹确认
    case failAfterConfirm(StubUpdateFailure)   // 确认后失败（tip-changed / ff-rejected 等）
    case successThenRefreshFailed              // 更新成功但刷新列表失败（独立呈现）
}

// MARK: - 检查运行（瞬态）

struct StubCheckRun {
    var total: Int
    var finished: Int
    var failed: Int
    var skipped: Int

    var isRunning: Bool { finished < total }
}

// MARK: - 场景

enum StubScenario: String, CaseIterable, Identifiable {
    case firstLaunch = "首次启动"
    case dailyLoop = "日常闭环"
    case mapping = "来源映射"
    case checkFailure = "检查失败"
    case updateRecovery = "更新与恢复"
    case registryFaults = "Registry 与审计故障"

    var id: String { rawValue }

    var guide: String {
        switch self {
        case .firstLaunch:
            return "空 Registry 是正常态，不是错误。试试：① 阅读引导；② 添加 Project Scan Root（原型提供两个假路径）；③ 观察列表多出一个「仅来源」Skill；④ 点「检查更新」。"
        case .dailyLoop:
            return "典型一天：找一个「有更新可用」的 Skill 完成一次更新；找一个「有未提交的本地改动」的看清恢复方向；找一个「来源不明」的安装建立映射。"
        case .mapping:
            return "来源映射全流程：① 给「来源不明」的复制安装指定来源；② 看失效映射（来源目录被移动）的原因与删除动作；③ 点「模拟：来源目录移回并重新扫描」看映射自动复活。"
        case .checkFailure:
            return "手动检查的部分失败：点「检查更新」，观察逐项发布；网络失败的检出回到「尚未检查」并给出原因；run 总结为「部分完成」。也可试「模拟部分扫描结果」看检查入口被禁用。"
        case .updateRecovery:
            return "更新全谱：git-commit = 成功；docx = 重查发现已是新（noop）；release-notes = 两个检出都可更新，发起时需选一个；pdf-tools = 确认后远程又变了（tip-changed）；frontend-design = 执行瞬间分叉（ff-rejected）；阻断画廊看其余状态的恢复方向。试试取消确认的后果。"
        case .registryFaults:
            return "故障与历史：① 用「模拟」菜单切换 Registry 损坏 / 未来版本，看受限恢复模式；② 打开「模拟写失败」后添加 Scan Root 或建映射，看 fail closed；③ 最近活动里找一条「结果未知（已中断）」的孤儿记录；④ 清空历史。"
        }
    }
}

// MARK: - PrototypeWorld：全部内存状态的唯一 owner（prototype-only）

@MainActor
@Observable
final class PrototypeWorld {
    private(set) var scenario: StubScenario = .dailyLoop

    var skills: [StubSkill] = []
    var sources: [StubSkillSource] = []
    var unattributed: [StubUnattributed] = []
    var scanRoots: [StubScanRoot] = []
    var audit: [StubAuditRecord] = []

    var registryMode: StubRegistryMode = .normal
    var simulateRegistryWriteFailure = false
    var scanIsPartial = false

    var checkRun: StubCheckRun?
    var update: StubUpdateFlow?
    var notice: String?

    /// 待映射的 Unattributed 条目 id；非 nil 时由 Root 弹出映射选择。
    var mappingDraftID: String?

    private var updateRigs: [String: StubUpdateRig] = [:]
    private var checkFailRigs: Set<String> = []
    private var checkReveal: [String: StubCheckoutState] = [:]

    init() {
        load(.dailyLoop)
    }

    // MARK: 查询

    func source(for skill: StubSkill) -> StubSkillSource? {
        sources.first { $0.id == skill.sourceID }
    }

    func checkout(_ id: String) -> StubCheckout? {
        sources.lazy.flatMap(\.checkouts).first { $0.id == id }
    }

    /// Skill 状态 = 其来源全部检出中 precedence 最高的主状态（呈现层聚合，合同归 #5 后续票）。
    func primaryState(for skill: StubSkill) -> StubCheckoutState? {
        guard let source = source(for: skill) else { return nil }
        let order: [StubCheckoutState] = StubCheckoutState.allCases
        return source.checkouts.compactMap(\.state).min { a, b in
            order.firstIndex(of: a)! < order.firstIndex(of: b)!
        }
    }

    func eligibleCheckouts(for skill: StubSkill) -> [StubCheckout] {
        source(for: skill)?.checkouts.filter { $0.state.isEligible } ?? []
    }

    var hasRunningWork: Bool {
        checkRun?.isRunning == true || update != nil
    }

    /// 检查入口可用性（ADR-0005 §2：完整 Scan Result 前置 gate；run 中互斥）。
    var canStartCheckRun: Bool {
        !scanIsPartial && checkRun?.isRunning != true && update == nil && registryMode == .normal
    }

    var lastObservationTime: Date? {
        sources.flatMap(\.checkouts).compactMap(\.observation?.completedAt).max()
    }

    // MARK: 场景装载

    func load(_ newScenario: StubScenario) {
        scenario = newScenario
        skills = []; sources = []; unattributed = []; scanRoots = []; audit = []
        registryMode = .normal
        simulateRegistryWriteFailure = false
        scanIsPartial = false
        checkRun = nil; update = nil; notice = nil; mappingDraftID = nil
        updateRigs = [:]; checkFailRigs = []; checkReveal = [:]

        switch newScenario {
        case .firstLaunch: loadFirstLaunch()
        case .dailyLoop: loadDailyLoop()
        case .mapping: loadMapping()
        case .checkFailure: loadCheckFailure()
        case .updateRecovery: loadUpdateRecovery()
        case .registryFaults: loadRegistryFaults()
        }
    }

    private static let personalRootsNote = "~/.claude/skills · ~/.agents/skills · ~/.codex/skills"

    private func loadFirstLaunch() {
        // 空 Registry：无 Project Scan Root、无映射、无观察记录；三个 Personal Skill Root 已自动发现。
        scanRoots = []
        let s1 = source("src-myskills", key: "github.com/dimon94/my-skills", name: "my-skills", checkouts: [
            checkout("co-myskills-1", path: "~/Code/my-skills", state: .checkUnknown, behind: 0,
                     head: "a1b2c3d", tip: "a1b2c3d", observation: nil),
        ])
        sources = [s1]
        skills = [
            skill("sk-git-commit", name: "git-commit", sourceID: "src-myskills", path: "skills/git-commit", installations: [
                inst("in-gc-claude", path: "~/.claude/skills/git-commit", host: .claude, projection: .symlink),
            ]),
        ]
        unattributed = [
            StubUnattributed(id: "ua-gc-codex", displayName: "git-commit",
                             asFoundPath: "~/.codex/skills/git-commit", host: .codex,
                             invalidMappingReason: nil, invalidMappingTargetName: nil),
        ]
        audit = []
        notice = "已自动发现三个 Personal Skill Root（\(Self.personalRootsNote)），无需理解目录结构。"
    }

    private func loadDailyLoop() {
        scanRoots = [
            StubScanRoot(id: "sr-code", path: "~/Code", isAvailable: true),
            StubScanRoot(id: "sr-old", path: "~/Code-old", isAvailable: false),
        ]
        sources = [
            source("src-myskills", key: "github.com/dimon94/my-skills", name: "my-skills", checkouts: [
                checkout("co-myskills-1", path: "~/Code/my-skills", state: .updateAvailable, behind: 3,
                         head: "a1b2c3d", tip: "e4f5g6h", hours: 2),
            ]),
            source("src-awesome", key: "github.com/acme/awesome-skills", name: "awesome-skills", checkouts: [
                checkout("co-awesome-1", path: "~/Code/awesome-skills", state: .dirty, behind: 0,
                         head: "b2c3d4e", tip: "b2c3d4e", hours: 2),
                checkout("co-awesome-2", path: "~/Work/awesome-skills", state: .updateAvailable, behind: 1,
                         head: "b2c3d4e", tip: "f5g6h7i", hours: 2),
            ]),
            source("src-helper-a", key: "github.com/org-a/helper", name: "helper (org-a)", checkouts: [
                checkout("co-helper-a", path: "~/Code/helper-a", state: .diverged, behind: 2,
                         head: "c3d4e5f", tip: "g6h7i8j", hours: 2),
            ]),
            source("src-helper-b", key: "github.com/org-b/helper", name: "helper (org-b)", checkouts: [
                checkout("co-helper-b", path: "~/Code/helper-b", state: .checkUnknown, behind: 0,
                         head: "d4e5f6g", tip: "d4e5f6g", observation: nil),
            ]),
            source("src-local-lab", key: "/Users/dimon/Code/local-lab", name: "local-lab（无远程）", checkouts: [
                checkout("co-local-lab", path: "~/Code/local-lab", state: .noRemote, behind: 0,
                         head: "e5f6g7h", tip: "e5f6g7h", observation: nil),
            ]),
            source("src-doc-suite", key: "github.com/acme/doc-suite", name: "doc-suite", checkouts: [
                checkout("co-doc-suite", path: "~/Code/doc-suite", state: .upToDate, behind: 0,
                         head: "f6g7h8i", tip: "f6g7h8i", hours: 2),
            ]),
            source("src-broken", key: "github.com/acme/old-stuff", name: "old-stuff", checkouts: [
                checkout("co-broken", path: "~/Code/old-stuff", state: .inspectionFailed, behind: 0,
                         head: "—", tip: "—", observation: nil),
            ]),
        ]
        skills = [
            skill("sk-git-commit", name: "git-commit", sourceID: "src-myskills", path: "skills/git-commit", installations: [
                inst("in-gc-claude", path: "~/.claude/skills/git-commit", host: .claude, projection: .symlink),
            ]),
            skill("sk-pdf-tools", name: "pdf-tools", sourceID: "src-myskills", path: "skills/pdf-tools", installations: [
                inst("in-pdf-agents", path: "~/.agents/skills/pdf-tools", host: .codex, projection: .symlink),
            ]),
            skill("sk-wayfinder", name: "wayfinder", sourceID: "src-myskills", path: "skills/wayfinder", installations: []),
            skill("sk-frontend-design", name: "frontend-design", sourceID: "src-awesome", path: "skills/frontend-design", installations: [
                inst("in-fd-claude", path: "~/.claude/skills/frontend-design", host: .claude, projection: .symlink),
                inst("in-fd-demo", path: "~/Code/demo/.claude/skills/frontend-design", host: .claude, projection: .symlink),
            ]),
            skill("sk-helper-a", name: "helper", sourceID: "src-helper-a", path: "skills/helper", installations: [
                inst("in-helper-a", path: "~/.claude/skills/helper", host: .claude, projection: .symlink),
            ]),
            skill("sk-helper-b", name: "helper", sourceID: "src-helper-b", path: "skills/helper", installations: [
                inst("in-helper-b", path: "~/.agents/skills/helper", host: .codex, projection: .symlink),
            ]),
            skill("sk-scratch", name: "scratch-notes", sourceID: "src-local-lab", path: "scratch-notes", installations: [
                inst("in-scratch", path: "~/.codex/skills/scratch-notes", host: .codex, projection: .symlink),
            ]),
            skill("sk-docx", name: "docx", sourceID: "src-doc-suite", path: "skills/docx", installations: [
                inst("in-docx", path: "~/.claude/skills/docx", host: .claude, projection: .symlink),
            ]),
            skill("sk-old-tool", name: "old-tool", sourceID: "src-broken", path: "old-tool", installations: [
                inst("in-old-tool", path: "~/.claude/skills/old-tool", host: .claude, projection: .symlink),
            ]),
        ]
        unattributed = [
            StubUnattributed(id: "ua-gc-codex", displayName: "git-commit",
                             asFoundPath: "~/.codex/skills/git-commit", host: .codex,
                             invalidMappingReason: nil, invalidMappingTargetName: nil),
        ]
        audit = [
            auditRecord("au-1", kind: .checkRun, hoursAgo: 2, subject: "全量检查（7 个检出）",
                        outcome: "complete", outcomeDisplay: "全部完成", detail: "应检查 5 · 成功 5 · 本地可判跳过 2"),
            auditRecord("au-2", kind: .mapping, hoursAgo: 26, subject: "~/.agents/skills/pdf-tools",
                        outcome: "created", outcomeDisplay: "已建立", detail: "映射到 my-skills 的 skills/pdf-tools"),
        ]
        updateRigs = ["sk-git-commit": .success, "sk-pdf-tools": .success, "sk-frontend-design": .success]
    }

    private func loadMapping() {
        loadDailyLoop()
        // 两个来源不明：一个从未映射，一个映射失效（来源目录被移动）。
        unattributed = [
            StubUnattributed(id: "ua-gc-codex", displayName: "git-commit",
                             asFoundPath: "~/.codex/skills/git-commit", host: .codex,
                             invalidMappingReason: nil, invalidMappingTargetName: nil),
            StubUnattributed(id: "ua-report", displayName: "weekly-report",
                             asFoundPath: "~/.claude/skills/weekly-report", host: .claude,
                             invalidMappingReason: "来源目录不存在或已移动（~/Code/report-skill）",
                             invalidMappingTargetName: "report-skill 的 skills/weekly-report"),
        ]
        audit.insert(auditRecord("au-m1", kind: .mapping, hoursAgo: 3, subject: "~/.claude/skills/weekly-report",
                                 outcome: "created", outcomeDisplay: "已建立",
                                 detail: "映射到 report-skill 的 skills/weekly-report（现已失效）"), at: 0)
        notice = "weekly-report 的映射已失效：来源目录被移动。映射记录保留，来源移回后自动复活。"
    }

    private func loadCheckFailure() {
        loadDailyLoop()
        // co-myskills-1 / co-helper-b 正常；co-helper-a 的 fetch 将失败（网络）。
        checkFailRigs = ["co-helper-a"]
        checkReveal = ["co-helper-b": .updateAvailable]
        audit = [auditRecord("au-c1", kind: .checkRun, hoursAgo: 20, subject: "全量检查（7 个检出）",
                             outcome: "partial", outcomeDisplay: "部分完成",
                             detail: "应检查 5 · 成功 4 · 失败 1 · 本地可判跳过 2")]
        notice = "本场景中 helper (org-a) 的远程将无法连接，用于演示部分失败。"
    }

    private func loadUpdateRecovery() {
        loadDailyLoop()
        // 阻断画廊：把各来源调成不同阻断态，覆盖其余主状态。
        setState("co-awesome-1", .dirty); setState("co-awesome-2", .dirty)
        setState("co-helper-a", .detached)
        setState("co-helper-b", .noUpstream)
        setState("co-local-lab", .noRemote)
        setState("co-doc-suite", .siblingConflict)
        setState("co-broken", .upstreamMismatch)
        // 双可更新检出的 Skill：发起更新时当次选择一个。
        let two = source("src-two-homes", key: "github.com/acme/two-homes", name: "two-homes", checkouts: [
            checkout("co-two-1", path: "~/Code/two-homes", state: .updateAvailable, behind: 2,
                     head: "aa11bb22", tip: "cc33dd44", hours: 1),
            checkout("co-two-2", path: "~/Work/two-homes", state: .updateAvailable, behind: 2,
                     head: "aa11bb22", tip: "cc33dd44", hours: 1),
        ])
        sources.append(two)
        skills.append(skill("sk-release-notes", name: "release-notes", sourceID: "src-two-homes",
                            path: "skills/release-notes", installations: [
            inst("in-rn", path: "~/.claude/skills/release-notes", host: .claude, projection: .symlink),
        ]))
        // ahead-only 示例。
        let ahead = source("src-ahead", key: "github.com/dimon94/experiments", name: "experiments", checkouts: [
            checkout("co-ahead", path: "~/Code/experiments", state: .aheadOnly, behind: 0,
                     head: "ff00ee11", tip: "dd22cc33", hours: 1),
        ])
        sources.append(ahead)
        skills.append(skill("sk-lab-notes", name: "lab-notes", sourceID: "src-ahead",
                            path: "skills/lab-notes", installations: [
            inst("in-lab", path: "~/.agents/skills/lab-notes", host: .codex, projection: .symlink),
        ]))
        updateRigs = [
            "sk-git-commit": .success,
            "sk-pdf-tools": .failAfterConfirm(.tipChanged),
            "sk-frontend-design": .failAfterConfirm(.ffRejected),
            "sk-release-notes": .successThenRefreshFailed,
        ]
        // docx 在本场景中先显示有可更新，重查时发现已是新（noop）：独立来源避免与阻断画廊冲突。
        let doc = source("src-doc-suite2", key: "github.com/acme/doc-suite", name: "doc-suite", checkouts: [
            checkout("co-doc2", path: "~/Code/doc-suite", state: .updateAvailable, behind: 1,
                     head: "0a1b2c3", tip: "4d5e6f7", hours: 1),
        ])
        sources.append(doc)
        skills.append(skill("sk-docx2", name: "docx", sourceID: "src-doc-suite2", path: "skills/docx", installations: [
            inst("in-docx2", path: "~/.codex/skills/docx", host: .codex, projection: .symlink),
        ]))
        updateRigs["sk-docx2"] = .noopNowUpToDate
        notice = "每个可更新 Skill 的更新结果已预设为不同走向，逐个尝试即可看全成功、noop、取消与失败恢复。"
    }

    private func loadRegistryFaults() {
        loadDailyLoop()
        audit = [
            auditRecord("au-r1", kind: .updateRun, hoursAgo: 1, subject: "git-commit",
                        outcome: "success", outcomeDisplay: "成功",
                        detail: "fast-forward 到 e4f5g6h（落后 3 个提交）"),
            auditRecord("au-r2", kind: .updateRun, hoursAgo: 5, subject: "frontend-design",
                        outcome: "unknown", outcomeDisplay: "结果未知（已中断）",
                        reason: .interruptedUnknown,
                        detail: "只有开始记录，没有结果记录：App 可能在更新过程中退出。",
                        isOrphanUpdateStart: true,
                        planSnapshot: "计划：~/Work/awesome-skills 从 b2c3d4e fast-forward 到 f5g6h7i（当时记录）"),
            auditRecord("au-r3", kind: .updateRun, hoursAgo: 8, subject: "pdf-tools",
                        outcome: "failed", outcomeDisplay: "失败",
                        reason: .fetchFailure,
                        detail: "无法连接远程仓库（当时记录）"),
            auditRecord("au-r4", kind: .updateRun, hoursAgo: 9, subject: "pdf-tools",
                        outcome: "cancelled", outcomeDisplay: "已取消",
                        detail: "确认前取消；该检出按当时规则回到「尚未检查」（当时记录）"),
            auditRecord("au-r5", kind: .checkRun, hoursAgo: 26, subject: "全量检查（7 个检出）",
                        outcome: "complete", outcomeDisplay: "全部完成", detail: "应检查 5 · 成功 5 · 本地可判跳过 2"),
        ]
        notice = "用顶部「模拟」菜单制造 Registry 损坏 / 未来版本 / 写失败；下方「最近活动」含一条孤儿更新记录。"
    }

    // MARK: 动作：扫描与 Scan Root

    func addScanRoot(_ path: String) {
        guard registryMode == .normal else { return }
        if simulateRegistryWriteFailure { registryWriteFailed(); return }
        scanRoots.append(StubScanRoot(id: "sr-\(scanRoots.count)", path: path, isAvailable: true))
        notice = "已保存 Project Scan Root \(path)。重新扫描后发现 1 个仅来源 Skill（wayfinder，无安装）。"
        if scenario == .firstLaunch, !skills.contains(where: { $0.id == "sk-wayfinder" }) {
            skills.append(skill("sk-wayfinder", name: "wayfinder", sourceID: "src-myskills",
                                path: "skills/wayfinder", installations: []))
        }
    }

    func removeScanRoot(_ id: String) {
        if simulateRegistryWriteFailure { registryWriteFailed(); return }
        scanRoots.removeAll { $0.id == id }
        notice = "已删除该 Scan Root 主张；其下映射与观察记录按合同保留，不级联删除。"
    }

    func rescan() {
        scanIsPartial = false
        notice = "已重新扫描（stub）：当前 Scan Result 完整。"
    }

    func simulatePartialScan() {
        scanIsPartial = true
        notice = "模拟：扫描结果不完整（部分目录不可读）。检查与更新入口已禁用，恢复动作是重新扫描或处理扫描问题。"
    }

    // MARK: 动作：Check Run

    func startCheckRun() {
        guard canStartCheckRun else { return }
        let targets = sources.flatMap(\.checkouts).filter { !$0.state.skipsNetworkCheck }
        let skipped = sources.flatMap(\.checkouts).count - targets.count
        checkRun = StubCheckRun(total: targets.count, finished: 0, failed: 0, skipped: skipped)
        for index in targets.indices { setChecking(targets[index].id, true) }

        let ids = targets.map(\.id)
        Task { @MainActor in
            for id in ids {
                try? await Task.sleep(for: .milliseconds(550))
                publishObservation(checkoutID: id)
            }
            finishCheckRun()
        }
    }

    private func publishObservation(checkoutID: String) {
        setChecking(checkoutID, false)
        let failed = checkFailRigs.contains(checkoutID)
        mutateCheckout(checkoutID) { co in
            co.observation = StubObservation(succeeded: !failed,
                                             completedAt: Date(),
                                             remoteTipSHA: failed ? nil : co.tipSHA)
            if failed {
                // 失败覆盖旧观察：检出回到 check-unknown（ADR-0005 §6）。
                co.state = .checkUnknown
            } else if co.state == .checkUnknown, let revealed = checkReveal[checkoutID] {
                co.state = revealed
                if revealed == .updateAvailable { co.behind = max(co.behind, 2) }
            }
        }
        checkRun?.finished += 1
        if failed { checkRun?.failed += 1 }
    }

    private func finishCheckRun() {
        guard let run = checkRun else { return }
        let outcome: String
        let outcomeDisplay: String
        if run.failed == 0 {
            outcome = "complete"; outcomeDisplay = "全部完成"
        } else if run.failed < run.finished {
            outcome = "partial"; outcomeDisplay = "部分完成"
        } else {
            outcome = "failed"; outcomeDisplay = "失败"
        }
        audit.insert(auditRecord("au-run-\(UUID().uuidString.prefix(6))", kind: .checkRun, hoursAgo: 0,
                                 subject: "全量检查（\(run.total + run.skipped) 个检出）",
                                 outcome: outcome, outcomeDisplay: outcomeDisplay,
                                 detail: "应检查 \(run.total) · 成功 \(run.finished - run.failed) · 失败 \(run.failed) · 本地可判跳过 \(run.skipped)"), at: 0)
        notice = outcome == "complete"
            ? "检查完成：全部成功。"
            : "检查\(outcomeDisplay)：失败项已回到「尚未检查」并随下次全量检查自然重试。"
        checkRun = nil
    }

    // MARK: 动作：Update Run

    func startUpdate(skillID: String) {
        guard !hasRunningWork, registryMode == .normal, !scanIsPartial else { return }
        guard let skill = skills.first(where: { $0.id == skillID }) else { return }
        let eligible = eligibleCheckouts(for: skill)
        guard !eligible.isEmpty else { return }
        update = StubUpdateFlow(skillID: skillID, phase: .rechecking)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard update?.skillID == skillID, case .rechecking = update?.phase else { return }
            resolveRecheck(skill: skill, eligible: eligible)
        }
    }

    private func resolveRecheck(skill: StubSkill, eligible: [StubCheckout]) {
        let rig = updateRigs[skill.id] ?? .success
        switch rig {
        case .noopNowUpToDate:
            update = nil
            notice = "「\(skill.name)」已是最新：重查发现远程没有新提交（noop，未做任何修改）。"
            audit.insert(auditRecord("au-\(UUID().uuidString.prefix(6))", kind: .updateRun, hoursAgo: 0,
                                     subject: skill.name, outcome: "success", outcomeDisplay: "成功（noop：已是最新）",
                                     detail: "重查时远程无新提交，未执行任何修改。"), at: 0)
        case .recheckBlocked(let state):
            update = nil
            notice = "「\(skill.name)」现在不可更新：\(state.displayName)。\(state.recovery ?? "")"
        case .success, .failAfterConfirm, .successThenRefreshFailed:
            guard let source = source(for: skill) else { update = nil; return }
            let selected = eligible[0]
            let plan = StubUpdatePlan(
                skillID: skill.id,
                candidateCheckoutIDs: eligible.map(\.id),
                selectedCheckoutID: selected.id,
                sourceKey: source.key,
                relativePath: skill.relativePath,
                checkoutPath: selected.path,
                branch: selected.branch,
                upstream: selected.upstream,
                headSHA: selected.headSHA,
                targetSHA: selected.tipSHA,
                behind: selected.behind
            )
            update = StubUpdateFlow(skillID: skill.id, phase: .confirming(plan))
        }
    }

    func selectPlanCheckout(_ checkoutID: String) {
        guard case .confirming(let plan) = update?.phase,
              let co = checkout(checkoutID) else { return }
        var newPlan = plan
        newPlan.selectedCheckoutID = checkoutID
        newPlan.checkoutPath = co.path
        newPlan.branch = co.branch
        newPlan.upstream = co.upstream
        newPlan.headSHA = co.headSHA
        newPlan.targetSHA = co.tipSHA
        newPlan.behind = co.behind
        update?.phase = .confirming(newPlan)
    }

    func cancelUpdate() {
        guard let flow = update, case .confirming(let plan) = flow.phase else { update = nil; return }
        // 确认前 fetch 已移动 remote-tracking ref：取消后该检出按 freshness 合同回落 check-unknown（ADR-0006 §2）。
        mutateCheckout(plan.selectedCheckoutID) { co in
            co.state = .checkUnknown
            co.observation = nil
        }
        let skillName = skills.first { $0.id == flow.skillID }?.name ?? flow.skillID
        audit.insert(auditRecord("au-\(UUID().uuidString.prefix(6))", kind: .updateRun, hoursAgo: 0,
                                 subject: skillName, outcome: "cancelled", outcomeDisplay: "已取消",
                                 detail: "确认前取消；该检出回到「尚未检查」，恢复动作是重新检查。",
                                 planSnapshot: "计划：\(plan.checkoutPath) 从 \(plan.headSHA) fast-forward 到 \(plan.targetSHA)（当时记录）"), at: 0)
        update = nil
        notice = "已取消。未做任何修改；该检出回到「尚未检查」，重新检查即可恢复。"
    }

    func confirmUpdate() {
        guard let flow = update, case .confirming(let plan) = flow.phase else { return }
        update?.phase = .applying(plan)
        let skillName = skills.first { $0.id == flow.skillID }?.name ?? flow.skillID
        // 确认绑定时刻写开始记录（best-effort）。
        audit.insert(auditRecord("au-start-\(UUID().uuidString.prefix(6))", kind: .updateRun, hoursAgo: 0,
                                 subject: skillName, outcome: "started", outcomeDisplay: "已开始",
                                 detail: "用户已确认的执行计划。",
                                 planSnapshot: "计划：\(plan.checkoutPath) 从 \(plan.headSHA) fast-forward 到 \(plan.targetSHA)（当时记录）"), at: 0)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard case .applying(let current) = update?.phase else { return }
            finishUpdate(plan: current, skillName: skillName)
        }
    }

    private func finishUpdate(plan: StubUpdatePlan, skillName: String) {
        let rig = updateRigs[plan.skillID] ?? .success
        switch rig {
        case .failAfterConfirm(let failure):
            update?.phase = .failed(failure)
            audit.insert(auditRecord("au-\(UUID().uuidString.prefix(6))", kind: .updateRun, hoursAgo: 0,
                                     subject: skillName, outcome: "failed", outcomeDisplay: "失败",
                                     reason: failure,
                                     detail: "\(failure.displayName)（当时记录）"), at: 0)
        case .success, .successThenRefreshFailed, .noopNowUpToDate, .recheckBlocked:
            mutateCheckout(plan.selectedCheckoutID) { co in
                co.state = .upToDate
                co.behind = 0
                co.headSHA = co.tipSHA
                co.observation = StubObservation(succeeded: true, completedAt: Date(), remoteTipSHA: co.tipSHA)
            }
            audit.insert(auditRecord("au-\(UUID().uuidString.prefix(6))", kind: .updateRun, hoursAgo: 0,
                                     subject: skillName, outcome: "success", outcomeDisplay: "成功",
                                     detail: "fast-forward 到 \(plan.targetSHA)（落后 \(plan.behind) 个提交）；已重读 Git 事实并触发完整扫描刷新。"), at: 0)
            update = nil
            if case .successThenRefreshFailed = rig {
                notice = "「\(skillName)」更新成功。但刷新列表的扫描失败了：列表可能不是最新；更新结果不受影响，也不会被回滚。"
            } else {
                notice = "「\(skillName)」已更新到 \(plan.targetSHA)，现在是最新。"
            }
        }
    }

    func dismissUpdateFailure() {
        update = nil
    }

    // MARK: 动作：来源映射

    func beginMapping(_ unattributedID: String) {
        guard registryMode == .normal else { return }
        mappingDraftID = unattributedID
    }

    func createMapping(targetSkillID: String) {
        guard let uaID = mappingDraftID,
              let ua = unattributed.first(where: { $0.id == uaID }),
              let skill = skills.first(where: { $0.id == targetSkillID }) else { return }
        if simulateRegistryWriteFailure { registryWriteFailed(); return }
        // 映射落盘（stub）：Installation 获得身份，从未归因列表移入 Skill 的安装列表。
        unattributed.removeAll { $0.id == uaID }
        var mapped = inst("in-mapped-\(ua.id)", path: ua.asFoundPath, host: ua.host, projection: .copy)
        mapped.attribution = .mapped
        if let idx = skills.firstIndex(where: { $0.id == targetSkillID }) {
            skills[idx].installations.append(mapped)
        }
        audit.insert(auditRecord("au-\(UUID().uuidString.prefix(6))", kind: .mapping, hoursAgo: 0,
                                 subject: ua.asFoundPath, outcome: "created", outcomeDisplay: "已建立",
                                 detail: "映射到 \(source(for: skill)?.displayName ?? "") 的 \(skill.relativePath)；每次完整扫描都会重验证。"), at: 0)
        mappingDraftID = nil
        notice = "已建立映射：\(ua.asFoundPath) → \(skill.name)。这是人工主张，事实变化时会自动失效或复活。"
    }

    func cancelMappingDraft() {
        mappingDraftID = nil
    }

    /// 显式删除失效映射：只删记录，Installation 仍是来源不明。
    func deleteInvalidMapping(_ unattributedID: String) {
        if simulateRegistryWriteFailure { registryWriteFailed(); return }
        mutateUnattributed(unattributedID) { ua in
            ua.invalidMappingReason = nil
            ua.invalidMappingTargetName = nil
        }
        audit.insert(auditRecord("au-\(UUID().uuidString.prefix(6))", kind: .mapping, hoursAgo: 0,
                                 subject: unattributed.first { $0.id == unattributedID }?.asFoundPath ?? unattributedID,
                                 outcome: "deleted", outcomeDisplay: "已删除",
                                 detail: "删除失效映射记录；未触碰任何 Skill 内容。"), at: 0)
        notice = "已删除失效映射记录。该安装仍是「来源不明」，可随时重新指定来源。"
    }

    /// 场景助手（mapping）：模拟来源目录移回 + 重新扫描 → 失效映射自动复活。
    func simulateMappingRevive() {
        guard let ua = unattributed.first(where: { $0.invalidMappingReason != nil }) else {
            notice = "当前没有失效映射。"
            return
        }
        // 来源重新被发现：注册一个新来源与 Skill，映射自动复活。
        if !sources.contains(where: { $0.id == "src-report" }) {
            sources.append(source("src-report", key: "github.com/dimon94/report-skill", name: "report-skill", checkouts: [
                checkout("co-report", path: "~/Code/report-skill", state: .checkUnknown, behind: 0,
                         head: "1a2b3c4", tip: "1a2b3c4", observation: nil),
            ]))
            skills.append(skill("sk-weekly-report", name: "weekly-report", sourceID: "src-report",
                                path: "skills/weekly-report", installations: []))
        }
        unattributed.removeAll { $0.id == ua.id }
        var revived = inst("in-revived-\(ua.id)", path: ua.asFoundPath, host: ua.host, projection: .copy)
        revived.attribution = .mapped
        if let idx = skills.firstIndex(where: { $0.id == "sk-weekly-report" }) {
            skills[idx].installations.append(revived)
        }
        notice = "来源目录移回后重新扫描：weekly-report 的映射已自动复活（无需人工确认）。"
    }

    // MARK: 动作：Registry 故障与审计

    func simulateRegistryCorruption() {
        registryMode = .corrupted
        checkRun = nil; update = nil
        notice = nil
    }

    func simulateFutureVersion() {
        registryMode = .futureVersion
        checkRun = nil; update = nil
        notice = nil
    }

    func resetRegistry() {
        // 受限恢复模式中的「重置为空 Registry」：显式动作，先无条件 quarantine，再写空 v1。
        registryMode = .normal
        scanRoots = []
        for skill in skills.indices { skills[skill].installations.removeAll { $0.attribution == .mapped } }
        for source in sources.indices {
            for index in sources[source].checkouts.indices {
                if sources[source].checkouts[index].state == .updateAvailable
                    || sources[source].checkouts[index].state == .upToDate {
                    sources[source].checkouts[index].state = .checkUnknown
                    sources[source].checkouts[index].observation = nil
                }
            }
        }
        notice = "已重置为空 Registry（原文件已备份到 registry.corrupt-20260823-1730.json）。Scan Root 与映射需人工重建；观察证据可经重新检查恢复。"
    }

    func simulateQuitForManualRepair() {
        notice = "真实产品中此动作会退出 App，由你在终端修复 quarantine 文件后放回原路径。原型不退出。"
    }

    func clearAudit() {
        audit = []
        notice = "已清空历史记录（无墓碑）。Registry、Skill 与 Git 均未受影响。"
    }

    // MARK: - 私有 helper

    private func registryWriteFailed() {
        notice = "写入失败：动作未生效，磁盘上的 Registry 保持原样（fail closed）。请检查磁盘空间与目录权限后重试。"
    }

    private func setState(_ checkoutID: String, _ state: StubCheckoutState) {
        mutateCheckout(checkoutID) { $0.state = state }
    }

    private func setChecking(_ checkoutID: String, _ flag: Bool) {
        mutateCheckout(checkoutID) { $0.isChecking = flag }
    }

    private func mutateCheckout(_ id: String, _ mutate: (inout StubCheckout) -> Void) {
        for s in sources.indices {
            for c in sources[s].checkouts.indices where sources[s].checkouts[c].id == id {
                mutate(&sources[s].checkouts[c])
                return
            }
        }
    }

    private func mutateUnattributed(_ id: String, _ mutate: (inout StubUnattributed) -> Void) {
        for i in unattributed.indices where unattributed[i].id == id {
            mutate(&unattributed[i])
            return
        }
    }

    // MARK: - 数据集 builder

    private func source(_ id: String, key: String, name: String, checkouts: [StubCheckout]) -> StubSkillSource {
        StubSkillSource(id: id, key: key, displayName: name, checkouts: checkouts)
    }

    private func checkout(_ id: String, path: String, state: StubCheckoutState, behind: Int,
                          head: String, tip: String, observation: StubObservation?) -> StubCheckout {
        StubCheckout(id: id, path: path, branch: "main", upstream: "origin/main",
                     state: state, behind: behind, headSHA: head, tipSHA: tip, observation: observation)
    }

    private func checkout(_ id: String, path: String, state: StubCheckoutState, behind: Int,
                          head: String, tip: String, hours: Int) -> StubCheckout {
        checkout(id, path: path, state: state, behind: behind, head: head, tip: tip,
                 observation: StubObservation(succeeded: true,
                                              completedAt: Date(timeIntervalSinceNow: -Double(hours) * 3600),
                                              remoteTipSHA: tip))
    }

    private func skill(_ id: String, name: String, sourceID: String, path: String,
                       installations: [StubInstallation]) -> StubSkill {
        StubSkill(id: id, name: name, sourceID: sourceID, relativePath: path, installations: installations)
    }

    private func inst(_ id: String, path: String, host: StubHost, projection: StubProjection) -> StubInstallation {
        StubInstallation(id: id, asFoundPath: path, host: host, projection: projection, attribution: .automatic)
    }

    private func auditRecord(_ id: String, kind: StubAuditRecord.Kind, hoursAgo: Double, subject: String,
                             outcome: String, outcomeDisplay: String, reason: StubUpdateFailure? = nil,
                             detail: String, isOrphanUpdateStart: Bool = false,
                             planSnapshot: String? = nil) -> StubAuditRecord {
        StubAuditRecord(id: id, kind: kind,
                        time: Date(timeIntervalSinceNow: -hoursAgo * 3600),
                        subject: subject, outcome: outcome, outcomeDisplay: outcomeDisplay,
                        reason: reason, detail: detail,
                        isOrphanUpdateStart: isOrphanUpdateStart, planSnapshot: planSnapshot)
    }
}
