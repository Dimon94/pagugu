import AppKit
import SwiftUI
import UniformTypeIdentifiers

// L3 COORD: Pagugu/Views/ContentView.swift
// POS: 主窗口内容（Variant F 主从结构，#16 落地目录 IA，#20 落地目录状态短语与静默排序，#27 接线 Update Run）。
//      左侧：平铺目录——来源仓库行（可收起/展开子 Skill 行，默认展开，chevron 独立热区）
//      + 无仓库可归行（来源不明）；消费 Skill Read Model 给出的逐态短语与五档顺序；无分组标题、无筛选 UI。
//      右侧：Skill 详情五块（状态与检出、安装位置、来源标识、SKILL.md 原文只读可选中、更新动作）；
//      空选择回欢迎引导。「相关记录」经工具栏「最近活动」承载。
//      检出卡逐检出提供「更新…」intent（仅 update-available 可用，其余禁用并给出原因）；
//      确认页列出 Skill Identity、目标检出、branch/upstream、当前 HEAD → 精确 target SHA、behind 数、
//      影响范围声明与「同一仓库的 N 个 Skill 将一起前进」名单；多 Eligible 检出当次选择不持久化。
//      结果区统一承载六类反馈（成功、noop、取消后果、写失败、刷新失败、检查总结），信息/警示分级、可关闭。
//      工具栏提供全量手动检查、扫描范围管理与「最近活动」三语义面（摘要、详情、清空确认；
//      详情标注「当时记录」，失败无 stderr/命令复制/重试，只导航相关 Skill；损坏呈现「历史不可用」）；
//      Registry 故障由全窗口门面接管，重置后呈现 quarantine 备份路径横幅。
//      View 只消费 Skill Read Model 与审计投影、只发 AppModel intent，不做 IO。
// TEST: repo://PaguguTests/AppModelTests.swift（AppModel 正常/阻断投影与 intent 路由 smoke）。

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var selection: SkillDirectoryNode?
    @State private var showsProjectScanRoots = false
    @State private var showsProjectRootImporter = false
    @State private var showsRecentActivity = false
    @State private var mappingRequest: MappingRequest?
    @State private var updateRequest: UpdateRequest?

    var body: some View {
        Group {
            if let recovery = model.registryRecovery {
                RegistryRecoveryView(recovery: recovery) {
                    await model.resetRegistry(confirmed: true)
                }
            } else if model.registryReady {
                skillBrowser
            } else {
                ProgressView("正在载入 App Registry…")
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .task {
            await model.start()
        }
        .fileImporter(
            isPresented: $showsProjectRootImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()
            Task {
                defer {
                    if hasSecurityScopedAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                await model.addProjectScanRoot(url)
            }
        }
        .fileDialogMessage("选择一个项目父目录。Pagugu 会递归发现其中的 Skill。")
        .fileDialogConfirmationLabel("添加扫描范围")
        .sheet(isPresented: $showsProjectScanRoots) {
            ProjectScanRootManagementView(
                roots: model.readModel.projectScanRoots,
                add: { showsProjectRootImporter = true },
                remove: { canonicalPath in
                    await model.removeProjectScanRoot(canonicalPath: canonicalPath)
                }
            )
        }
        .sheet(isPresented: $showsRecentActivity) {
            RecentActivitySheet(
                history: model.auditHistory,
                clear: { await model.clearAuditHistory(confirmed: true) },
                openSkill: { sourceKey, repositoryRelativePath in
                    guard let identity = model.skillIdentity(
                        matchingSnapshotSourceKey: sourceKey,
                        repositoryRelativePath: repositoryRelativePath
                    ) else { return false }
                    showsRecentActivity = false
                    selection = .skill(identity)
                    return true
                }
            )
        }
        .sheet(item: $mappingRequest) { request in
            SourceMappingSheet(
                model: model,
                installation: request.installation,
                displayName: request.displayName
            )
        }
        .sheet(item: $updateRequest) { request in
            UpdateConfirmationSheet(
                model: model,
                skill: request.skill,
                eligibleCheckoutPaths: request.eligibleCheckoutPaths,
                preselectedCheckoutPath: request.preselectedCheckoutPath
            )
        }
        .sheet(item: Binding(
            get: { model.pendingUpdatePlan.map(PreparedUpdatePlanBox.init(plan:)) },
            set: { _ in }
        )) { box in
            PreparedUpdateSheet(model: model, plan: box.plan)
        }
    }

    private var skillBrowser: some View {
        NavigationSplitView {
            SkillDirectoryListView(
                readModel: model.readModel,
                collapsedSources: model.collapsedSources,
                onToggleSource: { model.toggleSourceCollapsed($0) },
                mapSource: { installation, displayName in
                    mappingRequest = MappingRequest(
                        installation: installation,
                        displayName: displayName
                    )
                },
                deleteMapping: { path in
                    _ = await model.deleteSourceMapping(installationCanonicalPath: path)
                },
                selection: $selection
            )
        } detail: {
            VStack(spacing: 0) {
                ResultAreaView(model: model)
                detailView
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let progress = model.checkRunProgress {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("检查中 \(progress.completed)/\(progress.total)")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("检查更新", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await model.checkNow() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canStartCheckRun)
                    .help(model.canStartCheckRun ? "全量检查当前完整 Scan Result 中的检出。" : model.checkRunDisabledReason)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("扫描范围", systemImage: "folder.badge.gearshape") {
                    showsProjectScanRoots = true
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("最近活动", systemImage: "clock.arrow.circlepath") {
                    showsRecentActivity = true
                }
            }
        }
    }

    // MARK: - 右侧详情（与目录选择联动；空选择或选择失效回欢迎引导）

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .source(let key):
            if let source = model.readModel.sourceItem(for: key) {
                SkillSourcePanel(source: source, onSelectSkill: { selection = .skill($0) })
            } else {
                welcomePanel
            }
        case .skill(let identity):
            if let entry = model.readModel.skillEntry(for: identity) {
                SkillDetailPanel(
                    entry: entry,
                    checkouts: model.readModel.checkoutCards(for: entry.id.sourceKey),
                    markdown: model.skillMarkdown(canonicalPath: entry.canonicalPath),
                    canStartUpdate: model.canStartUpdateRun,
                    updateDisabledReason: model.updateRunDisabledReason,
                    isPreparingUpdate: model.activeRun == .updatePreparing,
                    startUpdate: { checkoutPath in
                        updateRequest = UpdateRequest(
                            skill: entry,
                            eligibleCheckoutPaths: model.eligibleUpdateCheckoutPaths(for: entry.id),
                            preselectedCheckoutPath: checkoutPath
                        )
                    },
                    deleteMapping: { path in
                        _ = await model.deleteSourceMapping(installationCanonicalPath: path)
                    }
                )
            } else {
                welcomePanel
            }
        case .invalidMapping(let path):
            if let mapping = model.readModel.invalidMapping(for: path) {
                InvalidSourceMappingPanel(mapping: mapping) {
                    _ = await model.deleteSourceMapping(installationCanonicalPath: path)
                }
            } else {
                welcomePanel
            }
        case .unattributedInstallation(let id):
            if let item = model.readModel.unattributedItem(for: id) {
                UnattributedInstallationPanel(
                    item: item,
                    markdown: model.skillMarkdown(canonicalPath: item.canonicalPath)
                )
            } else {
                welcomePanel
            }
        case nil:
            welcomePanel
        }
    }

    private var welcomePanel: some View {
        WelcomePanel {
            showsProjectRootImporter = true
        }
    }
}

// MARK: - 结果区（六类反馈：成功、noop、取消后果、写失败、刷新失败、检查总结）
// 信息/警示分级、可关闭；同一动作不出现第二处反馈样式。

private struct ResultAreaView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if let backupPath = model.registryResetBackupPath {
                ResultBanner(
                    level: .info,
                    icon: "checkmark.circle",
                    text: "Registry 已重置为空。原文件备份在：\(backupPath)",
                    onDismiss: { model.dismissRegistryResetBackupPath() }
                )
            }
            if let progress = model.checkRunProgress {
                ResultBanner(
                    level: .info,
                    icon: "arrow.triangle.2.circlepath",
                    text: "检查中 \(progress.completed)/\(progress.total)",
                    onDismiss: nil
                )
            } else if let summary = model.checkRunSummary {
                ResultBanner(
                    level: summary.outcome == .complete ? .info : .warning,
                    icon: summary.outcome == .complete ? "checkmark.circle"
                        : summary.outcome == .partial ? "exclamationmark.triangle" : "xmark.circle",
                    text: "检查\(summary.outcome.rawValue)：成功 \(summary.succeeded) · 失败 \(summary.failed) · 不适用 \(summary.skipped)",
                    onDismiss: { model.dismissCheckRunSummary() }
                )
            }
            if let result = model.updateResult {
                updateResultBanner(result)
            }
            if let refreshFailure = model.updateRefreshFailure {
                ResultBanner(
                    level: .warning,
                    icon: "exclamationmark.triangle",
                    text: refreshFailure.outcome == .partial
                        ? "更新后的完整刷新部分完成（\(refreshFailure.issueCount) 个 Scan Issue）。更新本身已成功；可稍后重新扫描。"
                        : "更新后的完整刷新失败。更新本身已成功；请重新扫描。",
                    onDismiss: nil
                )
            }
            if let error = model.projectScanRootError {
                ResultBanner(
                    level: .warning,
                    icon: "exclamationmark.triangle",
                    text: "无法保存 App Registry：\(error.reason)",
                    onDismiss: { model.clearProjectScanRootError() }
                )
            }
            if let error = model.sourceMappingError {
                ResultBanner(
                    level: .warning,
                    icon: "exclamationmark.triangle",
                    text: "无法保存来源映射：\(error.reason)",
                    onDismiss: { model.clearSourceMappingError() }
                )
            }
        }
    }

    @ViewBuilder
    private func updateResultBanner(_ result: UpdateResult) -> some View {
        switch result {
        case .success(_, let targetSHA):
            ResultBanner(
                level: .info,
                icon: "checkmark.circle",
                text: "更新成功。已 fast-forward 到目标提交（\(String(targetSHA.prefix(7)))）。",
                onDismiss: { model.dismissUpdateResult() }
            )
        case .upToDate:
            ResultBanner(
                level: .info,
                icon: "checkmark.circle",
                text: "已是最新：重查发现远端没有新提交，未做任何修改。",
                onDismiss: { model.dismissUpdateResult() }
            )
        case .cancelled:
            ResultBanner(
                level: .warning,
                icon: "exclamationmark.triangle",
                text: UpdateResult.cancellationConsequence,
                onDismiss: { model.dismissUpdateResult() }
            )
        case .failed(let failure):
            ResultBanner(
                level: .warning,
                icon: "xmark.circle",
                text: "更新失败：\(failure.reason.displayName)。\(failure.recoveryDirection)",
                onDismiss: { model.dismissUpdateResult() }
            )
        }
    }
}

