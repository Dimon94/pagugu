import Foundation

// L3 COORD: Pagugu/AppModel/SkillReadModel.swift
// POS: AppModel 模块（ADR-0009 §7）。owns Skill Read Model 只读投影与目录节点派生。
// TEST: repo://PaguguTests/AppModelTests.swift（投影形状、目录节点与欢迎态测试）。

/// Skill Read Model：AppModel 发布的只读投影，View 只消费不重建。
struct SkillReadModel: Sendable {
    /// 来源仓库行（Variant F 呈现分组；身份与去重的 canonical 条目是其子 Skill）。
    let sources: [SkillSourceItem]
    /// 无仓库可归行（Unattributed Installation 以 Skill 本身为行；内容指纹一致的复制安装聚合）。
    let unattributedInstallations: [UnattributedInstallationItem]
    /// 扫描问题列表。
    let issues: [ScanIssue]
    /// 整体扫描状态。
    let scanOutcome: ScanOutcome
    /// Project Scan Root 主张的按序实时投影。
    let projectScanRoots: [ProjectScanRoot]
    /// 是否为空态（无任何 Skill 且无 Issue）。
    let isEmpty: Bool

    static func empty() -> SkillReadModel {
        SkillReadModel(
            sources: [],
            unattributedInstallations: [],
            issues: [],
            scanOutcome: .complete,
            projectScanRoots: []
        )
    }

    init(
        sources: [SkillSourceItem],
        unattributedInstallations: [UnattributedInstallationItem],
        issues: [ScanIssue],
        scanOutcome: ScanOutcome,
        projectScanRoots: [ProjectScanRoot] = []
    ) {
        self.sources = sources
        self.unattributedInstallations = unattributedInstallations
        self.issues = issues
        self.scanOutcome = scanOutcome
        self.projectScanRoots = projectScanRoots
        self.isEmpty = sources.isEmpty && unattributedInstallations.isEmpty && issues.isEmpty
    }

    /// 平铺目录节点（Variant F：无分组标题、无筛选 UI）：
    /// 无仓库可归行在前（需要处理），随后来源仓库行；收起的仓库行不产子 Skill 行。
    /// 五档行动优先级静默排序归 #20（检出状态接入后）。
    func directoryNodes(collapsedSources: Set<SkillSourceKey>) -> [SkillDirectoryNode] {
        var nodes: [SkillDirectoryNode] = unattributedInstallations.map { .unattributedInstallation($0.id) }
        for source in sources {
            nodes.append(.source(source.id))
            guard !collapsedSources.contains(source.id) else { continue }
            nodes.append(contentsOf: source.skills.map { .skill($0.id) })
        }
        return nodes
    }

    // MARK: - 选择解析（View 按节点查投影的唯一入口）

    func sourceItem(for key: SkillSourceKey) -> SkillSourceItem? {
        sources.first { $0.id == key }
    }

    func skillEntry(for identity: SkillIdentity) -> SkillDirectoryEntry? {
        sources.flatMap(\.skills).first { $0.id == identity }
    }

    func unattributedItem(for id: String) -> UnattributedInstallationItem? {
        unattributedInstallations.first { $0.id == id }
    }
}

/// 目录中的可选中行（主从选择模型）。
enum SkillDirectoryNode: Hashable, Sendable {
    /// 来源仓库行。
    case source(SkillSourceKey)
    /// 仓库下的子 Skill 行（canonical 条目）。
    case skill(SkillIdentity)
    /// 无仓库可归行（值为条目稳定标识：内容指纹组或安装 Canonical Path）。
    case unattributedInstallation(String)
}
