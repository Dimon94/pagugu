// PROTOTYPE / THROWAWAY — issue #10（Wayfinder map #1）
// 共享展示组件：prototype chrome（场景条 + variant 切换浮层）、状态徽标、更新确认/结果、
// 映射选择、审计列表与详情、Registry 受限恢复、Scan Root 管理。
// 全部内存 stub；不是生产实现。

import SwiftUI
import AppKit

// MARK: - Prototype chrome：场景条（顶部，视觉上明确是原型工具而非产品设计）

struct PrototypeScenarioBar: View {
    let world: PrototypeWorld

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("PROTOTYPE")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.purple.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.white)
                Picker("场景", selection: scenarioBinding) {
                    ForEach(StubScenario.allCases) { scenario in
                        Text(scenario.rawValue).tag(scenario)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()

                Menu("模拟") {
                    Button("模拟：来源目录移回并重新扫描（映射复活）") { world.simulateMappingRevive() }
                    Button("模拟：部分扫描结果") { world.simulatePartialScan() }
                    Button("重新扫描") { world.rescan() }
                    Divider()
                    Button("模拟：Registry 损坏") { world.simulateRegistryCorruption() }
                    Button("模拟：Registry 未知未来版本") { world.simulateFutureVersion() }
                    Toggle("模拟写失败（fail closed）", isOn: writeFailureBinding)
                }

                Spacer()

                if let notice = world.notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: 520, alignment: .trailing)
                }
            }
            Text(world.scenario.guide)
                .font(.caption)
                .foregroundStyle(.purple.opacity(0.9))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.purple.opacity(0.08))
    }

    private var scenarioBinding: Binding<StubScenario> {
        Binding(get: { world.scenario }, set: { world.load($0) })
    }

    private var writeFailureBinding: Binding<Bool> {
        Binding(get: { world.simulateRegistryWriteFailure }, set: { world.simulateRegistryWriteFailure = $0 })
    }
}

// MARK: - Prototype chrome：variant 切换浮层（底部中央，←/→ 切换，输入时不截获）

struct PrototypeSwitcherBar: View {
    @Binding var variant: PrototypeVariant

    var body: some View {
        HStack(spacing: 12) {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
            Text("\(variant.rawValue) · \(variant.title)")
                .font(.callout.weight(.medium))
                .frame(minWidth: 220)
            Button { step(1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.purple.opacity(0.6), lineWidth: 1.5))
        .shadow(radius: 8)
        .padding(.bottom, 10)
    }

    private func step(_ delta: Int) {
        let all = PrototypeVariant.allCases
        let next = (all.firstIndex(of: variant)! + delta + all.count) % all.count
        variant = all[next]
    }
}

/// 方向键监听（AppKit seam）：SwiftUI 的 keyboardShortcut 无法在「文本输入聚焦时不截获」上给出确认行为。
/// 本地 keyDown 监听：firstResponder 是文本编辑器时放行，否则 ←/→ 切换 variant 并消费事件。
struct PrototypeArrowKeyMonitor: NSViewRepresentable {
    let onStep: (Int) -> Void

    final class Coordinator {
        var monitor: Any?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 123 || event.keyCode == 124 else { return event }
            if let responder = event.window?.firstResponder, responder is NSText { return event }
            Task { @MainActor in onStep(event.keyCode == 123 ? -1 : 1) }
            return nil
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
    }
}

enum PrototypeVariant: String, CaseIterable {
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"

    var title: String {
        switch self {
        case .a: return "Skill 目录（列表 + 详情）"
        case .b: return "行动工作台（待办队列）"
        case .c: return "来源地图（来源 → Skill → 安装）"
        case .d: return "单列表（极简）"
        }
    }
}

// MARK: - 状态徽标与共享行

struct StubStatePill: View {
    let state: StubCheckoutState

    var body: some View {
        Text(state.displayName)
            .font(.caption)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch state.group {
        case .updateReady: return .blue
        case .needsAttention: return .orange
        case .unknown: return .secondary
        case .settled: return .green
        }
    }
}

struct HostBadge: View {
    let host: StubHost