private struct ResultBanner: View {
    enum Level {
        case info
        case warning
    }

    let level: Level
    let icon: String
    let text: String
    let onDismiss: (() -> Void)?

    private var color: Color {
        switch level {
        case .info: return .green
        case .warning: return .orange
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.callout)
            Spacer()
            if let onDismiss {
                Button("关闭", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(color.opacity(0.10))
    }
}

// MARK: - 更新确认（多检出当次选择 + 冻结计划确认）

private struct UpdateRequest: Identifiable {
    var id: String { skill.id.sourceKey.registryValue + "|" + skill.id.repositoryRelativePath }

    let skill: SkillDirectoryEntry
    let eligibleCheckoutPaths: [String]
    var preselectedCheckoutPath: String?
}

private struct PreparedUpdatePlanBox: Identifiable {
    var id: String { plan.runID }

    let plan: UpdatePlan
}

// MARK: - 更新确认 sheet：重查前选择目标检出（多 Eligible 时）

private struct UpdateConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    let skill: SkillDirectoryEntry
    let eligibleCheckoutPaths: [String]
    @State private var selectedCheckoutPath: String?
    @State private var isPreparing = false
    var preselectedCheckoutPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("更新 \(skill.displayName)")
                    .font(.title2.bold())
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            if eligibleCheckoutPaths.count > 1 {
                Text("该来源有 \(eligibleCheckoutPaths.count) 个可更新检出。当次选择一个，不持久化。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker("目标检出", selection: $selectedCheckoutPath) {
                    ForEach(eligibleCheckoutPaths, id: \.self) { path in
                        Text(path).tag(Optional(path))
                    }
                }
                .pickerStyle(.radioGroup)
            } else {
                Text("目标检出：\(eligibleCheckoutPaths.first ?? "Unknown")")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }

            Text("确认后 Pagugu 会先 fetch 并重查该检出，再给出精确计划。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                Button {
                    guard let path = selectedCheckoutPath ?? eligibleCheckoutPaths.first else { return }
                    isPreparing = true
                    Task {
                        do {
                            try await model.prepareUpdate(skillIdentity: skill.id, checkoutPath: path)
                            dismiss()
                        } catch {
                            isPreparing = false
                        }
                    }
                } label: {
                    if isPreparing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("正在重查…")
                        }
                    } else {
                        Text("重查并确认")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPreparing)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 240)
        .onAppear {
            selectedCheckoutPath = preselectedCheckoutPath ?? eligibleCheckoutPaths.first
        }
    }
}

