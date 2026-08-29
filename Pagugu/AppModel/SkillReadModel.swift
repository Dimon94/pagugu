import Foundation

// L3 COORD: Pagugu/AppModel/SkillReadModel.swift
// POS: AppModel 模块（ADR-0009 §7）。owns Skill Read Model、来源映射投影、Check Run 投影、
//      同名共存组徽标与逐宿主诊断、目录状态短语与五档排序。
// TEST: repo://PaguguTests/AppModelTests.swift（投影形状、来源映射、Check Run、目录状态短语与排序表测试）；
//       repo://PaguguTests/AppModelCollisionTests.swift（同名诊断只读投影、目录名回退与更新资格隔离）。

/// Skill Read Model：AppModel 发布的只读投影，View 只消费不重建。
struct SkillReadModel: Sendable {
    /// 来源仓库行（Variant F 呈现分组；身份与去重的 canonical 条目是其子 Skill）。
    let sources: [SkillSourceItem]
    /// 无仓库可归行（Unattributed Installation 以 Skill 本身为行；内容指纹一致的复制安装聚合）。
    let unattributedInstallations: [UnattributedInstallationItem]
    /// 当前可选的已发现 Skill；人工映射只能指向其中一项。
    let mappingTargets: [SkillDirectoryEntry]
    /// 当前完整/部分扫描下判定为失效的持久映射投影。
    let invalidMappings: [SourceMappingProjection]
    /// 扫描问题列表。
    let issues: [ScanIssue]
    /// 整体扫描状态。
    let scanOutcome: ScanOutcome
    /// Project Scan Root 主张的按序实时投影。
    let projectScanRoots: [ProjectScanRoot]
    /// 按 Skill Source Key 保存逐检出卡片；卡片只投影实时事实与纯函数裁决。
    private let checkoutCardsBySource: [SkillSourceKey: [CheckoutCardReadModel]]
    /// 按 Skill/来源不明条目保存同名共存组徽标与逐宿主诊断。
    private let nameCollisionsByMemberID: [String: NameCollisionReadModel]
    /// 是否为空态（无任何 Skill 且无 Issue）。
    let isEmpty: Bool

    static func empty() -> SkillReadModel {
        SkillReadModel(
            sources: [],
            unattributedInstallations: [],
            mappingTargets: [],
            invalidMappings: [],
            issues: [],
            scanOutcome: .complete,
            projectScanRoots: [],
            checkoutCardsBySource: [:]
        )
    }

    init(
        sources: [SkillSourceItem],
        unattributedInstallations: [UnattributedInstallationItem],
        mappingTargets: [SkillDirectoryEntry] = [],
        invalidMappings: [SourceMappingProjection] = [],
        issues: [ScanIssue],
        scanOutcome: ScanOutcome,
        projectScanRoots: [ProjectScanRoot] = [],
        checkoutCardsBySource: [SkillSourceKey: [CheckoutCardReadModel]] = [:]
    ) {
        self.sources = sources
        self.unattributedInstallations = unattributedInstallations
        self.mappingTargets = mappingTargets
        self.invalidMappings = invalidMappings
        self.issues = issues
        self.scanOutcome = scanOutcome
        self.projectScanRoots = projectScanRoots
        self.checkoutCardsBySource = checkoutCardsBySource
        self.nameCollisionsByMemberID = Self.makeNameCollisionPresentations(
            sources: sources,
            unattributedInstallations: unattributedInstallations
        )
        self.isEmpty = sources.isEmpty && unattributedInstallations.isEmpty && invalidMappings.isEmpty && issues.isEmpty
    }