    var body: some View {
        Text(host.rawValue)
            .font(.caption2)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
    }
}

/// 单个检出的状态卡片：状态 + 一句恢复方向 + 主动作（仅 Eligible 时出现更新按钮）。
struct StubCheckoutCard: View {
    let world: PrototypeWorld
    let skill: StubSkill
    let checkout: StubCheckout

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "externaldrive")
                Text(checkout.path).font(.callout.weight(.medium))
                if checkout.isChecking {
                    ProgressView().controlSize(.small)
                    Text("检查中…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                StubStatePill(state: checkout.state)
            }

            if let observation = checkout.observation {
                Text(observation.succeeded
                     ? "上次检查 \(observation.completedAt.formatted(date: .abbreviated, time: .shortened)) · 远程最新 \(observation.remoteTipSHA ?? "—")"
                     : "上次检查失败 · \(observation.completedAt.formatted(date: .abbreviated, time: .shortened)) · 重新检查即可恢复")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !checkout.isChecking {
                Text("从未检查过").font(.caption).foregroundStyle(.secondary)
            }

            if let recovery = checkout.state.recovery {
                Label(recovery, systemImage: "wrench.and.screwdriver")
                    .font(.caption).foregroundStyle(.orange)
            }

            if checkout.state == .updateAvailable {
                HStack {
                    Button("更新到 \(checkout.tipSHA)（落后 \(checkout.behind) 个提交）") {
                        world.startUpdate(skillID: skill.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(world.hasRunningWork || world.scanIsPartial || world.registryMode != .normal)
                    Text("只 fast-forward 这个工作树；不动其他检出与任何安装目录。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }
}

/// Skill 详情共用的信息块（三个 variant 各自决定把它放在哪）。
struct StubSkillDetailSections: View {
    let world: PrototypeWorld
    let skill: StubSkill

    private var installationsSummary: String {
        skill.installations.isEmpty ? "无安装，仅来源条目" : "\(skill.installations.count) 处"
    }

    var body: some View {
        if let source = world.source(for: skill) {
            GroupBox("来源") {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Skill Source", value: source.key)
                    LabeledContent("仓内路径", value: skill.relativePath)
                    Text("Skill 身份 = 来源 + 仓内路径；名称只是展示。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("安装位置（\(installationsSummary)）") {
                if skill.installations.isEmpty {
                    Text("在 Project Scan Root 中发现的 Skill：当前没有任何 Agent Host 安装它。")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(skill.installations) { installation in
                            HStack {
                                Image(systemName: installation.projection == .symlink ? "link" : "doc.on.doc")
                                Text(installation.asFoundPath).font(.callout)
                                HostBadge(host: installation.host)
                                Spacer()
                                Text(installation.projection.rawValue + (installation.attribution == .mapped ? " · 人工映射" : ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            GroupBox("检出（\(source.checkouts.count) 个物理工作树）") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(source.checkouts) { checkout in
                        StubCheckoutCard(world: world, skill: skill, checkout: checkout)
                    }
                    if source.checkouts.count > 1 {
                        Text("同一来源的多个检出分别裁决、分别呈现；其他检出的状态不影响可更新检出。")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - 更新流程 sheet（确认绑定精确 SHA；取消 / noop / 失败恢复）

struct StubUpdateSheet: View {
    let world: PrototypeWorld

    var body: some View {
        if let flow = world.update {
            switch flow.phase {
            case .rechecking:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在重新检查远程…").font(.headline)
                    Text("更新前必须按最新事实重查；上次观察结果不作为执行许可。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(32).frame(width: 420)
            case .confirming(let plan):
                StubConfirmView(world: world, plan: plan)
            case .applying(let plan):
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在 fast-forward 到 \(plan.targetSHA)…").font(.headline)
                }
                .padding(32).frame(width: 420)
            case .failed(let failure):
                VStack(alignment: .leading, spacing: 12) {
                    Label("更新未完成：\(failure.displayName)", systemImage: "xmark.octagon")
                        .font(.headline).foregroundStyle(.orange)
                    Text(failure.recovery).font(.callout)
                    Text("Pagugu 没有做任何自动重试或回滚；仓库保持 Git 事实中的当前状态。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button("知道了") { world.dismissUpdateFailure() }
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(24).frame(width: 460)
            }
        }
    }
}

struct StubConfirmView: View {
    let world: PrototypeWorld
    let plan: StubUpdatePlan

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("确认更新计划").font(.title3.weight(.semibold))

            if plan.candidateCheckoutIDs.count > 1 {
                Picker("本次更新的工作树（仅此一个）", selection: selectedBinding) {
                    ForEach(plan.candidateCheckoutIDs, id: \.self) { id in
                        Text(world.checkout(id)?.path ?? id).tag(id)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Skill", value: "\(plan.sourceKey) 的 \(plan.relativePath)")
                    LabeledContent("工作树", value: plan.checkoutPath)
                    LabeledContent("分支", value: "\(plan.branch)（跟踪 \(plan.upstream)）")
                    LabeledContent("当前", value: plan.headSHA)
                    LabeledContent("更新到", value: plan.targetSHA)
                    LabeledContent("落后", value: "\(plan.behind) 个提交")
                }
            }

            Text("影响范围：仅把上面这个工作树 fast-forward 到目标提交；不动其他检出，不写任何安装目录。确认前已按最新事实重查。")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Button("取消") { world.cancelUpdate() }
                Spacer()
                Button("确认更新到 \(plan.targetSHA)") { world.confirmUpdate() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            Text("取消的后果：确认前的检查已刷新远程引用，该检出会回到「尚未检查」，重新检查即可。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(24).frame(width: 500)
    }

    private var selectedBinding: Binding<String> {
        Binding(get: { plan.selectedCheckoutID }, set: { world.selectPlanCheckout($0) })
    }
}

// MARK: - 来源映射 sheet

struct StubMappingSheet: View {
    let world: PrototypeWorld
    @State private var selectedSkillID: String?

    var body: some View {
        if let uaID = world.mappingDraftID,
           let ua = world.unattributed.first(where: { $0.id == uaID }) {
            VStack(alignment: .leading, spacing: 12) {
                Text("指定来源").font(.title3.weight(.semibold))
                Text("\(ua.asFoundPath) 是一份复制安装，无法自动确认来源。请选择它对应的 Skill（只能选择当前已发现的 Skill）：")
                    .font(.callout)

                Picker("Skill", selection: $selectedSkillID) {
                    Text("请选择…").tag(String?.none)
                    ForEach(world.skills) { skill in
                        Text("\(skill.name) — \(world.source(for: skill)?.displayName ?? "")")
                            .tag(String?.some(skill.id))
                    }
                }
                .labelsHidden()

                if let target = selectedSkillID,
                   let skill = world.skills.first(where: { $0.id == target }),
                   skill.name != ua.displayName {
                    Label("名称不一致（\(ua.displayName) ≠ \(skill.name)）：名称只是展示元数据，不阻断映射。", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Text("映射是人工主张：每次完整扫描都会重验证；事实不再成立时自动失效并保留记录，事实恢复时自动复活。软链接与仓库本体的自动归因不可人工覆盖。")
                    .font(.caption).foregroundStyle(.secondary)

                HStack {
                    Button("取消") { world.cancelMappingDraft() }
                    Spacer()
                    Button("建立映射") {
                        if let target = selectedSkillID { world.createMapping(targetSkillID: target) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedSkillID == nil)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24).frame(width: 520)
        }
    }
}

/// 来源不明条目卡片（各 variant 共用）。
struct StubUnattributedCard: View {
    let world: PrototypeWorld
    let item: StubUnattributed

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "doc.on.doc")
                Text(item.asFoundPath).font(.callout.weight(.medium))
                HostBadge(host: item.host)
                Spacer()
                Text("来源不明")
                    .font(.caption)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
            }
            Text("复制安装，无法自动确认来源；不参与去重，不可更新。")
                .font(.caption).foregroundStyle(.secondary)
            if let reason = item.invalidMappingReason {
                Label("此前的映射已失效：\(reason)。记录保留，来源恢复后自动复活；也可显式删除。",
                      systemImage: "link.badge.plus")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack(spacing: 12) {
                Button("指定来源…") { world.beginMapping(item.id) }
                    .disabled(world.registryMode != .normal)
                if item.invalidMappingReason != nil {
                    Button("删除失效映射记录") { world.deleteInvalidMapping(item.id) }
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }
}

// MARK: - 审计：最近活动 + 单条详情 + 清空

struct StubAuditSection: View {
    let world: PrototypeWorld
    @State private var detailRecord: StubAuditRecord?
    @State private var confirmClear = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("最近活动").font(.headline)
                    Text("历史证据，只是当时记录；不代表当前状态")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("清空历史") { confirmClear = true }
                        .disabled(world.audit.isEmpty)
                        .foregroundStyle(.red)
                }
                if world.audit.isEmpty {
                    Text("暂无记录。检查、更新与来源映射的建立/删除会出现在这里。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(world.audit) { record in
                        Button { detailRecord = record } label: {
                            HStack {
                                Image(systemName: icon(for: record))
                                Text(record.subject).font(.callout)
                                Text(record.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text(record.outcomeDisplay)
                                    .font(.caption)
                                    .foregroundStyle(record.isOrphanUpdateStart || record.outcome == "failed" ? .orange : .secondary)
                                Text(record.time.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(item: $detailRecord) { record in
            StubAuditDetailView(record: record)
        }
        .confirmationDialog("清空全部历史记录？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空历史", role: .destructive) { world.clearAudit() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只删除历史证据本身；不影响 Registry、Skill 内容或任何 Git 仓库。清空后无法恢复。")
        }
    }

    private func icon(for record: StubAuditRecord) -> String {
        switch record.kind {
        case .checkRun: return "arrow.triangle.2.circlepath"
        case .updateRun: return record.isOrphanUpdateStart ? "questionmark.circle" : "arrow.down.circle"
        case .mapping: return "link"
        }
    }
}

struct StubAuditDetailView: View {
    let record: StubAuditRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(record.kind.rawValue) · \(record.subject)").font(.title3.weight(.semibold))
                Spacer()
                Text("当时记录")
                    .font(.caption)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            LabeledContent("时间", value: record.time.formatted(date: .abbreviated, time: .standard))
            LabeledContent("结果", value: record.outcomeDisplay)
            if let reason = record.reason {
                LabeledContent("原因", value: reason.displayName)
                Label(reason.recovery, systemImage: "wrench.and.screwdriver")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let plan = record.planSnapshot {
                Text(plan).font(.caption).foregroundStyle(.secondary)
            }
            Text(record.detail).font(.callout)
            Text("历史不驱动任何动作：要重试，请回到该 Skill 的当前状态照常重新发起。")
                .font(.caption2).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 480)
    }
}

// MARK: - Registry 受限恢复模式（阻断式，全窗口接管；原型 chrome 仍可用）

struct StubRegistryRecoveryView: View {
    let world: PrototypeWorld
    @State private var confirmReset = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text(world.registryMode == .futureVersion ? "Registry 由更新版本的 Pagugu 创建" : "Registry 已损坏")
                .font(.title2.weight(.semibold))
            Text(world.registryMode == .futureVersion
                 ? "为避免覆盖你无法读取的数据，Pagugu 已停止读写 Registry。请升级 Pagugu，或显式重置。"
                 : "Pagugu 无法读取你的设置记录。原文件已完整保留在：\n~/Library/Application Support/com.dimon.pagugu/registry.corrupt-20260823-1730.json")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("受限恢复模式：扫描、检查与更新均已停用。你的 Skill 与 Git 仓库未受任何影响。")
                .font(.caption).foregroundStyle(.orange)
            HStack(spacing: 16) {
                Button("重置为空 Registry…") { confirmReset = true }
                    .buttonStyle(.borderedProminent)
                Button("退出并自行修复") { world.simulateQuitForManualRepair() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog("重置为空 Registry？", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("重置为空 Registry", role: .destructive) { world.resetRegistry() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将无条件备份当前文件，然后清空全部设置：Project Scan Root 与来源映射需人工重建，检查观察可经重新检查恢复。你的 Skill 与 Git 仓库不受影响。")
        }
    }
}

// MARK: - Scan Root 管理块

struct StubScanRootSection: View {
    let world: PrototypeWorld
    @State private var showAddMenu = false

    var body: some View {
        GroupBox("扫描范围") {
            VStack(alignment: .leading, spacing: 6) {
                Label("三个个人 Skill 目录已自动发现：~/.claude/skills · ~/.agents/skills · ~/.codex/skills",
                      systemImage: "checkmark.circle")
                    .font(.caption)
                ForEach(world.scanRoots) { root in
                    HStack {
                        Image(systemName: "folder")
                        Text(root.path).font(.callout)
                        if !root.isAvailable {
                            Text("不可用：目录不存在或已移动")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        Spacer()
                        Button("删除") { world.removeScanRoot(root.id) }
                            .font(.caption)
                    }
                }
                Menu("添加 Project Scan Root…") {
                    Button("~/Code（示例）") { world.addScanRoot("~/Code") }
                    Button("~/Work（示例）") { world.addScanRoot("~/Work") }
                }
                .font(.callout)
                Text("Pagugu 只在你明确选择的目录内递归发现 Skill；不会遍历整个 Home。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