// MARK: - 冻结计划确认 sheet（S5：列出 Skill Identity、目标检出、branch/upstream、HEAD→SHA、behind、影响范围）

private struct PreparedUpdateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    let plan: UpdatePlan
    @State private var isExecuting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("确认更新")
                    .font(.title2.bold())
                Spacer()
                Button("关闭") { Task { await model.cancelUpdate(); dismiss() } }
                    .keyboardShortcut(.cancelAction)
            }

            GroupBox("计划") {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Skill") {
                        Text("\(plan.skillIdentity.sourceKey.registryValue) · \(plan.skillIdentity.repositoryRelativePath.isEmpty ? "（仓库根目录）" : plan.skillIdentity.repositoryRelativePath)")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("目标检出") {
                        Text(plan.checkoutCanonicalPath)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("分支 / upstream") {
                        Text("\(plan.branchName) / \(plan.upstreamRefName)")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("当前 HEAD → 目标") {
                        Text("\(String(plan.currentHeadSHA.prefix(7))) → \(String(plan.targetSHA.prefix(7)))")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("落后") {
                        Text("\(plan.behindCount) 个提交")
                            .font(.caption)
                    }
                }
            }

            Text(plan.impactStatement)
                .font(.callout)
                .foregroundStyle(.secondary)

            if plan.affectedSkills.count > 1 {
                GroupBox("影响范围") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("同一仓库的 \(plan.affectedSkills.count) 个 Skill 将一起前进：")
                            .font(.caption)
                        ForEach(plan.affectedSkills, id: \.identity.repositoryRelativePath) { affected in
                            Text("\(affected.displayName)（\(affected.identity.repositoryRelativePath.isEmpty ? "仓库根目录" : affected.identity.repositoryRelativePath)）")
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack {
                Spacer()
                Button("取消", role: .cancel) {
                    Task { await model.cancelUpdate(); dismiss() }
                }
                Button {
                    isExecuting = true
                    Task {
                        do {
                            try await model.confirmUpdate()
                            dismiss()
                        } catch {
                            isExecuting = false
                        }
                    }
                } label: {
                    if isExecuting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("正在执行…")
                        }
                    } else {
                        Text("确认更新")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExecuting)
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 360)
    }
}

private struct MappingRequest: Identifiable {
    var id: String { installation.canonicalPath }

    let installation: SkillInstallation
    let displayName: String
}

// MARK: - Project Scan Root 管理

private struct ProjectScanRootManagementView: View {
    @Environment(\.dismiss) private var dismiss

    let roots: [ProjectScanRoot]
    let add: () -> Void
    let remove: (String) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("扫描范围")
                    .font(.title2.bold())
                Spacer()
                Button("关闭") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            if roots.isEmpty {
                ContentUnavailableView(
                    "尚未添加 Project Scan Root",
                    systemImage: "folder.badge.plus",
                    description: Text("添加项目父目录后，Pagugu 会保存顺序并执行一次完整 Discovery Scan。")
                )
            } else {
                List(roots) { root in
                    HStack(spacing: 12) {
                        Image(systemName: root.isAvailable ? "folder" : "folder.badge.questionmark")
                            .foregroundStyle(root.isAvailable ? Color.secondary : Color.orange)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(root.asFoundPath)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                            if let reason = root.unavailableReason {
                                Text("不可用：\(reason)。路径恢复后会自动复活。")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }

                        Spacer()

                        Button("删除", systemImage: "trash", role: .destructive) {
                            Task { await remove(root.canonicalPath) }
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("删除扫描范围 \(root.asFoundPath)")
                    }
                }
            }

            HStack {
                Text("删除只移除主张记录，不会触碰目录、Skill Source 或 Git 工作树。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("添加 Project Scan Root", systemImage: "plus") {
                    add()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 660, minHeight: 420)
    }
}

// MARK: - Registry 受限恢复

private struct RegistryRecoveryView: View {
    let recovery: RegistryRecovery
    let reset: () async -> Void
    @State private var showsResetConfirmation = false

    var body: some View {
        ContentUnavailableView {
            Label("App Registry 需要恢复", systemImage: "exclamationmark.lock")
        } description: {
            VStack(spacing: 8) {
                Text(description)
                Text(recovery.evidenceURL.path)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
        } actions: {
            Button("重置为空 Registry", role: .destructive) {
                showsResetConfirmation = true
            }
            Button("退出自行修复") {
                NSApplication.shared.terminate(nil)
            }
        }
        .alert("确认重置 App Registry？", isPresented: $showsResetConfirmation) {
            Button("取消", role: .cancel) {}
            Button("重置为空 Registry", role: .destructive) {
                Task { await reset() }
            }
        } message: {
            Text(Persistence.resetImpact)
        }
    }

    private var description: String {
        switch recovery.kind {
        case .corrupt:
            return "Registry 已损坏。原文件已保留。你可以重置为空 Registry，或退出后自行修复。"
        case .unknownFutureVersion:
            return "Registry 来自更新版本。请升级 Pagugu，或退出后自行修复。应用不会覆写该文件。"
        case .externallyModified:
            return "检测到 Registry 被外部修改。请退出并重新打开 Pagugu，或确认重置。"
        case .writeFailed:
            return "Registry 写入失败。请检查磁盘空间与目录权限后重试，或退出自行修复。"
        }
    }
}

// MARK: - 左侧目录

private struct SkillDirectoryListView: View {
    let readModel: SkillReadModel
    let collapsedSources: Set<SkillSourceKey>
    let onToggleSource: (SkillSourceKey) -> Void
    let mapSource: (SkillInstallation, String) -> Void
    let deleteMapping: (String) async -> Void
    @Binding var selection: SkillDirectoryNode?

    var body: some View {
        Group {
            if readModel.isEmpty {
                // 正常空态
                ContentUnavailableView(
                    "未发现 Skill",
                    systemImage: "tray",
                    description: Text("三个 Personal Skill Root 与已保存的 Project Scan Root 下没有可解析的 Skill。")
                )
            } else {
                List(selection: $selection) {
                    if !readModel.issues.isEmpty {
                        Section {
                            ForEach(readModel.issues, id: \.path) { issue in
                                VStack(alignment: .leading, spacing: 2) {
                                    Label("扫描问题", systemImage: "exclamationmark.triangle")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                    Text(issue.path)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(issue.reason)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Section {
                        ForEach(readModel.directoryNodes(collapsedSources: collapsedSources), id: \.self) { node in
                            row(for: node)
                                .tag(node)
                        }
                    }
                }
            }
        }
        .navigationTitle("Skills")
    }

    @ViewBuilder
    private func row(for node: SkillDirectoryNode) -> some View {
        switch node {
        case .source(let key):
            if let source = readModel.sourceItem(for: key) {
                SkillSourceRow(
                    source: source,
                    statusPhrase: readModel.directoryStatusPhrase(for: key),
                    isCollapsed: collapsedSources.contains(key),
                    onToggle: { onToggleSource(key) }
                )
            }
        case .skill(let identity):
            if let entry = readModel.skillEntry(for: identity) {
                SkillRow(entry: entry)
            }
        case .unattributedInstallation(let id):
            if let item = readModel.unattributedItem(for: id) {
                UnattributedInstallationRow(
                    item: item,
                    mapSource: mapSource,
                    deleteMapping: deleteMapping
                )
            }
        case .invalidMapping(let path):
            if let mapping = readModel.invalidMapping(for: path) {
                InvalidSourceMappingRow(mapping: mapping, deleteMapping: deleteMapping)
            }
        }
    }
}

// MARK: - 来源仓库行（呈现分组；chevron 独立热区，不误触行选择）

private struct SkillSourceRow: View {
    let source: SkillSourceItem
    let statusPhrase: String?
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Button(action: onToggle) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCollapsed ? "展开" : "收起")

                Text(source.displayName)
                    .font(.headline)
                Spacer()
                HostLogoSlots(hosts: source.hosts)
            }
            if let statusPhrase {
                Text(statusPhrase)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 24)
            }
            Text(source.id.displayString)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 24)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 仓库下的子 Skill 行

private struct SkillRow: View {
    let entry: SkillDirectoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.displayName)
                    .font(.callout)
                Spacer()
                HostLogoSlots(hosts: entry.hosts)
            }
            if entry.id.repositoryRelativePath != entry.displayName {
                Text(entry.id.repositoryRelativePath.isEmpty ? "（仓库根目录）" : entry.id.repositoryRelativePath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 24)
        .padding(.vertical, 2)
    }
}

// MARK: - 无仓库可归行（来源不明）

private struct UnattributedInstallationRow: View {
    let item: UnattributedInstallationItem
    let mapSource: (SkillInstallation, String) -> Void
    let deleteMapping: (String) async -> Void
    @State private var mappingPathToDelete: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(item.displayName)
                    .font(.callout)
                Text("来源不明")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Spacer()
                HostLogoSlots(hosts: item.hosts)
                if item.installations.contains(where: {
                    $0.projectionType == .copy || $0.sourceMapping != nil
                }) {
                    Menu("来源映射") {
                        ForEach(item.installations, id: \.asFoundPath) { installation in
                            if installation.projectionType == .copy && installation.sourceMapping == nil {
                                Button("指定：\(installation.asFoundPath)") {
                                    mapSource(installation, item.displayName)
                                }
                            } else if installation.sourceMapping != nil {
                                Button("删除：\(installation.asFoundPath)", role: .destructive) {
                                    mappingPathToDelete = installation.canonicalPath
                                }
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .accessibilityLabel("管理 \(item.displayName) 的来源映射")
                }
            }
            // 消歧 caption：聚合组显示安装位置数，单例显示路径（同名不同内容按此区分）
            Text(item.installations.count > 1
                 ? "\(item.installations.count) 个安装位置"
                 : (item.installations.first?.asFoundPath ?? item.canonicalPath))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
        .alert(
            "确认删除来源映射？",
            isPresented: Binding(
                get: { mappingPathToDelete != nil },
                set: { if !$0 { mappingPathToDelete = nil } }
            )
        ) {
            Button("取消", role: .cancel) { mappingPathToDelete = nil }
            Button("删除映射", role: .destructive) {
                guard let path = mappingPathToDelete else { return }
                mappingPathToDelete = nil
                Task { await deleteMapping(path) }
            }
        } message: {
            Text("只删除映射记录。不会修改 Skill Installation、Skill Source 或 Git 工作树。")
        }
    }
}

private struct InvalidSourceMappingRow: View {
    let mapping: SourceMappingProjection
    let deleteMapping: (String) async -> Void
    @State private var showsDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("来源映射失效", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(mapping.installationCanonicalPath)
                .font(.caption2.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            Button("删除映射", role: .destructive) { showsDeleteConfirmation = true }
                .font(.caption)
        }
        .alert("确认删除来源映射？", isPresented: $showsDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除映射", role: .destructive) {
                Task { await deleteMapping(mapping.installationCanonicalPath) }
            }
        } message: {
            Text("只删除映射记录。不会修改 Skill Installation、Skill Source 或 Git 工作树。")
        }
    }
}

// MARK: - 宿主 logo 槽位（占位图形，真实 logo 归后续票）

private struct HostLogoSlots: View {
    let hosts: Set<AgentHost>

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AgentHost.allCases, id: \.self) { host in
                HostLogoDot(host: host, isActive: hosts.contains(host))
            }
        }
    }
}