    // L4 IN: 当前 Skill Read Model 与瞬态收起集合。
    // OUT: 无分组标题的平铺目录；父来源行带其连续子 Skill 行。
    // INVARIANT: 静默顺序固定为需要处理、可更新、尚未检查、无需更新、仅本地；同档按最严重 Checkout Git State。
    //            卡片缺失来源与来源不明行无 Checkout 可比较，依次排在具体「需要处理」状态后、下一档前。
    // TEST: repo://PaguguTests/AppModelTests.swift::testDirectoryNodesUseFiveQuietPrioritiesAndRefreshWithStates。
    func directoryNodes(collapsedSources: Set<SkillSourceKey>) -> [SkillDirectoryNode] {
        var roots: [(node: SkillDirectoryNode, tier: Int, severity: Int, name: String, key: String)] = sources.map { source in
            let rank = sourceRank(for: source.id)
            return (.source(source.id), rank.tier, rank.severity, source.displayName, source.id.displayString)
        }
        roots.append(contentsOf: unattributedInstallations.map {
            (.unattributedInstallation($0.id), 0, CheckoutGitState.allCases.count + 1, $0.displayName, $0.id)
        })
        let visibleMappingPaths = Set(unattributedInstallations.flatMap(\.installations).map(\.canonicalPath))
        roots.append(contentsOf: invalidMappings.compactMap { mapping in
            guard !visibleMappingPaths.contains(mapping.installationCanonicalPath) else { return nil }
            return (
                .invalidMapping(mapping.installationCanonicalPath),
                0,
                CheckoutGitState.allCases.count + 1,
                mapping.installationCanonicalPath,
                mapping.installationCanonicalPath
            )
        })
        roots.sort {
            if $0.tier != $1.tier { return $0.tier < $1.tier }
            if $0.severity != $1.severity { return $0.severity < $1.severity }
            return $0.name != $1.name ? $0.name < $1.name : $0.key < $1.key
        }

        var nodes: [SkillDirectoryNode] = []
        for root in roots {
            nodes.append(root.node)
            guard case .source(let sourceKey) = root.node,
                  let source = sourceItem(for: sourceKey) else { continue }
            guard !collapsedSources.contains(source.id) else { continue }
            nodes.append(contentsOf: source.skills.map { .skill($0.id) })
        }
        return nodes
    }

