// PROTOTYPE / THROWAWAY — issue #10（Wayfinder map #1）
// Variant E：平铺清单 —— 一份完整列表，条目 = 来源仓库；无仓库的 Skill（来源不明）以 Skill 本身为行。
// 不预设分组：排序在底层静默按行动优先级（需要处理 → 可更新 → 尚未检查 → 无需更新），行颜色自解释。
// 宽行：状态图标 + 名称 + 状态短语 + 包含的 Skill + 宿主 logo 槽位（点亮=已安装）+ 动作按钮。
// 行状态 = 检出状态，多检出展开逐条呈现，无聚合假状态；更新按钮 = 任一检出 Eligible。
// 全部内存 stub；不是生产实现。

import SwiftUI

struct PrototypeVariantEView: View {
    let world: PrototypeWorld
    @State private var showActivity = false
    @State private var showScanRoots = false

    private enum FlatRow: Hashable {
        case source(String)
        case unattributed(String)
    }

    var body: some View {
        NavigationStack {
            List {
                if world.scanRoots.isEmpty {
                    firstLaunchBlock
                }
                if let run = world.checkRun, run.isRunning {
                    Label("正在检查 \(run.finished)/\(run.total)…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.callout).foregroundStyle(.blue)
                }
                ForEach(flatRows, id: \.self) { row in
                    switch row {
                    case .source(let id):
                        if let source = world.sources.first(where: { $0.id == id }) {
                            sourceRow(source)
                        }
                    case .unattributed(let id):
                        if let item = world.unattributed.first(where: { $0.id == id }) {
                            unattributedRow(item)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .toolbar {
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
            .navigationDestination(for: String.self) { skillID in
                if let skill = world.skills.first(where: { $0.id == skillID }) {
                    SkillDetailView(world: world, skill: skill)
                }
            }
        }
        .sheet(isPresented: $showActivity) {
            VStack(alignment: .leading) { StubAuditSection(world: world) }
                .padding(16).frame(width: 560, height: 420)
        }
        .sheet(isPresented: $showScanRoots) {
            VStack(alignment: .leading) { StubScanRootSection(world: world) }
                .padding(16).frame(width: 520)
        }
    }

    private var firstLaunchBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("欢迎使用 Pagugu").font(.headline)
            Text("三个个人 Skill 目录已自动发现。添加 Project Scan Root 后，项目里的来源仓库也会出现在这份清单里。")
                .font(.callout).foregroundStyle(.secondary)
            Menu("添加 Project Scan Root…") {
                Button("~/Code（示例）") { world.addScanRoot("~/Code") }
                Button("~/Work（示例）") { world.addScanRoot("~/Work") }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: 平铺排序：静默按行动优先级，名称次序稳定

    private var flatRows: [FlatRow] {
        var rows: [(row: FlatRow, order: Int, name: String)] = world.sources.map { source in
            (.source(source.id), worstGroup(of: source).sortOrder, source.displayName)
        }
        rows += world.unattributed.map { item in
            (.unattributed(item.id), StubStateGroup.needsAttention.sortOrder, item.displayName)
        }
        return rows.sorted { lhs, rhs in
            lhs.order != rhs.order ? lhs.order < rhs.order : lhs.name < rhs.name
        }.map(\.row)
    }

    private func worstGroup(of source: StubSkillSource) -> StubStateGroup {
        let order = StubCheckoutState.allCases
        return source.checkouts.map(\.state).min { a, b in
            order.firstIndex(of: a)! < order.firstIndex(of: b)!
        }?.group ?? .unknown
    }

    // MARK: 仓库行（宽行）

    @ViewBuilder
    private func sourceRow(_ source: StubSkillSource) -> some View {
        let skills = world.skills.filter { $0.sourceID == source.id }
        let eligible = source.checkouts.filter { $0.state.isEligible }
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(source.checkouts) { co in
                    checkoutSubrow(checkout: co, skills: skills)
                }
                if !skills.isEmpty {
                    ForEach(skills) { skill in
                        NavigationLink(value: skill.id) {
                            HStack(spacing: 8) {
                                Image(systemName: "shippingbox").font(.caption)
                                Text(skill.name).font(.callout)
                                Spacer()
                                hostSlots(activeHosts(of: skill))
                            }
                        }
                    }
                }
            }
            .padding(.leading, 26)
            .padding(.vertical, 6)
        } label: {
            HStack(spacing: 10) {
                stateIcon(of: source)
                Text(source.displayName).font(.body.weight(.medium))
                Text(phrase(of: source))
                    .foregroundStyle(phraseColor(of: source))
                Spacer()
                Text(skillPreview(skills))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
                hostSlots(activeHosts(of: source, skills: skills))
                if !eligible.isEmpty {
                    Button("更新") { startUpdate(skills: skills) }
                        .disabled(world.hasRunningWork || world.scanIsPartial)
                }
            }
            .padding(.vertical, 3)
        }
    }

    private func checkoutSubrow(checkout: StubCheckout, skills: [StubSkill]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: "externaldrive").font(.caption)
                Text(checkout.path).font(.callout)
                if checkout.isChecking {
                    ProgressView().controlSize(.mini)
                }
                Spacer()
                Text(checkout.state.displayName)
                    .font(.caption)
                    .foregroundStyle(color(for: checkout.state))
                if let observation = checkout.observation {
                    Text("上次检查 \(observation.completedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if checkout.state.isEligible, let skill = skills.first {
                    Button("更新") { world.startUpdate(skillID: skill.id) }
                        .controlSize(.small)
                        .disabled(world.hasRunningWork || world.scanIsPartial)
                }
            }
            if let recovery = checkout.state.recovery {
                Text(recovery)
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    /// 无仓库的 Skill（来源不明的复制安装）：以 Skill 本身为行。
    @ViewBuilder
    private func unattributedRow(_ item: StubUnattributed) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(item.displayName).font(.body.weight(.medium))
                Text(item.invalidMappingReason == nil ? "来源不明" : "映射已失效")
                    .foregroundStyle(.orange)
                Spacer()
                Text("复制安装")
                    .font(.caption).foregroundStyle(.secondary)
                hostSlots([item.host])
                Button("指定来源") { world.beginMapping(item.id) }
                    .disabled(world.registryMode != .normal)
            }
            if let reason = item.invalidMappingReason {
                HStack {
                    Text("失效原因：\(reason)。记录保留，来源恢复后自动复活。")
                        .font(.caption2).foregroundStyle(.orange)
                    Spacer()
                    Button("删除失效映射记录") { world.deleteInvalidMapping(item.id) }
                        .font(.caption).foregroundStyle(.red)
                }
                .padding(.leading, 26)
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: 呈现 helper

    private func startUpdate(skills: [StubSkill]) {
        guard let skill = skills.first else { return }
        world.startUpdate(skillID: skill.id)
    }

    /// 宿主 logo 槽位：点亮 = 该平台已安装（至少一处安装），灰显 = 未安装。
    private func hostSlots(_ active: Set<StubHost>) -> some View {
        HStack(spacing: 6) {
            ForEach(StubHost.allCases) { host in
                StubHostLogo(host: host, isActive: active.contains(host))
            }
        }
    }

    private func activeHosts(of skill: StubSkill) -> Set<StubHost> {
        Set(skill.installations.map(\.host))
    }

    private func activeHosts(of source: StubSkillSource, skills: [StubSkill]) -> Set<StubHost> {
        Set(skills.flatMap { $0.installations.map(\.host) })
    }

    private func skillPreview(_ skills: [StubSkill]) -> String {
        if skills.isEmpty { return "无 Skill" }
        let names = skills.map(\.name)
        if names.count <= 3 { return names.joined(separator: "、") }
        return names.prefix(3).joined(separator: "、") + " 等 \(names.count) 个"
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

    /// 组合状态短语：多检出状态不同时如实并列（如「1 个可更新 · 1 个有改动」）。
    private func phrase(of source: StubSkillSource) -> String {
        let states = source.checkouts.map(\.state)
        let groups = Dictionary(grouping: states, by: \.group)
        if groups.count == 1, let state = states.first {
            return singlePhrase(state, behind: source.checkouts.first?.behind ?? 0)
        }
        var parts: [String] = []
        if let n = groups[.updateReady]?.count { parts.append("\(n) 个可更新") }
        if let n = groups[.needsAttention]?.count { parts.append("\(n) 个需处理") }
        if let n = groups[.unknown]?.count { parts.append("\(n) 个未检查") }
        if parts.isEmpty, let n = groups[.settled]?.count { parts.append("\(n) 个无需更新") }
        return parts.joined(separator: " · ")
    }

    private func singlePhrase(_ state: StubCheckoutState, behind: Int) -> String {
        switch state {
        case .updateAvailable: return "有更新可用 · 落后 \(behind) 个提交"
        case .upToDate: return "已是最新"
        case .aheadOnly: return "本地领先，无需更新"
        case .noRemote: return "仅本地 · 没有远程，不可更新"
        default: return state.displayName
        }
    }

    private func phraseColor(of source: StubSkillSource) -> Color {
        color(for: source.checkouts.map(\.state).min { a, b in
            StubCheckoutState.allCases.firstIndex(of: a)! < StubCheckoutState.allCases.firstIndex(of: b)!
        } ?? .checkUnknown)
    }

    private func color(for state: StubCheckoutState) -> Color {
        switch state.group {
        case .updateReady: return .blue
        case .needsAttention: return .orange
        case .unknown, .settled: return .secondary
        }
    }
}