private struct HostLogoDot: View {
    let host: AgentHost
    let isActive: Bool

    var body: some View {
        Circle()
            .fill(isActive ? Color.primary : Color.secondary)
            .opacity(isActive ? 1.0 : 0.3)
            .frame(width: 8, height: 8)
            .help(host.displayName + (isActive ? "（已安装）" : "（未安装）"))
    }
}

// MARK: - 右侧详情：来源仓库行

private struct SkillSourcePanel: View {
    let source: SkillSourceItem
    let onSelectSkill: (SkillIdentity) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(source.displayName)
                        .font(.title2.bold())
                    HostLogoSlots(hosts: source.hosts)
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("包含的 Skill（\(source.skills.count) 个）")
                        .font(.headline)
                    ForEach(source.skills) { entry in
                        Button {
                            onSelectSkill(entry.id)
                        } label: {
                            HStack {
                                Text(entry.displayName)
                                    .font(.body)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                SourceIdentityBlock(sourceKey: source.id, repositoryRelativePath: nil)

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 右侧详情：Skill（状态与检出、安装位置、来源标识、SKILL.md 原文）

private struct SkillDetailPanel: View {
    let entry: SkillDirectoryEntry
    let checkouts: [CheckoutCardReadModel]
    let markdown: String?
    let canStartUpdate: Bool
    let updateDisabledReason: String
    let isPreparingUpdate: Bool
    let startUpdate: (String?) -> Void
    let deleteMapping: (String) async -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.displayName)
                        .font(.title2.bold())
                    HostLogoSlots(hosts: entry.hosts)
                }

                Divider()

                CheckoutStatusBlock(
                    checkouts: checkouts,
                    canStartUpdate: canStartUpdate,
                    updateDisabledReason: updateDisabledReason,
                    isPreparingUpdate: isPreparingUpdate,
                    startUpdate: startUpdate
                )

                Divider()

                InstallationsBlock(
                    installations: entry.installations,
                    deleteMapping: deleteMapping
                )

                Divider()

                SourceIdentityBlock(
                    sourceKey: entry.id.sourceKey,
                    repositoryRelativePath: entry.id.repositoryRelativePath
                )

                Divider()

                MarkdownSourceBlock(markdown: markdown)

                Divider()

                UpdateActionBlock(
                    checkouts: checkouts,
                    canStartUpdate: canStartUpdate,
                    updateDisabledReason: updateDisabledReason,
                    isPreparingUpdate: isPreparingUpdate,
                    startUpdate: startUpdate
                )

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 详情块：状态与检出（逐检出，不造来源级聚合状态）

private struct CheckoutStatusBlock: View {
    let checkouts: [CheckoutCardReadModel]
    let canStartUpdate: Bool
    let updateDisabledReason: String
    let isPreparingUpdate: Bool
    let startUpdate: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("状态与检出")
                .font(.headline)
            ForEach(checkouts) { checkout in
                CheckoutCard(
                    checkout: checkout,
                    canStartUpdate: canStartUpdate,
                    updateDisabledReason: updateDisabledReason,
                    isPreparingUpdate: isPreparingUpdate,
                    startUpdate: startUpdate
                )
            }
        }
    }
}

// MARK: - 详情块：更新动作（逐检出 intent 入口；S5/US14）

private struct UpdateActionBlock: View {
    let checkouts: [CheckoutCardReadModel]
    let canStartUpdate: Bool
    let updateDisabledReason: String
    let isPreparingUpdate: Bool
    let startUpdate: (String?) -> Void

