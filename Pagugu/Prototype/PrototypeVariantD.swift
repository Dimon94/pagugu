// PROTOTYPE / THROWAWAY — issue #10（Wayfinder map #1）
// Variant D：单列表极简 —— 整个 App 只有一份 Skill 清单。
// 每行回答三个问题：叫什么 → 现在怎么样 → 下一步做什么（至多一个动作）。
// 行按行动优先级排序：需要处理 → 可更新 → 尚未检查 → 已是最新。
// 全局只有一个动作：检查更新。来源/检出/SHA/映射全部折叠进行情；最近活动与扫描范围收进工具栏弹层。
// 全部内存 stub；不是生产实现。

import SwiftUI

struct PrototypeVariantDView: View {
    let world: PrototypeWorld
    @State private var showActivity = false
    @State private var showScanRoots = false

    enum Row: Hashable {
        case skill(String)
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
                band(.needsAttention, title: "需要处理")
                band(.updateReady, title: "可更新")
                band(.unknown, title: "尚未检查")
                band(.settled, title: "已是最新")
            }
            .listStyle(.plain)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("检查更新") { world.startCheckRun() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!world.canStartCheckRun)
                        .help(world.scanIsPartial ? "扫描结果不完整：重新扫描后才能检查" : "全量检查全部应检查检出")
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
            .navigationDestination(for: Row.self) { row in
                detail(for: row)
            }
        }
        .sheet(isPresented: $showActivity) {
            VStack(alignment: .leading) {
                StubAuditSection(world: world)
            }
            .padding(16).frame(width: 560, height: 420)
        }
        .sheet(isPresented: $showScanRoots) {
            VStack(alignment: .leading) {
                StubScanRootSection(world: world)
            }
            .padding(16).frame(width: 520)
        }
    }

    private var firstLaunchBlock: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("欢迎使用 Pagugu").font(.headline)
                Text("三个个人 Skill 目录已自动发现。添加 Project Scan Root 后，项目里的 Skill 与来源仓库也会出现在这份清单里。")
                    .font(.callout).foregroundStyle(.secondary)
                Menu("添加 Project Scan Root…") {
                    Button("~/Code（示例）") { world.addScanRoot("~/Code") }
                    Button("~/Work（示例）") { world.addScanRoot("~/Work") }
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: 优先级分组

    private func band(_ group: StubStateGroup, title: String) -> some View {
        let rows = rows(for: group)
        return Group {
            if !rows.isEmpty {
                Section(title) {
                    ForEach(rows, id: \.self) { row in
                        rowView(row)
                    }
                }
            }
        }
    }

    private func rows(for group: StubStateGroup) -> [Row] {
        var result: [Row] = world.skills
            .filter { world.primaryState(for: $0)?.group == group }
            .map { Row.skill($0.id) }
        if group == .needsAttention {
            result.append(contentsOf: world.unattributed.map { Row.unattributed($0.id) })
        }
        return result
    }

    // MARK: 行：状态 > 名字+谁在用 > 下一步动作

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        switch row {
        case .skill(let id):
            if let skill = world.skills.first(where: { $0.id == id }),
               let state = world.primaryState(for: skill) {
                NavigationLink(value: row) {
                    HStack(spacing: 10) {
                        stateIcon(state)
                        Text(skill.name)
                        if isDuplicateName(skill) {
                            Text(world.source(for: skill)?.displayName ?? "")
                                .font(.caption)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.purple.opacity(0.12), in: Capsule())
                        }
                        Text(statePhrase(state))
                            .foregroundStyle(stateColor(state))
                        Spacer()
                        Text(hostsSummary(skill))
                            .font(.caption).foregroundStyle(.secondary)
                        if state == .updateAvailable {
                            Button("更新") { world.startUpdate(skillID: skill.id) }
                                .disabled(world.hasRunningWork || world.scanIsPartial)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        case .unattributed(let id):
            if let item = world.unattributed.first(where: { $0.id == id }) {
                NavigationLink(value: row) {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(item.displayName)
                        Text(item.invalidMappingReason == nil ? "来源不明" : "映射已失效")
                            .foregroundStyle(.orange)
                        Spacer()
                        Text(item.host.rawValue)
                            .font(.caption).foregroundStyle(.secondary)
                        Button("指定来源") { world.beginMapping(item.id) }
                            .disabled(world.registryMode != .normal)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private func stateIcon(_ state: StubCheckoutState) -> some View {
        let (name, color): (String, Color) = {
            switch state.group {
            case .updateReady: return ("arrow.down.circle.fill", .blue)
            case .needsAttention: return ("exclamationmark.triangle.fill", .orange)
            case .unknown: return ("questionmark.circle", .secondary)
            case .settled: return ("checkmark.circle", .secondary)
            }
        }()
        return Image(systemName: name).foregroundStyle(color)
    }

    /// 行内状态短语：只说用户要做什么，不暴露 Git 术语。
    private func statePhrase(_ state: StubCheckoutState) -> String {
        switch state {
        case .updateAvailable: return "有更新可用"
        case .upToDate: return "已是最新"
        case .aheadOnly: return "已是最新"
        case .checkUnknown: return "尚未检查"
        default: return state.displayName
        }
    }

    private func stateColor(_ state: StubCheckoutState) -> Color {
        switch state.group {
        case .updateReady: return .blue
        case .needsAttention: return .orange
        case .unknown, .settled: return .secondary
        }
    }

    private func isDuplicateName(_ skill: StubSkill) -> Bool {
        world.skills.filter { $0.name == skill.name }.count > 1
    }

    private func hostsSummary(_ skill: StubSkill) -> String {
        var seen = Set<String>()
        let hosts = skill.installations.map(\.host.rawValue).filter { seen.insert($0).inserted }
        return hosts.isEmpty ? "仅来源" : hosts.joined(separator: " · ")
    }

    // MARK: 详情：Git 复杂度只活在这里

    @ViewBuilder
    private func detail(for row: Row) -> some View {
        switch row {
        case .skill(let id):
            if let skill = world.skills.first(where: { $0.id == id }) {
                SkillDetailView(world: world, skill: skill)
            }
        case .unattributed(let id):
            if let item = world.unattributed.first(where: { $0.id == id }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(item.displayName).font(.title2.weight(.semibold))
                        StubUnattributedCard(world: world, item: item)
                    }
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// Skill 详情：平铺分区，不套卡片盒。状态与检出 → 安装位置 → 来源 → 相关记录。
struct SkillDetailView: View {
    let world: PrototypeWorld
    let skill: StubSkill
    @State private var detailRecord: StubAuditRecord?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Text(skill.name).font(.title2.weight(.semibold))
                    if let state = world.primaryState(for: skill) {
                        StubStatePill(state: state)
                    }
                }

                if let source = world.source(for: skill) {
                    section("状态与检出") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(source.checkouts) { checkout in
                                StubCheckoutCard(world: world, skill: skill, checkout: checkout)
                            }
                            if source.checkouts.count > 1 {
                                Text("同一来源有 \(source.checkouts.count) 个检出，各自裁决；其他检出不影响可更新检出。")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }

                    section("安装位置") {
                        if skill.installations.isEmpty {
                            Text("仅来源条目：当前没有任何 Agent Host 安装它。")
                                .font(.callout).foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(skill.installations) { installation in
                                    HStack(spacing: 8) {
                                        Image(systemName: installation.projection == .symlink ? "link" : "doc.on.doc")
                                            .font(.caption)
                                        Text(installation.asFoundPath).font(.callout)
                                        HostBadge(host: installation.host)
                                        Text(installation.attribution == .mapped ? "人工映射" : installation.projection.rawValue)
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    section("来源") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.key).font(.callout).textSelection(.enabled)
                            Text("仓内路径 \(skill.relativePath) · Skill 身份 = 来源 + 仓内路径，名称只是展示。")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }

                    section("SKILL.md 原文（只读）") {
                        MarkdownSourceView(text: skill.markdownDocument)
                    }

                    let related = world.audit.filter { $0.subject.contains(skill.name) }
                    if !related.isEmpty {
                        section("相关记录（当时记录，不代表当前状态）") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(related) { record in
                                    Button { detailRecord = record } label: {
                                        HStack {
                                            Text(record.outcomeDisplay).font(.callout)
                                            Text(record.time.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption).foregroundStyle(.secondary)
                                            Spacer()
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $detailRecord) { record in
            StubAuditDetailView(record: record)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }
}
