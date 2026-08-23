// PROTOTYPE / THROWAWAY — issue #10（Wayfinder map #1）
// Variant C：来源地图 —— Skill Source 为一等公民的双栏关系视图。左栏按来源展开检出与 Skill，
// 右栏呈现「来源 → 检出状态 → Skill → 安装位置 → Agent Host」的完整关系链。
// 主 affordance = 选中来源/检出节点后直接操作。来源不明的复制安装没有来源，单列在「待归源」。
// 全部内存 stub；不是生产实现。

import SwiftUI

struct PrototypeVariantCView: View {
    let world: PrototypeWorld
    @State private var selection: Node?

    enum Node: Hashable {
        case source(String)
        case checkout(String)
        case skill(String)
        case unattributed(String)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                if world.scanRoots.isEmpty {
                    Label("添加 Project Scan Root 后发现项目 Skill 与来源", systemImage: "folder.badge.plus")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Skill Source（\(world.sources.count)）") {
                    ForEach(world.sources) { source in
                        Section {
                            ForEach(source.checkouts) { co in
                                HStack {
                                    Image(systemName: "externaldrive")
                                    Text(co.path).font(.caption).lineLimit(1)
                                    Spacer()
                                    StubStatePill(state: co.state)
                                }
                                .tag(Node.checkout(co.id))
                            }
                            ForEach(world.skills.filter { $0.sourceID == source.id }) { skill in
                                Label(skill.name, systemImage: "shippingbox")
                                    .font(.callout)
                                    .tag(Node.skill(skill.id))
                            }
                        } header: {
                            Text(source.displayName).font(.callout.weight(.medium))
                                .tag(Node.source(source.id))
                        }
                    }
                }
                if !world.unattributed.isEmpty {
                    Section("待归源（复制安装，暂无来源）") {
                        ForEach(world.unattributed) { item in
                            HStack {
                                Text(item.displayName).font(.callout)
                                Spacer()
                                Text("来源不明").font(.caption).foregroundStyle(.orange)
                            }
                            .tag(Node.unattributed(item.id))
                        }
                    }
                }
                Section {
                    StubScanRootSection(world: world)
                }
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 420)
        } detail: {
            detailContent
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("检查更新") { world.startCheckRun() }
                            .disabled(!world.canStartCheckRun)
                    }
                }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let run = world.checkRun, run.isRunning {
            VStack { Spacer(); ProgressView("正在检查 \(run.finished)/\(run.total)…"); Spacer() }
        } else {
            switch selection {
            case .source(let id):
                if let source = world.sources.first(where: { $0.id == id }) {
                    sourceDetail(source)
                } else { placeholder }
            case .checkout(let id):
                checkoutDetail(id)
            case .skill(let id):
                if let skill = world.skills.first(where: { $0.id == id }) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(skill.name).font(.title2.weight(.semibold))
                            StubSkillDetailSections(world: world, skill: skill)
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else { placeholder }
            case .unattributed(let id):
                if let item = world.unattributed.first(where: { $0.id == id }) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(item.displayName).font(.title2.weight(.semibold))
                            StubUnattributedCard(world: world, item: item)
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else { placeholder }
            case nil:
                placeholder
            }
        }
    }

    private var placeholder: some View {
        ContentUnavailableView("选择左侧的来源、检出或 Skill", systemImage: "map")
    }

    /// 来源节点详情：完整关系链。
    private func sourceDetail(_ source: StubSkillSource) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(source.displayName).font(.title2.weight(.semibold))
                Text("Skill Source Key：\(source.key)")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)

                GroupBox("检出（物理工作树）") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(source.checkouts) { co in
                            if let skill = world.skills.first(where: { $0.sourceID == source.id }) {
                                StubCheckoutCard(world: world, skill: skill, checkout: co)
                            }
                        }
                    }
                }

                GroupBox("包含的 Skill 与安装去向") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(world.skills.filter { $0.sourceID == source.id }) { skill in
                            VStack(alignment: .leading, spacing: 4) {
                                Label("\(skill.name)（\(skill.relativePath)）", systemImage: "shippingbox")
                                    .font(.callout.weight(.medium))
                                if skill.installations.isEmpty {
                                    Text("未被任何 Agent Host 安装").font(.caption).foregroundStyle(.secondary)
                                }
                                ForEach(skill.installations) { installation in
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.turn.down.right").font(.caption2)
                                        Text(installation.asFoundPath).font(.caption)
                                        HostBadge(host: installation.host)
                                        Text(installation.projection.rawValue)
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                StubAuditSection(world: world)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func checkoutDetail(_ id: String) -> some View {
        let owner = world.sources.first { $0.checkouts.contains { $0.id == id } }
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let source = owner, let co = source.checkouts.first(where: { $0.id == id }),
                   let skill = world.skills.first(where: { $0.sourceID == source.id }) {
                    Text(co.path).font(.title2.weight(.semibold))
                    Text("属于来源 \(source.key)").font(.caption).foregroundStyle(.secondary)
                    StubCheckoutCard(world: world, skill: skill, checkout: co)
                    if source.checkouts.count > 1 {
                        Text("该来源还有 \(source.checkouts.count - 1) 个其他检出；它们的状态不影响本检出的更新资格。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    StubAuditSection(world: world)
                } else {
                    placeholder
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