    private var eligibleCheckouts: [CheckoutCardReadModel] {
        checkouts.filter { $0.state == .updateAvailable }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("更新动作")
                .font(.headline)
            if eligibleCheckouts.isEmpty {
                Text("当前没有可更新的检出。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(eligibleCheckouts.count == 1
                     ? "1 个检出可更新。"
                     : "\(eligibleCheckouts.count) 个检出可更新；确认时当次选择一个，不持久化。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    startUpdate(nil)
                } label: {
                    if isPreparingUpdate {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("正在重查…")
                        }
                    } else {
                        Text("更新…")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStartUpdate || isPreparingUpdate)
                .help(updateHelp)
            }
        }
    }

    private var updateHelp: String {
        if !canStartUpdate { return updateDisabledReason }
        return "重查并确认精确计划后执行；一次只更新一个工作树。"
    }
}

private struct CheckoutCard: View {
    let checkout: CheckoutCardReadModel
    var canStartUpdate: Bool = false
    var updateDisabledReason: String = ""
    var isPreparingUpdate: Bool = false
    var startUpdate: ((String?) -> Void)? = nil

    private var isEligible: Bool {
        checkout.state == .updateAvailable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(checkout.state.displayName)
                    .font(.headline)
                Text(checkout.state.rawValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                if isEligible {
                    Button {
                        startUpdate?(checkout.id)
                    } label: {
                        if isPreparingUpdate {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.mini)
                                Text("重查中…")
                            }
                        } else {
                            Text("更新…")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canStartUpdate || isPreparingUpdate)
                    .help(updateButtonHelp)
                }
            }
            Text(checkout.state.recoveryDirection)
                .font(.caption)
                .foregroundStyle(.secondary)
            if checkout.isChecking {
                Label("检查中", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            if let outcome = checkout.checkOutcome {
                checkOutcome(outcome)
            }
            if checkout.observation?.result == .failure, checkout.checkOutcome == nil {
                Text(CheckRunFailure.fetchFailed.message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let observation = checkout.observation {
                fact("观察时间", observation.completedAt.formatted(date: .abbreviated, time: .standard))
            }
            fact("检出路径", checkout.facts.checkoutPath)
            fact("Git common dir", checkout.facts.gitCommonDirectory ?? "Unknown")
            fact("HEAD", headText)
            fact("origin", checkout.facts.originRemoteURL ?? "无")
            fact("upstream", upstreamText)
            fact("相对位置", relativePositionText)
            fact("严格 dirty", dirtyText)
            fact("兄弟分支冲突", checkout.facts.siblingBranchConflict ? "是" : "否")
            fact("worktree", worktreeText)
            if let failure = checkout.facts.inspectionFailure {
                fact("检查错误", failureText(failure))
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func checkOutcome(_ outcome: CheckRunItemOutcome) -> some View {
        switch outcome {
        case .success:
            EmptyView()
        case .notApplicable:
            Text("本次检查：不适用")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let reason):
            Text(reason.message)
                .font(.caption)
                .foregroundStyle(.red)
        case .discarded:
            Text("检查期间检出身份已变化。本次观察已丢弃；请重新检查。")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func fact(_ name: String, _ value: String) -> some View {
        LabeledContent(name) {
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
    }

    private var updateButtonHelp: String {
        if !canStartUpdate { return updateDisabledReason }
        return "重查并确认精确计划后执行；一次只更新一个工作树。"
    }

    private var headText: String {
        switch checkout.facts.head {
        case .branch(let name, let sha): return "\(name) @ \(sha)"
        case .detached(let sha): return "detached @ \(sha)"
        case nil: return "Unknown"
        }
    }

    private var upstreamText: String {
        guard let upstream = checkout.facts.upstream else { return "无" }
        return "\(upstream.ref) · \(upstream.remoteURL ?? "Unknown")"
    }

    private var relativePositionText: String {
        switch checkout.facts.relativePosition {
        case .unknown: return "Unknown（尚未检查）"
        case .upToDate: return "ahead 0 · behind 0"
        case .aheadOnly(let ahead): return "ahead \(ahead) · behind 0"
        case .behindOnly(let behind): return "ahead 0 · behind \(behind)"
        case .diverged(let ahead, let behind): return "ahead \(ahead) · behind \(behind)"
        }
    }

    private var dirtyText: String {
        let facts = checkout.facts.dirty
        var kinds: [String] = []
        if facts.staged { kinds.append("staged") }
        if facts.unstaged { kinds.append("unstaged") }
        if facts.untracked { kinds.append("untracked") }
        if facts.unmerged { kinds.append("unmerged") }
        if facts.submodule { kinds.append("submodule") }
        kinds.append(contentsOf: facts.operations.map(\.rawValue).sorted())
        return kinds.isEmpty ? "干净" : kinds.joined(separator: "、")
    }

    private var worktreeText: String {
        checkout.facts.worktrees
            .map { "\($0.path) [\($0.branch ?? "detached")]" }
            .joined(separator: "\n")
    }

    private func failureText(_ failure: GitInspectionFailure) -> String {
        switch failure {
        case .notAWorkTree: return "不是有效 Git 工作树"
        case .launchFailed: return "Git 启动失败"
        case .timedOut: return "Git 命令超时"
        case .commandFailed(let exitCode, _): return "Git 命令失败（exit \(exitCode)）"
        }
    }
}

// MARK: - 右侧详情：无仓库可归（来源不明）

private struct UnattributedInstallationPanel: View {
    let item: UnattributedInstallationItem
    let markdown: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.displayName)
                        .font(.title2.bold())
                    HostLogoSlots(hosts: item.hosts)
                }

                Divider()

                InstallationsBlock(installations: item.installations)

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("来源标识")
                        .font(.headline)
                    Text("来源不明")
                        .font(.body)
                        .foregroundStyle(.orange)
                    Text("复制投影未关联任何已发现 Skill Source；不参与更新。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if item.installations.count > 1 {
                        Text("内容完全一致的 \(item.installations.count) 个安装位置已聚合为一个条目（仍来源不明、不可更新）。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                MarkdownSourceBlock(markdown: markdown)

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 详情块：安装位置（路径 + 宿主 + 投影/归因）

private struct InstallationsBlock: View {
    let installations: [SkillInstallation]
    var deleteMapping: ((String) async -> Void)? = nil
    @State private var mappingPathToDelete: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("安装位置")
                .font(.headline)
            if installations.isEmpty {
                Text("未安装到任何 Agent Host（仅在扫描范围内发现）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(installations, id: \.asFoundPath) { installation in
                VStack(alignment: .leading, spacing: 2) {
                    Text(installation.asFoundPath)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                    // 软链接安装的解析目标（归因证据）；as-found 即 canonical 时不重复显示
                    if installation.canonicalPath != (installation.asFoundPath as NSString).expandingTildeInPath {
                        Text("→ \(installation.canonicalPath)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    HStack(spacing: 6) {
                        HostLogoSlots(hosts: installation.hosts)
                        Text(installation.projectionType.displayName + attributionNote(for: installation))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if let mapping = installation.sourceMapping {
                        switch mapping.validity {
                        case .invalid(let reason):
                            Text("映射失效：\(reason.message)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        case .unverified:
                            Text("扫描不完整，暂不重验证该映射。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .valid:
                            EmptyView()
                        }
                    }
                    if installation.isManuallyMapped, deleteMapping != nil {
                        Button("删除来源映射", role: .destructive) {
                            mappingPathToDelete = installation.canonicalPath
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .alert(
            "确认删除来源映射？",
            isPresented: Binding(
                get: { mappingPathToDelete != nil },
                set: { if !$0 { mappingPathToDelete = nil } }
            )
        ) {
            Button("取消", role: .cancel) { mappingPathToDelete = nil }
            Button("删除映射", role: .destructive) {
                guard let path = mappingPathToDelete, let deleteMapping else { return }
                mappingPathToDelete = nil
                Task { await deleteMapping(path) }
            }
        } message: {
            Text("只删除映射记录。该复制投影会回到来源不明；不会修改磁盘内容。")
        }
    }

    private func attributionNote(for installation: SkillInstallation) -> String {
        if installation.isManuallyMapped { return " · 人工映射" }
        switch installation.projectionType {
        case .symlink: return " · 已归因到本来源"
        case .repositorySelf: return " · 安装路径即来源工作树"
        case .copy: return " · 来源不明"
        }
    }
}

// MARK: - 详情块：来源标识

private struct SourceIdentityBlock: View {
    let sourceKey: SkillSourceKey
    let repositoryRelativePath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("来源标识")
                .font(.headline)
            LabeledContent("Skill Source Key") {
                Text(sourceKey.displayString)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
            if let repositoryRelativePath {
                LabeledContent("仓内相对路径") {
                    Text(repositoryRelativePath.isEmpty ? "（仓库根目录）" : repositoryRelativePath)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
    }
}

// MARK: - 详情块：SKILL.md 原文（只读、可选中）

private struct MarkdownSourceBlock: View {
    let markdown: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SKILL.md 原文（只读）")
                .font(.headline)
            if let markdown {
                Text(markdown)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            } else {
                Text("无法读取 SKILL.md。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 来源映射

private struct MappingTargetGroup: Identifiable {
    var id: SkillSourceKey { sourceKey }

    let sourceKey: SkillSourceKey
    let entries: [SkillDirectoryEntry]
}

private struct SourceMappingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    let installation: SkillInstallation
    let displayName: String
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("指定来源")
                        .font(.title2.bold())
                    Text(installation.asFoundPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            if model.readModel.mappingTargets.isEmpty {
                ContentUnavailableView(
                    "没有可指定的 Skill",
                    systemImage: "folder.badge.plus",
                    description: Text("请先添加包含 Skill Source 的 Project Scan Root。")
                )
            } else {
                List {
                    ForEach(filteredGroups) { group in
                        Section(group.sourceKey.registryValue) {
                            ForEach(group.entries) { target in
                                Button {
                                    Task {
                                        let created = await model.createSourceMapping(
                                            installationCanonicalPath: installation.canonicalPath,
                                            targetIdentity: target.id
                                        )
                                        if created { dismiss() }
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(target.displayName)
                                        Text(target.id.repositoryRelativePath.isEmpty
                                             ? "（仓库根目录）"
                                             : target.id.repositoryRelativePath)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                        if target.displayName != displayName {
                                            Label(
                                                "frontmatter name 不同；名称不参与身份，不阻断指定。",
                                                systemImage: "exclamationmark.triangle"
                                            )
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("指定来源为 \(target.displayName)")
                            }
                        }
                    }
                }
                .searchable(text: $query, prompt: "筛选 Skill 或来源")
            }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 480)
    }

    private var filteredGroups: [MappingTargetGroup] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let targets = model.readModel.mappingTargets.filter { target in
            needle.isEmpty || target.displayName.lowercased().contains(needle) ||
                target.id.sourceKey.registryValue.lowercased().contains(needle) ||
                target.id.repositoryRelativePath.lowercased().contains(needle)
        }
        return Dictionary(grouping: targets, by: { $0.id.sourceKey })
            .map { sourceKey, entries in
                MappingTargetGroup(
                    sourceKey: sourceKey,
                    entries: entries.sorted { $0.displayName < $1.displayName }
                )
            }
            .sorted { $0.sourceKey.registryValue < $1.sourceKey.registryValue }
    }
}

private struct InvalidSourceMappingPanel: View {
    let mapping: SourceMappingProjection
    let deleteMapping: () async -> Void
    @State private var showsDeleteConfirmation = false

    var body: some View {
        ContentUnavailableView {
            Label("来源映射失效", systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: 8) {
                Text(mapping.installationCanonicalPath)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                if case .invalid(let reason) = mapping.validity {
                    Text(reason.message)
                }
            }
        } actions: {
            Button("删除映射", role: .destructive) { showsDeleteConfirmation = true }
        }
        .alert("确认删除来源映射？", isPresented: $showsDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除映射", role: .destructive) {
                Task { await deleteMapping() }
            }
        } message: {
            Text("只删除映射记录。不会修改 Skill Installation、Skill Source 或 Git 工作树。")
        }
    }
}

// MARK: - 欢迎引导

private struct WelcomePanel: View {
    let addProjectScanRoot: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("欢迎使用 Pagugu", systemImage: "shippingbox")
        } description: {
            Text("Pagugu 自动发现三个 Personal Skill Root 下的 Skill。\n从左侧目录选择一个 Skill 查看详情，或添加 Project Scan Root 扩展扫描范围。")
        } actions: {
            Button("添加 Project Scan Root", systemImage: "folder.badge.plus") {
                addProjectScanRoot()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - 最近活动（ADR-0007 §7 三语义面：摘要列表、单条详情、清空动作）
// 历史快照标注「当时记录」，与当前实时状态明确区分；历史永不覆盖或参与当前状态呈现。
// 失败详情不提供原始 stderr、不生成/复制终端命令、不提供一键重试，只导航到相关 Skill。

private struct RecentActivitySheet: View {
    @Environment(\.dismiss) private var dismiss

    let history: AuditHistoryProjection
    let clear: () async -> Void
    let openSkill: (String, String) -> Bool
    @State private var selectedItemID: AuditActivityItem.ID?
    @State private var showsClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近活动")
                    .font(.title2.bold())
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            if history.isUnavailable {
                ContentUnavailableView(
                    AuditHistoryProjection.unavailableMessage,
                    systemImage: "exclamationmark.triangle",
                    description: Text("审计历史已损坏并丢弃重建。这不会影响任何功能；此后的动作会重新记录。")
                )
            } else if history.items.isEmpty {
                ContentUnavailableView(
                    "暂无记录",
                    systemImage: "clock",
                    description: Text("检查、更新与来源映射维护会记录在这里。")
                )
            } else {
                List(history.items, selection: $selectedItemID) { item in
                    AuditActivityRow(item: item)
                        .tag(item.id)
                }

                if let item = history.items.first(where: { $0.id == selectedItemID }) {
                    AuditRecordDetailView(item: item, openSkill: openSkill)
                }
            }

            HStack {
                Text("清空只删除历史记录，不影响 Skill、Registry 与 Git 仓库。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("清空历史", systemImage: "trash", role: .destructive) {
                    showsClearConfirmation = true
                }
                .disabled(history.items.isEmpty && !history.isUnavailable)
            }
        }
        .padding(20)
        .frame(minWidth: 660, minHeight: 480)
        .alert("确认清空审计历史？", isPresented: $showsClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空历史", role: .destructive) {
                Task { await clear() }
            }
        } message: {
            Text("将删除全部审计历史记录，且无法恢复。不会修改 Registry、Skill Source、Skill Installation 或 Git 工作树。")
        }
    }
}

private struct AuditActivityRow: View {
    let item: AuditActivityItem

    var body: some View {
        HStack(spacing: 8) {
            Text(item.title)
                .font(.callout)
            if let identity = item.skillIdentity {
                Text(identity.repositoryRelativePath.isEmpty
                     ? identity.sourceKey
                     : "\(identity.sourceKey)/\(identity.repositoryRelativePath)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(item.outcomeDisplayName)
                .font(.caption)
                .foregroundStyle(outcomeColor)
            Text(item.recordedAt.formatted(date: .abbreviated, time: .standard))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var outcomeColor: Color {
        switch item.outcome {
        case .interruptedUnknown: return .orange
        case .record(let outcome):
            switch outcome {
            case .success, .complete, .created: return .green
            case .partial, .cancelled: return .orange
            case .failed, .deleted: return .red
            }
        }
    }
}

private struct AuditRecordDetailView: View {
    let item: AuditActivityItem
    let openSkill: (String, String) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("当时记录：以下为该动作发生时的历史快照，不代表当前实时状态。",
                  systemImage: "clock.arrow.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent("动作") { detailText(item.title) }
            LabeledContent("时间") {
                detailText(item.recordedAt.formatted(date: .abbreviated, time: .standard))
            }
            LabeledContent("结果") { detailText(item.outcomeDisplayName) }

            if let scope = item.record.checkRunScope {
                LabeledContent("检查范围") {
                    detailText("应检查 \(scope.checkableCount) · 成功 \(scope.succeededCount) · 失败 \(scope.failedCount) · 不适用 \(scope.skippedCount)")
                }
            }

            if let path = item.record.installationCanonicalPath {
                LabeledContent("Installation") { detailText(path) }
            }
            if let target = item.record.target {
                LabeledContent("映射目标") {
                    detailText("\(target.skillSourceKey) · \(target.repositoryRelativePath)")
                }
            }

            if let plan = item.record.updateRunPlan {
                LabeledContent("Skill") {
                    detailText("\(plan.skillIdentity.skillSourceKey) · \(plan.skillIdentity.repositoryRelativePath)")
                }
                LabeledContent("目标检出") { detailText(plan.checkoutCanonicalPath) }
                LabeledContent("分支 / upstream") {
                    detailText("\(plan.branchName) / \(plan.upstreamRefName)")
                }
                LabeledContent("当前 HEAD") { detailText(plan.currentHeadSHA) }
                LabeledContent("目标 SHA") { detailText(plan.targetSHA) }
                LabeledContent("behind") { detailText(String(plan.behindCount)) }
                if plan.affectedSkills.count > 1 {
                    LabeledContent("影响范围") {
                        detailText("同一仓库的 \(plan.affectedSkills.count) 个 Skill 一起前进：" +
                            plan.affectedSkills.map(\.repositoryRelativePath).joined(separator: "、"))
                    }
                }
            } else if let target = item.record.updateRunTarget {
                LabeledContent("Skill") {
                    detailText("\(target.skillIdentity.skillSourceKey) · \(target.skillIdentity.repositoryRelativePath)")
                }
                LabeledContent("目标检出") { detailText(target.checkoutCanonicalPath) }
                LabeledContent("分支 / upstream") {
                    detailText("\(target.branchName) / \(target.upstreamRefName)")
                }
            }

            if let reasonCode = item.failureReasonCode,
               let reason = UpdateRunFailureReason(rawValue: reasonCode) {
                LabeledContent("原因") { detailText(reason.displayName) }
                Text(reason.recoveryDirection)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if item.action == .updateRun, let identity = item.skillIdentity {
                Button("查看相关 Skill") {
                    _ = openSkill(identity.sourceKey, identity.repositoryRelativePath)
                }
                .font(.callout)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    private func detailText(_ value: String) -> some View {
        Text(value)
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .multilineTextAlignment(.trailing)
    }
}

#Preview {
    ContentView(model: AppModel())
}