    // L4 IN: 来源下当前逐检出卡片。
    // OUT: 按逐态计数并列的目录短语；单检出直接使用该状态短语。
    // INVARIANT: 每一部分都对应详情 Checkout 卡片；no-remote 只显示「仅本地」；不产生来源级聚合状态。
    // TEST: repo://PaguguTests/AppModelTests.swift::testDirectoryStatusPhraseTable。
    func directoryStatusPhrase(for sourceKey: SkillSourceKey) -> String? {
        let states = checkoutCards(for: sourceKey).map(\.state)
        guard !states.isEmpty else { return nil }
        if states.count == 1 { return Self.statusPhrase(for: states[0]) }

        let counts = Dictionary(grouping: states, by: { $0 }).mapValues(\.count)
        return counts.keys.sorted(by: Self.stateComesBefore).map { state in
            "\(counts[state, default: 0]) 个\(Self.statusPhrase(for: state))"
        }.joined(separator: " · ")
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

    func checkoutCards(for sourceKey: SkillSourceKey) -> [CheckoutCardReadModel] {
        checkoutCardsBySource[sourceKey] ?? []
    }

    private func sourceRank(for sourceKey: SkillSourceKey) -> (tier: Int, severity: Int) {
        guard let state = checkoutCards(for: sourceKey).map(\.state).min(by: Self.stateComesBefore) else {
            return (0, CheckoutGitState.allCases.count)
        }
        return Self.stateRank(state)
    }

    private static func stateComesBefore(_ lhs: CheckoutGitState, _ rhs: CheckoutGitState) -> Bool {
        let lhsRank = stateRank(lhs)
        let rhsRank = stateRank(rhs)
        return lhsRank.tier != rhsRank.tier
            ? lhsRank.tier < rhsRank.tier
            : lhsRank.severity < rhsRank.severity
    }

    private static func stateRank(_ state: CheckoutGitState) -> (tier: Int, severity: Int) {
        let tier: Int
        switch state {
        case .inspectionFailed, .detached, .noUpstream, .upstreamMismatch,
             .siblingConflict, .dirty, .diverged:
            tier = 0
        case .updateAvailable:
            tier = 1
        case .checkUnknown:
            tier = 2
        case .aheadOnly, .upToDate:
            tier = 3
        case .noRemote:
            tier = 4
        }
        return (tier, CheckoutGitState.allCases.firstIndex(of: state)!)
    }

    private static func statusPhrase(for state: CheckoutGitState) -> String {
        state == .noRemote ? "仅本地" : state.displayName
    }

    func invalidMapping(for path: String) -> SourceMappingProjection? {
        invalidMappings.first { $0.installationCanonicalPath == path }
    }

    func nameCollision(for identity: SkillIdentity) -> NameCollisionReadModel? {
        nameCollisionsByMemberID[Self.skillCollisionMemberID(identity)]
    }

    func nameCollision(forUnattributedInstallationID id: String) -> NameCollisionReadModel? {
        nameCollisionsByMemberID[Self.unattributedCollisionMemberID(id)]
    }

    private static func makeNameCollisionPresentations(
        sources: [SkillSourceItem],
        unattributedInstallations: [UnattributedInstallationItem]
    ) -> [String: NameCollisionReadModel] {
        let skillCandidates = sources.flatMap(\.skills).map { entry in
            NameCollisionCandidate(
                id: skillCollisionMemberID(entry.id),
                frontmatterName: entry.displayName,
                installationDirectoryName: (entry.canonicalPath as NSString).lastPathComponent,
                locations: collisionLocations(for: entry.installations)
            )
        }
        let unattributedCandidates = unattributedInstallations.map { item in
            NameCollisionCandidate(
                id: unattributedCollisionMemberID(item.id),
                frontmatterName: item.displayName,
                installationDirectoryName: (item.canonicalPath as NSString).lastPathComponent,
                locations: collisionLocations(for: item.installations)
            )
        }

        var presentations: [String: NameCollisionReadModel] = [:]
        for group in NameCollisionEngine.groups(from: skillCandidates + unattributedCandidates) {
            let presentation = NameCollisionReadModel(
                badgeText: "同名共存组 · \(group.memberIDs.count)",
                diagnosticTexts: group.diagnostics.map(\.message)
            )
            for memberID in group.memberIDs {
                presentations[memberID] = presentation
            }
        }
        return presentations
    }

    private static func collisionLocations(
        for installations: [SkillInstallation]
    ) -> Set<HostSkillLocation> {
        Set(installations.flatMap { installation in
            installation.hosts.map { host in
                HostSkillLocation(host: host, scope: installation.scope)
            }
        })
    }

    private static func skillCollisionMemberID(_ identity: SkillIdentity) -> String {
        "skill\0\(identity.sourceKey.registryValue)\0\(identity.repositoryRelativePath)"
    }

    private static func unattributedCollisionMemberID(_ id: String) -> String {
        "unattributed\0\(id)"
    }
}

/// 详情页消费的同名共存组只读投影。
struct NameCollisionReadModel: Equatable, Sendable {
    let badgeText: String
    let diagnosticTexts: [String]
}

/// Skill Read Model 中的一张逐检出卡片。主状态不覆盖正交事实。
struct CheckoutCardReadModel: Identifiable, Sendable {
    let facts: CheckoutGitFacts
    let state: CheckoutGitState
    let observation: CheckoutObservation?
    let checkOutcome: CheckRunItemOutcome?
    let isChecking: Bool

    init(
        facts: CheckoutGitFacts,
        state: CheckoutGitState,
        observation: CheckoutObservation? = nil,
        checkOutcome: CheckRunItemOutcome? = nil,
        isChecking: Bool = false
    ) {
        self.facts = facts
        self.state = state
        self.observation = observation
        self.checkOutcome = checkOutcome
        self.isChecking = isChecking
    }

    var id: String { facts.checkoutPath }
}

/// 目录中的可选中行（主从选择模型）。
enum SkillDirectoryNode: Hashable, Sendable {
    /// 来源仓库行。
    case source(SkillSourceKey)
    /// 仓库下的子 Skill 行（canonical 条目）。
    case skill(SkillIdentity)
    /// 无仓库可归行（值为条目稳定标识：内容指纹组或安装 Canonical Path）。
    case unattributedInstallation(String)
    /// 当前扫描中已无对应复制 Installation 的失效映射主张。
    case invalidMapping(String)
}
