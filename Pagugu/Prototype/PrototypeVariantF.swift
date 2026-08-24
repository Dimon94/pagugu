// PROTOTYPE / THROWAWAY — issue #10（Wayfinder map #1）
// Variant F：主从结构 —— 左侧全量目录（仓库行 + 仓库下 Skill 行 + 无仓库 Skill 行，不收起、不嵌套点击），
// 选中后右侧直接显示详情；Skill 详情包含状态与检出、安装位置、来源、SKILL.md 原文（只读）。
// 条目模型与宿主 logo 沿用 E；无 DisclosureGroup 嵌套，消除一次点击触发多个响应的问题。
// 全部内存 stub；不是生产实现。

import SwiftUI

struct PrototypeVariantFView: View {
    let world: PrototypeWorld
    @State private var selection: Node?
    @State private var showActivity = false
    @State private var showScanRoots = false

    enum Node: Hashable {
        case repo(String)
        case skill(String)
        case unattributed(String)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                if world.scanRoots.isEmpty {
                    firstLaunchBlock
                }
                if let run = world.checkRun, run.isRunning {
                    Label("正在检查 \(run.finished)/\(run.total)…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.callout).foregroundStyle(.blue)
                }
                ForEach(flatNodes, id: \.self) { node in
                    sidebarRow(node)
                }
            }
            .listStyle(.plain)
            .navigationSplitViewColumnWidth(min: 260, ideal: 310, max: 420)
        } detail: {
            detailView
                .toolbar { detailToolbar }
        }
        .sheet(isPresented: $showActivity) {
            VStack(alignment: .leading) { StubAuditSection(world: world) }
                .padding(16).frame(width: 560, height: 420)
        }
        .sheet(isPresented: $showScanRoots) {
            VStack(alignment: .leading) { StubScanRootSection(world: world) }
                .padding(16).frame(width: 520)
        }
        .onAppear {
            if selection == nil { selection = flatNodes.first }
        }
        .onChange(of: world.scenario) {
            selection = flatNodes.first
        }
    }

    private var firstLaunchBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("欢迎使用 Pagugu").font(.headline)
            Text("三个个人 Skill 目录已自动发现。添加 Project Scan Root 后，项目里的来源仓库也会出现在目录里。")
                .font(.caption).foregroundStyle(.secondary)
            Menu("添加 Project Scan Root…") {
                Button("~/Code（示例）") { world.addScanRoot("~/Code") }
                Button("~/Work（示例）") { world.addScanRoot("~/Work") }
            }
            .font(.callout)
        }
        .padding(.vertical, 6)
    }

    // MARK: 目录顺序：静默按行动优先级；仓库行后紧跟其 Skill 行

    private var flatNodes: [Node] {
        var rows: [(node: Node, order: Int, name: String)] = world.sources.map { source in
            (.repo(source.id), worstGroup(of: source).sortOrder, source.displayName)
        }
        rows += world.unattributed.map { item in
            (.unattributed(item.id), StubStateGroup.needsAttention.sortOrder, item.displayName)
        }
        let ordered = rows.sorted { lhs, rhs in
            lhs.order != rhs.order ? lhs.order < rhs.order : lhs.name < rhs.name
        }
        var nodes: [Node] = []
        for entry in ordered {
            nodes.append(entry.node)
            if case .repo(let id) = entry.node {
                nodes.append(contentsOf: world.skills.filter { $0.sourceID == id }.map { Node.skill($0.id) })
            }
        }
        return nodes
    }

    private func worstGroup(of source: StubSkillSource) -> StubStateGroup {
        let order = StubCheckoutState.allCases
        return source.checkouts.map(\.state).min { a, b in
            order.firstIndex(of: a)! < order.firstIndex(of: b)!
        }?.group ?? .unknown
    }

    // MARK: 侧栏行

    @ViewBuilder
    private func sidebarRow(_ node: Node) -> some View {
        switch node {
        case .repo(let id):
            if let source = world.sources.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        stateIcon(of: source)
                        Text(source.displayName).font(.callout.weight(.medium))
                        Spacer()
                        hostSlots(activeHosts(of: source))
                    }
                    Text(phrase(of: source))
                        .font(.caption)
                        .foregroundStyle(phraseColor(of: source))
                        .padding(.leading, 24)
                }
                .tag(Node.repo(id))
            }
        case .skill(let id):
            if let skill = world.skills.first(where: { $0.id == id }) {
                HStack(spacing: 8) {
                    Image(systemName: "shippingbox").font(.caption2)
                    Text(skill.name).font(.callout)
                    Spacer()
                    hostSlots(activeHosts(of: skill))
                }
                .padding(.leading, 22)
                .tag(Node.skill(id))
            }
        case .unattributed(let id):
            if let item = world.unattributed.first(where: { $0.id == id }) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                    Text(item.displayName).font(.callout)
                    Text(item.invalidMappingReason == nil ? "来源不明" : "映射失效")
                        .font(.caption).foregroundStyle(.orange)
                    Spacer()
                    hostSlots([item.host])
                }
                .tag(Node.unattributed(id))
            }
        }
    }

    // MARK: 右侧详情

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .repo(let id):
            if let source = world.sources.first(where: { $0.id == id }) {
                repoDetail(source)
            } else { placeholder }
        case .skill(let id):
            if let skill = world.skills.first(where: { $0.id == id }) {
                SkillDetailView(world: world, skill: skill)
            } else { placeholder }
        case .unattributed(let id):
            if let item = world.unattributed.first(where: { $0.id == id }) {
                unattributedDetail(item)
            } else { placeholder }
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        ContentUnavailableView("选择左侧的仓库或 Skill", systemImage: "shippingbox")
    }

    private func repoDetail(_ source: StubSkillSource) -> some View {
        let skills = world.skills.filter { $0.sourceID == source.id }
        let eligible = source.checkouts.filter { $0.state.isEligible }
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Text(source.displayName).font(.title2.weight(.semibold))
                    hostSlots(activeHosts(of: source))
                    Spacer()
                    if !eligible.isEmpty, let skill = skills.first {
                        Button("更新") { world.startUpdate(skillID: skill.id) }
                            .buttonStyle(.borderedProminent)
                            .disabled(world.hasRunningWork || world.scanIsPartial)
                    }
                }
                Text(phrase(of: source))
                    .foregroundStyle(phraseColor(of: source))

                detailSection("检出（物理工作树）") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(source.checkouts) { co in
                            if let skill = skills.first {
                                StubCheckoutCard(world: world, skill: skill, checkout: co)
                            }
                        }
                        if source.checkouts.count > 1 {
                            Text("同一来源的多个检出各自裁决；其他检出的状态不影响可更新检出。")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                detailSection("包含的 Skill（\(skills.count) 个）") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(skills) { skill in
                            Button { selection = .skill(skill.id) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "shippingbox").font(.caption)
                                    Text(skill.name).font(.callout)
                                    Spacer()
                                    hostSlots(activeHosts(of: skill))
                                    Image(systemName: "chevron.right")
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                detailSection("来源标识") {
                    Text(source.key)
                        .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func unattributedDetail(_ item: StubUnattributed) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Text(item.displayName).font(.title2.weight(.semibold))
                    hostSlots([item.host])
                }
                StubUnattributedCard(world: world, item: item)
                detailSection("SKILL.md 原文（只读）") {
                    MarkdownSourceView(text: item.markdownDocument)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detailSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    // MARK: 工具栏

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("检查更新") { world.startCheckRun() }
                .buttonStyle(.borderedProminent)
                .disabled(!world.canStartCheckRun)
        }
        ToolbarItem(placement: .status) {
            if let last = world.lastObservationTime {
                Text("上次检查 \(last.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(.secondary)
            }
        }
        ToolbarItem(placement: .automatic) {
            Button { showActivity = true } label: { Label("最近活动", systemImage: "clock") }
        }
        ToolbarItem(placement: .automatic) {
            Button { showScanRoots = true } label: { Label("扫描范围", systemImage: "folder") }
        }
    }

    // MARK: 呈现 helper（与 E 同一套语义）

    private func hostSlots(_ active: Set<StubHost>) -> some View {
        HStack(spacing: 5) {
            ForEach(StubHost.allCases) { host in
                StubHostLogo(host: host, isActive: active.contains(host), size: 13)
            }
        }
    }

    private func activeHosts(of skill: StubSkill) -> Set<StubHost> {
        Set(skill.installations.map(\.host))
    }

    private func activeHosts(of source: StubSkillSource) -> Set<StubHost> {
        Set(world.skills.filter { $0.sourceID == source.id }
            .flatMap { $0.installations.map(\.host) })
    }

    private func stateIcon(of source: StubSkillSource) -> some View {
        let (name, color): (String, Color) = {
            switch worstGroup(of: source) {
            case .updateReady: return ("arrow.down.circle.fill", .blue)
            case .needsAttention: return ("exclamationmark.triangle.fill", .orange)
            case .unknown: return ("questionmark.circle", .secondary)
            case .settled: return ("checkmark.circle", .secondary)
            }
        }()
        return Image(systemName: name).foregroundStyle(color)
    }

    private func phrase(of source: StubSkillSource) -> String {
        let states = source.checkouts.map(\.state)
        let groups = Dictionary(grouping: states, by: \.group)
        if groups.count == 1, let state = states.first {
            switch state {
            case .updateAvailable: return "有更新可用 · 落后 \(source.checkouts.first?.behind ?? 0) 个提交"
            case .upToDate: return "已是最新"
            case .aheadOnly: return "本地领先，无需更新"
            case .noRemote: return "仅本地 · 没有远程，不可更新"
            default: return state.displayName
            }
        }
        var parts: [String] = []
        if let n = groups[.updateReady]?.count { parts.append("\(n) 个可更新") }
        if let n = groups[.needsAttention]?.count { parts.append("\(n) 个需处理") }
        if let n = groups[.unknown]?.count { parts.append("\(n) 个未检查") }
        if parts.isEmpty, let n = groups[.settled]?.count { parts.append("\(n) 个无需更新") }
        return parts.joined(separator: " · ")
    }

    private func phraseColor(of source: StubSkillSource) -> Color {
        switch worstGroup(of: source) {
        case .updateReady: return .blue
        case .needsAttention: return .orange
        case .unknown, .settled: return .secondary
        }
    }
}
