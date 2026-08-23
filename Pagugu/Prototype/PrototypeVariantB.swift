// PROTOTYPE / THROWAWAY — issue #10（Wayfinder map #1）
// Variant B：行动工作台 —— 顶部状态条 + 「需要你处理」行动队列为主视图，全部 Skill 退为紧凑表格，
// 最近活动置于底部。主 affordance = 直接在行动卡片上操作，不先浏览列表。
// 全部内存 stub；不是生产实现。

import SwiftUI

struct PrototypeVariantBView: View {
    let world: PrototypeWorld
    @State private var detailSkillID: String?
    @State private var detailUnattributedID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statusHeader
                if world.scanRoots.isEmpty { firstLaunchCard }
                actionQueue
                allSkillsTable
                StubScanRootSection(world: world)
                StubAuditSection(world: world)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: detailSkillBinding) { skill in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(skill.name).font(.title2.weight(.semibold))
                    StubSkillDetailSections(world: world, skill: skill)
                }
                .padding(20)
            }
            .frame(width: 560, height: 520)
        }
        .sheet(item: detailUnattributedBinding) { item in
            VStack(alignment: .leading, spacing: 12) {
                Text(item.displayName).font(.title2.weight(.semibold))
                StubUnattributedCard(world: world, item: item)
            }
            .padding(20)
            .frame(width: 560)
        }
    }

    // MARK: 状态条：上次检查 + 检查动作 + run 进度

    private var statusHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                if let run = world.checkRun, run.isRunning {
                    Label("正在检查 \(run.finished)/\(run.total)（本地可判跳过 \(run.skipped)）…",
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline).foregroundStyle(.blue)
                } else if let last = world.lastObservationTime {
                    Label("上次检查：\(last.formatted(date: .abbreviated, time: .shortened))",
                          systemImage: "clock")
                        .font(.headline)
                } else {
                    Label("尚未检查过", systemImage: "questionmark.circle")
                        .font(.headline)
                }
                Text("观察时间永远伴随显示；它不是执行许可，更新前会重新检查。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button("检查更新") { world.startCheckRun() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!world.canStartCheckRun)
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private var firstLaunchCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Label("欢迎使用 Pagugu", systemImage: "shippingbox").font(.headline)
                Text("个人 Skill 目录已自动发现。添加一个 Project Scan Root 后，项目里的 Skill 与来源仓库会出现在这里。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 行动队列：可更新 / 需要处理 / 来源不明，直接给主动作

    @ViewBuilder
    private var actionQueue: some View {
        let updatable = world.skills.filter { !world.eligibleCheckouts(for: $0).isEmpty }
        let blocked = world.skills.filter {
            guard let state = world.primaryState(for: $0) else { return false }
            return state.group == .needsAttention
        }
        let unchecked = world.skills.filter { world.primaryState(for: $0)?.group == .unknown }

        if !updatable.isEmpty || !blocked.isEmpty || !world.unattributed.isEmpty || !unchecked.isEmpty {
            GroupBox("需要你处理") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(updatable) { skill in
                        actionCard(
                            icon: "arrow.down.circle.fill", tint: .blue,
                            title: "\(skill.name) 有更新可用",
                            subtitle: world.source(for: skill)?.displayName ?? "",
                            actionLabel: "更新…"
                        ) { world.startUpdate(skillID: skill.id) }
                    }
                    ForEach(blocked) { skill in
                        let state = world.primaryState(for: skill) ?? .inspectionFailed
                        actionCard(
                            icon: "exclamationmark.triangle.fill", tint: .orange,
                            title: "\(skill.name)：\(state.displayName)",
                            subtitle: state.recovery ?? "",
                            actionLabel: "查看"
                        ) { detailSkillID = skill.id }
                    }
                    ForEach(unchecked) { skill in
                        actionCard(
                            icon: "questionmark.circle", tint: .secondary,
                            title: "\(skill.name) 尚未检查",
                            subtitle: "点击顶部「检查更新」获取远程状态。",
                            actionLabel: nil
                        ) {}
                    }
                    ForEach(world.unattributed) { item in
                        actionCard(
                            icon: "link.badge.plus", tint: .orange,
                            title: "\(item.displayName) 来源不明",
                            subtitle: item.invalidMappingReason.map { "此前的映射已失效：\($0)" } ?? "复制安装，指定来源后才可更新。",
                            actionLabel: "指定来源…"
                        ) { world.beginMapping(item.id) }
                    }
                }
            }
        } else {
            GroupBox("需要你处理") {
                Label("没有待办：全部 Skill 都已确认状态。", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func actionCard(icon: String, tint: Color, title: String, subtitle: String,
                            actionLabel: String?, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            if let actionLabel {
                Button(actionLabel, action: action)
                    .disabled(world.hasRunningWork || world.registryMode != .normal)
            }
        }
        .padding(8)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }

    // MARK: 全部 Skill：紧凑表格，点击行进详情 sheet

    private var allSkillsTable: some View {
        GroupBox("全部 Skill（\(world.skills.count)）") {
            VStack(spacing: 0) {
                HStack {
                    Text("Skill").frame(width: 140, alignment: .leading)
                    Text("Agent Host").frame(width: 110, alignment: .leading)
                    Text("来源").frame(maxWidth: .infinity, alignment: .leading)
                    Text("状态").frame(width: 150, alignment: .trailing)
                }
                .font(.caption).foregroundStyle(.secondary)
                Divider()
                ForEach(world.skills) { skill in
                    Button { detailSkillID = skill.id } label: {
                        HStack {
                            Text(skill.name).frame(width: 140, alignment: .leading)
                            Text(skill.installations.map(\.host.rawValue).uniqued().joined(separator: "、"))
                                .frame(width: 110, alignment: .leading)
                                .lineLimit(1)
                            Text(world.source(for: skill)?.displayName ?? "—")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(.secondary)
                            Group {
                                if let state = world.primaryState(for: skill) {
                                    StubStatePill(state: state)
                                } else {
                                    Text("—")
                                }
                            }
                            .frame(width: 150, alignment: .trailing)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private var detailSkillBinding: Binding<StubSkill?> {
        Binding(get: { world.skills.first { $0.id == detailSkillID } },
                set: { detailSkillID = $0?.id })
    }

    private var detailUnattributedBinding: Binding<StubUnattributed?> {
        Binding(get: { world.unattributed.first { $0.id == detailUnattributedID } },
                set: { detailUnattributedID = $0?.id })
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
