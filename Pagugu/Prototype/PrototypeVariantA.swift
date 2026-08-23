// PROTOTYPE / THROWAWAY — issue #10（Wayfinder map #1）
// Variant A：Skill 目录 —— master-detail。侧栏按可扫读状态分组列出 Skill 与「来源不明」安装，
// 详情页承载安装位置、逐检出状态、映射与更新动作。主 affordance = 选中条目后在详情内操作。
// 全部内存 stub；不是生产实现。

import SwiftUI

struct PrototypeVariantAView: View {
    let world: PrototypeWorld
    @State private var selection: SidebarItem?
    @State private var filter = ""

    enum SidebarItem: Hashable {
        case skill(String)
        case unattributed(String)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                if world.scanRoots.isEmpty {
                    firstLaunchGuidance
                }
                ForEach(groupedSkills, id: \.group.id) { section in
                    Section(section.group.rawValue) {
                        ForEach(section.skills) { skill in
                            skillRow(skill).tag(SidebarItem.skill(skill.id))
                        }
                    }
                }
                if !world.unattributed.isEmpty {
                    Section("来源不明（复制安装）") {
                        ForEach(world.unattributed) { item in
                            HStack {
                                Text(item.displayName)
                                Spacer()
                                HostBadge(host: item.host)
                            }
                            .tag(SidebarItem.unattributed(item.id))
                        }
                    }
                }
                Section {
                    StubScanRootSection(world: world)
                }
            }
            .searchable(text: $filter, placement: .sidebar, prompt: "筛选 Skill")
            .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 420)
        } detail: {
            detailContent
                .toolbar { checkToolbar }
        }
    }

    private var firstLaunchGuidance: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("欢迎使用 Pagugu", systemImage: "shippingbox")
                .font(.headline)
            Text("个人 Skill 目录已自动发现。要看到项目里的 Skill 与它们的来源仓库，请在下方添加一个 Project Scan Root。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var groupedSkills: [(group: StubStateGroup, skills: [StubSkill])] {
        let visible = world.skills.filter {
            filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter)
        }
        return StubStateGroup.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { group in
                (group, visible.filter { world.primaryState(for: $0)?.group == group })
            }
            .filter { !$0.skills.isEmpty }
    }

    private func skillRow(_ skill: StubSkill) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(skill.name)
                if isDuplicateName(skill) {
                    Text("同名异源")
                        .font(.caption2)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(.purple.opacity(0.12), in: Capsule())
                }
                Spacer()
                if let state = world.primaryState(for: skill) {
                    StubStatePill(state: state)
                }
            }
            Text(hostsSummary(for: skill))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func hostsSummary(for skill: StubSkill) -> String {
        let hosts = skill.installations.map(\.host.rawValue)
        var seen = Set<String>()
        let unique = hosts.filter { seen.insert($0).inserted }
        if unique.isEmpty { return "仅来源条目，无安装" }
        return unique.joined(separator: " · ") + " · \(skill.installations.count) 处安装"
    }

    private func isDuplicateName(_ skill: StubSkill) -> Bool {
        world.skills.filter { $0.name == skill.name }.count > 1
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .skill(let id):
            if let skill = world.skills.first(where: { $0.id == id }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(skill.name).font(.title2.weight(.semibold))
                            if isDuplicateName(skill) {
                                Text("存在同名异源 Skill，已按来源区分")
                                    .font(.caption).foregroundStyle(.purple)
                            }
                        }
                        if let run = world.checkRun, run.isRunning {
                            Label("正在检查：已完成 \(run.finished)/\(run.total)，本地可判跳过 \(run.skipped)…",
                                  systemImage: "arrow.triangle.2.circlepath")
                                .font(.callout).foregroundStyle(.blue)
                        }
                        StubSkillDetailSections(world: world, skill: skill)
                        StubAuditSection(world: world)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("选择左侧的 Skill", systemImage: "shippingbox")
            }
        case .unattributed(let id):
            if let item = world.unattributed.first(where: { $0.id == id }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(item.displayName).font(.title2.weight(.semibold))
                        StubUnattributedCard(world: world, item: item)
                        StubAuditSection(world: world)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("选择左侧的条目", systemImage: "shippingbox")
            }
        case nil:
            ContentUnavailableView("选择一个 Skill 查看详情", systemImage: "shippingbox")
        }
    }

    @ToolbarContentBuilder
    private var checkToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("检查更新") { world.startCheckRun() }
                .disabled(!world.canStartCheckRun)
                .help(world.scanIsPartial
                      ? "扫描结果不完整：重新扫描后才能检查"
                      : "对全部应检查检出执行一次全量检查（run 中互斥）")
        }
        ToolbarItem(placement: .status) {
            if let last = world.lastObservationTime {
                Text("上次检查 \(last.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
