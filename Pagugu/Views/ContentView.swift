import SwiftUI
import UniformTypeIdentifiers

// L3 COORD: Pagugu/Views/ContentView.swift
// POS: 主窗口内容（Variant F 主从结构，#16 落地目录 IA，#20 落地目录状态短语与静默排序，#27 接线 Update Run）。
//      左侧：平铺目录——来源仓库行（可收起/展开子 Skill 行，默认展开，chevron 独立热区）
//      + 无仓库可归行（来源不明）；消费 Skill Read Model 给出的逐态短语与五档顺序；无分组标题、无筛选 UI。
//      右侧：Skill 详情呈现同名共存组徽标与逐宿主诊断、调用面实时档位与 Unsupported 缺口；
//      Claude Code 行提供四档、Codex 行提供三档主张切换；读取失败时禁用档位写入；两者共用分歧解决与逐宿主单槽恢复；
//      Pi 行提供三档切换、单槽恢复、扩展修复入口与 reload 提示；扩展不健康时禁用档位与恢复；
//      Unsupported segment 禁用；Codex 用户级「仅显式」标明会影响全部 Codex Skill；并呈现状态与检出、安装位置、来源标识、
//      SKILL.md 原文只读可选中、更新动作；
//      空选择回欢迎引导。「相关记录」经工具栏「最近活动」承载。
//      检出卡逐检出提供「更新…」intent（仅 update-available 可用，其余禁用并给出原因）；
//      确认页列出 Skill Identity、目标检出、branch/upstream、当前 HEAD → 精确 target SHA、behind 数、
//      影响范围声明与「同一仓库的 N 个 Skill 将一起前进」名单；多 Eligible 检出当次选择不持久化。
//      结果区统一承载运行反馈、调用面失败与 Pi reload 提示，信息/警示分级、可关闭。
//      工具栏提供全量手动检查、扫描范围管理与「最近活动」三语义面（摘要、详情、清空确认；
//      详情标注「当时记录」，失败无 stderr/命令复制/重试，只导航相关 Skill；损坏呈现「历史不可用」）；
//      Registry 故障由全窗口门面接管，重置后呈现 quarantine 备份路径横幅；
//      「退出自行修复」只发 AppModel.requestQuit，不直接 terminate。
//      主窗口根画布、四个 List 与全部 app-owned sheet 消费正式暖米白主题；欢迎引导展示正式 Pagugu Logo。
//      全部视觉常量消费 DesignTokens（repo://Pagugu/Views/DesignTokens.swift），不逐组件手写冲突值。
//      View 只消费 Skill Read Model 与审计投影、只发 AppModel intent，不做 IO。
// TEST: repo://PaguguTests/AppModelTests.swift（投影与 intent smoke）；
//       repo://PaguguTests/AppModelSurfaceTests.swift（调用面事实投影）；
//       repo://PaguguTests/AppModelClaudeConflictTests.swift（Claude 主张、分歧与动作结果）；
//       repo://PaguguTests/AppModelCodexTests.swift（Codex 三档、Unsupported、分歧与动作结果）；
//       repo://PaguguTests/PiExtensionHealthTests.swift（Pi 扩展健康、修复与档位 intent）；
//       repo://PaguguTests/PaguguTests.swift（ContentView 构造、确认页完整 SHA、DesignTokens、受限恢复退出不直接 terminate）。

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
                RegistryRecoveryView(recovery: recovery, quit: { model.requestQuit() }) {
                    await model.resetRegistry(confirmed: true)
                }
            } else if model.registryReady {
                skillBrowser
            } else {
                ProgressView("正在载入 App Registry…")
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .background(DesignTokens.Brand.themeBackground, ignoresSafeAreaEdges: .all)
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
            .background(DesignTokens.Brand.themeBackground)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let progress = model.checkRunProgress {
                    HStack(spacing: DesignTokens.Space.row) {
                        ProgressView().controlSize(.small)
                        Text("检查中 \(progress.completed)/\(progress.total)")
                            .font(DesignTokens.Fonts.caption)
                            .monospacedDigit()
                            .foregroundStyle(DesignTokens.Status.neutral)
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
        .toolbarBackground(DesignTokens.Brand.themeBackground, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
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
                    nameCollision: model.readModel.nameCollision(for: entry.id),
                    invocationSurfaces: model.readModel.invocationSurfaces(for: entry.id),
                    piExtensionHealth: model.piExtensionHealth,
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
                    setExposureLevel: { host, level in
                        _ = await model.setExposureLevel(level, for: entry.id, host: host)
                    },
                    setPiExposureLevel: { level in
                        _ = await model.setPiExposureLevel(level, for: entry.id)
                    },
                    installOrUpdatePiExtension: {
                        _ = await model.installOrUpdatePiExtension()
                    },
                    reapplyClaim: { host in
                        _ = await model.reapplyVisibilityClaim(for: entry.id, host: host)
                    },
                    adoptDiskConfiguration: { host in
                        _ = await model.adoptDiskConfiguration(for: entry.id, host: host)
                    },
                    restoreConfiguration: { host in
                        _ = await model.restoreConfiguration(for: host)
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
                    nameCollision: model.readModel.nameCollision(forUnattributedInstallationID: item.id),
                    invocationSurfaces: model.readModel.invocationSurfaces(
                        forUnattributedInstallationID: item.id
                    ),
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

// MARK: - 结果区（运行结果、恢复信息与调用面动作失败）
// 信息/警示分级、可关闭；同一动作不出现第二处反馈样式。

private struct ResultAreaView: View {
    @ObservedObject var model: AppModel

    private var hasBanner: Bool {
        model.registryResetBackupPath != nil || model.checkRunProgress != nil
            || model.checkRunSummary != nil || model.updateResult != nil
            || model.piReloadRequired
            || model.updateRefreshFailure != nil || model.projectScanRootError != nil
            || model.sourceMappingError != nil || model.visibilityClaimError != nil
    }

    var body: some View {
        if hasBanner {
            VStack(spacing: DesignTokens.Space.row) {
                banners
            }
            .padding(.horizontal, DesignTokens.Space.cardPadding)
            .padding(.vertical, DesignTokens.Space.block)
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    @ViewBuilder
    private var banners: some View {
            if let backupPath = model.registryResetBackupPath {
                ResultBanner(
                    level: .success,
                    icon: "checkmark.circle",
                    text: "Registry 已重置为空。原文件备份在：\(backupPath)",
                    onDismiss: { model.dismissRegistryResetBackupPath() }
                )
            }
            if model.piReloadRequired {
                ResultBanner(
                    level: .warning,
                    icon: "arrow.clockwise",
                    text: "Pi 配置已更新。请在 Pi 中运行 /reload 或重启 Pi 后生效。",
                    onDismiss: { model.dismissPiReloadReminder() }
                )
            }
            if let progress = model.checkRunProgress {
                ResultBanner(
                    level: .running,
                    icon: "arrow.triangle.2.circlepath",
                    text: "检查中 \(progress.completed)/\(progress.total)",
                    onDismiss: nil
                )
            } else if let summary = model.checkRunSummary {
                ResultBanner(
                    level: summary.outcome == .complete ? .success
                        : summary.outcome == .partial ? .warning : .failure,
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
            if let error = model.visibilityClaimError {
                ResultBanner(
                    level: .failure,
                    icon: "xmark.circle",
                    text: "调用面操作失败：\(error.reason)",
                    onDismiss: { model.clearVisibilityClaimError() }
                )
            }
    }

    @ViewBuilder
    private func updateResultBanner(_ result: UpdateResult) -> some View {
        switch result {
        case .success(_, let targetSHA):
            ResultBanner(
                level: .success,
                icon: "checkmark.circle",
                text: "更新成功。已 fast-forward 到目标提交（\(String(targetSHA.prefix(7)))）。",
                onDismiss: { model.dismissUpdateResult() }
            )
        case .upToDate:
            ResultBanner(
                level: .success,
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
                level: .failure,
                icon: "xmark.circle",
                text: "更新失败：\(failure.reason.displayName)。\(failure.recoveryDirection)",
                onDismiss: { model.dismissUpdateResult() }
            )
        }
    }
}

private struct ResultBanner: View {
    /// 横幅语气分级：成功 / 进行中 / 警示 / 失败；颜色是状态提示之一，图标与文案为并存的静态提示。
    enum Level {
        case success
        case running
        case warning
        case failure
    }

    let level: Level
    let icon: String
    let text: String
    let onDismiss: (() -> Void)?

    private var color: Color {
        switch level {
        case .success: return DesignTokens.Status.ok
        case .running: return DesignTokens.Status.running
        case .warning: return DesignTokens.Status.warning
        case .failure: return DesignTokens.Status.error
        }
    }

    var body: some View {
        HStack(spacing: DesignTokens.Space.block) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(DesignTokens.Fonts.rowTitle)
                // 横幅文案含恢复指引，必须完整可读，不截断
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let onDismiss {
                Button("关闭", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.pressFeedback)
                    .frame(
                        width: DesignTokens.Size.bannerDismissHotspot,
                        height: DesignTokens.Size.bannerDismissHotspot
                    )
                    .contentShape(Rectangle())
            }
        }
        .padding(DesignTokens.Space.cardPadding)
        .background(
            DesignTokens.Surface.bannerTint(color),
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .strokeBorder(DesignTokens.Surface.bannerStroke(color), lineWidth: 1)
        }
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
        VStack(alignment: .leading, spacing: DesignTokens.Space.section) {
            HStack {
                Text("更新 \(skill.displayName)")
                    .font(DesignTokens.Fonts.panelTitle)
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            if eligibleCheckoutPaths.count > 1 {
                Text("该来源有 \(eligibleCheckoutPaths.count) 个可更新检出。当次选择一个，不持久化。")
                    .font(DesignTokens.Fonts.rowTitle)
                    .foregroundStyle(DesignTokens.Status.neutral)
                Picker("目标检出", selection: $selectedCheckoutPath) {
                    ForEach(eligibleCheckoutPaths, id: \.self) { path in
                        Text(path).tag(Optional(path))
                    }
                }
                .pickerStyle(.radioGroup)
            } else {
                Text("目标检出：\(eligibleCheckoutPaths.first ?? "Unknown")")
                    .font(DesignTokens.Fonts.evidenceBody)
                    .foregroundStyle(DesignTokens.Status.neutral)
            }

            Text("确认后 Pagugu 会先 fetch 并重查该检出，再给出精确计划。")
                .font(DesignTokens.Fonts.caption)
                .foregroundStyle(DesignTokens.Status.neutral)

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
                        HStack(spacing: DesignTokens.Space.row) {
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
        .padding(DesignTokens.Space.sheetPadding)
        .frame(minWidth: 560, minHeight: 240)
        .background(DesignTokens.Brand.themeBackground)
        .onAppear {
            selectedCheckoutPath = preselectedCheckoutPath ?? eligibleCheckoutPaths.first
        }
    }
}

// 确认页「当前 HEAD → 目标」必须展示完整 Git 对象名（40/64 位），不得截成 7 位前缀。
// TEST: repo://PaguguTests/PaguguTests.swift::testPreparedUpdateConfirmationShowsFullSHAAndRejectsSevenCharPrefix
func updateConfirmationHeadToTargetText(currentHeadSHA: String, targetSHA: String) -> String {
    "\(currentHeadSHA) → \(targetSHA)"
}

// MARK: - 冻结计划确认 sheet（S5：列出 Skill Identity、目标检出、branch/upstream、HEAD→SHA、behind、影响范围）

private struct PreparedUpdateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    let plan: UpdatePlan
    @State private var isExecuting = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.section) {
            HStack {
                Text("确认更新")
                    .font(DesignTokens.Fonts.panelTitle)
                Spacer()
                Button("关闭") { Task { await model.cancelUpdate(); dismiss() } }
                    .keyboardShortcut(.cancelAction)
            }

            GroupBox("计划") {
                VStack(alignment: .leading, spacing: DesignTokens.Space.row) {
                    LabeledContent("Skill") {
                        Text("\(plan.skillIdentity.sourceKey.registryValue) · \(plan.skillIdentity.repositoryRelativePath.isEmpty ? "（仓库根目录）" : plan.skillIdentity.repositoryRelativePath)")
                            .font(DesignTokens.Fonts.evidence)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("目标检出") {
                        Text(plan.checkoutCanonicalPath)
                            .font(DesignTokens.Fonts.evidence)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("分支 / upstream") {
                        Text("\(plan.branchName) / \(plan.upstreamRefName)")
                            .font(DesignTokens.Fonts.evidence)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("当前 HEAD → 目标") {
                        Text(updateConfirmationHeadToTargetText(
                            currentHeadSHA: plan.currentHeadSHA,
                            targetSHA: plan.targetSHA
                        ))
                            .font(DesignTokens.Fonts.evidence)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("落后") {
                        Text("\(plan.behindCount) 个提交")
                            .font(DesignTokens.Fonts.caption)
                    }
                }
            }

            Text(plan.impactStatement)
                .font(DesignTokens.Fonts.rowTitle)
                .foregroundStyle(DesignTokens.Status.neutral)

            if plan.affectedSkills.count > 1 {
                GroupBox("影响范围") {
                    VStack(alignment: .leading, spacing: DesignTokens.Space.inline) {
                        Text("同一仓库的 \(plan.affectedSkills.count) 个 Skill 将一起前进：")
                            .font(DesignTokens.Fonts.caption)
                        ForEach(plan.affectedSkills, id: \.identity.repositoryRelativePath) { affected in
                            Text("\(affected.displayName)（\(affected.identity.repositoryRelativePath.isEmpty ? "仓库根目录" : affected.identity.repositoryRelativePath)）")
                                .font(DesignTokens.Fonts.evidence)
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
                        HStack(spacing: DesignTokens.Space.row) {
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
        .padding(DesignTokens.Space.sheetPadding)
        .frame(minWidth: 620, minHeight: 360)
        .background(DesignTokens.Brand.themeBackground)
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
        VStack(alignment: .leading, spacing: DesignTokens.Space.section) {
            HStack {
                Text("扫描范围")
                    .font(DesignTokens.Fonts.panelTitle)
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
                    HStack(spacing: DesignTokens.Space.block) {
                        Image(systemName: root.isAvailable ? "folder" : "folder.badge.questionmark")
                            .foregroundStyle(root.isAvailable ? DesignTokens.Status.neutral : DesignTokens.Status.warning)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: DesignTokens.Space.tight) {
                            Text(root.asFoundPath)
                                .font(DesignTokens.Fonts.evidenceBody)
                                .textSelection(.enabled)
                            if let reason = root.unavailableReason {
                                Text("不可用：\(reason)。路径恢复后会自动复活。")
                                    .font(DesignTokens.Fonts.caption)
                                    .foregroundStyle(DesignTokens.Status.warning)
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
                .scrollContentBackground(.hidden)
                .background(DesignTokens.Brand.themeBackground)
            }

            HStack {
                Text("删除只移除主张记录，不会触碰目录、Skill Source 或 Git 工作树。")
                    .font(DesignTokens.Fonts.caption)
                    .foregroundStyle(DesignTokens.Status.neutral)
                Spacer()
                Button("添加 Project Scan Root", systemImage: "plus") {
                    add()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(DesignTokens.Space.sheetPadding)
        .frame(minWidth: 660, minHeight: 420)
        .background(DesignTokens.Brand.themeBackground)
    }
}

// MARK: - Registry 受限恢复

private struct RegistryRecoveryView: View {
    let recovery: RegistryRecovery
    let quit: () -> Void
    let reset: () async -> Void
    @State private var showsResetConfirmation = false

    var body: some View {
        ContentUnavailableView {
            Label("App Registry 需要恢复", systemImage: "exclamationmark.lock")
        } description: {
            VStack(spacing: DesignTokens.Space.block) {
                Text(description)
                Text(recovery.evidenceURL.path)
                    .font(DesignTokens.Fonts.evidenceBody)
                    .textSelection(.enabled)
            }
        } actions: {
            Button("重置为空 Registry", role: .destructive) {
                showsResetConfirmation = true
            }
            Button("退出自行修复") {
                quit()
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
                    description: Text("四个 Personal Skill Root 与已保存的 Project Scan Root 下没有可解析的 Skill。")
                )
            } else {
                List(selection: $selection) {
                    if !readModel.issues.isEmpty {
                        Section {
                            ForEach(readModel.issues, id: \.path) { issue in
                                VStack(alignment: .leading, spacing: DesignTokens.Space.tight) {
                                    Label("扫描问题", systemImage: "exclamationmark.triangle")
                                        .font(DesignTokens.Fonts.caption)
                                        .foregroundStyle(DesignTokens.Status.warning)
                                    Text(issue.path)
                                        .font(DesignTokens.Fonts.captionSmall)
                                        .foregroundStyle(DesignTokens.Status.neutral)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text(issue.reason)
                                        .font(DesignTokens.Fonts.captionSmall)
                                        .foregroundStyle(DesignTokens.Status.neutral)
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
                .scrollContentBackground(.hidden)
                .background(DesignTokens.Brand.themeBackground)
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
        VStack(alignment: .leading, spacing: DesignTokens.Space.tight) {
            HStack(spacing: DesignTokens.Space.row) {
                Button(action: onToggle) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(DesignTokens.Fonts.disclosure)
                        .foregroundStyle(DesignTokens.Status.neutral)
                        .frame(
                            width: DesignTokens.Size.disclosureHotspot,
                            height: DesignTokens.Size.disclosureHotspot
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressFeedback)
                .accessibilityLabel(isCollapsed ? "展开" : "收起")

                Text(source.displayName)
                    .font(DesignTokens.Fonts.heading)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                HostLogoSlots(hosts: source.hosts)
            }
            if let statusPhrase {
                Text(statusPhrase)
                    .font(DesignTokens.Fonts.caption)
                    .foregroundStyle(DesignTokens.Status.neutral)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, DesignTokens.Size.childIndent)
            }
            Text(source.id.displayString)
                .font(DesignTokens.Fonts.captionSmall)
                .foregroundStyle(DesignTokens.Status.neutral)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, DesignTokens.Size.childIndent)
        }
        .padding(.vertical, DesignTokens.Space.rowVertical)
    }
}

// MARK: - 仓库下的子 Skill 行

private struct SkillRow: View {
    let entry: SkillDirectoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.tight) {
            HStack {
                Text(entry.displayName)
                    .font(DesignTokens.Fonts.rowTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                HostLogoSlots(hosts: entry.hosts)
            }
            if entry.id.repositoryRelativePath != entry.displayName {
                Text(entry.id.repositoryRelativePath.isEmpty ? "（仓库根目录）" : entry.id.repositoryRelativePath)
                    .font(DesignTokens.Fonts.captionSmall)
                    .foregroundStyle(DesignTokens.Status.neutral)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.leading, DesignTokens.Size.childIndent)
        .padding(.vertical, DesignTokens.Space.rowVertical)
    }
}

// MARK: - 无仓库可归行（来源不明）

private struct UnattributedInstallationRow: View {
    let item: UnattributedInstallationItem
    let mapSource: (SkillInstallation, String) -> Void
    let deleteMapping: (String) async -> Void
    @State private var mappingPathToDelete: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.tight) {
            HStack(spacing: DesignTokens.Space.row) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(DesignTokens.Fonts.caption)
                    .foregroundStyle(DesignTokens.Status.warning)
                Text(item.displayName)
                    .font(DesignTokens.Fonts.rowTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("来源不明")
                    .font(DesignTokens.Fonts.caption)
                    .foregroundStyle(DesignTokens.Status.warning)
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
                .font(DesignTokens.Fonts.captionSmall)
                .foregroundStyle(DesignTokens.Status.neutral)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, DesignTokens.Space.rowVertical)
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
        VStack(alignment: .leading, spacing: DesignTokens.Space.inline) {
            Label("来源映射失效", systemImage: "exclamationmark.triangle.fill")
                .font(DesignTokens.Fonts.caption)
                .foregroundStyle(DesignTokens.Status.warning)
            Text(mapping.installationCanonicalPath)
                .font(DesignTokens.Fonts.evidence)
                .lineLimit(1)
                .truncationMode(.middle)
            Button("删除映射", role: .destructive) { showsDeleteConfirmation = true }
                .font(DesignTokens.Fonts.caption)
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
        HStack(spacing: DesignTokens.Space.inline) {
            ForEach(AgentHost.allCases, id: \.self) { host in
                HostLogoDot(host: host, isActive: hosts.contains(host))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        AgentHost.allCases
            .map { host in
                host.displayName + (hosts.contains(host) ? "已安装" : "未安装")
            }
            .joined(separator: "，")
    }
}

private struct HostLogoDot: View {
    let host: AgentHost
    let isActive: Bool

    // 占位槽位：已安装 = 实心，未安装 = 描边；形状与填充双重静态提示，不依赖单一透明度，明暗两态可辨。
    var body: some View {
        Circle()
            .fill(isActive ? Color.primary : .clear)
            .overlay {
                if !isActive {
                    Circle()
                        .strokeBorder(DesignTokens.Status.neutral, lineWidth: 1)
                }
            }
            .frame(width: DesignTokens.Size.hostLogoDot, height: DesignTokens.Size.hostLogoDot)
            .help(host.displayName + (isActive ? "（已安装）" : "（未安装）"))
    }
}

// MARK: - 右侧详情：来源仓库行

private struct SkillSourcePanel: View {
    let source: SkillSourceItem
    let onSelectSkill: (SkillIdentity) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Space.section) {
                VStack(alignment: .leading, spacing: DesignTokens.Space.block) {
                    Text(source.displayName)
                        .font(DesignTokens.Fonts.panelTitle)
                    HostLogoSlots(hosts: source.hosts)
                }

                VStack(alignment: .leading, spacing: DesignTokens.Space.inline) {
                    Text("包含的 Skill（\(source.skills.count) 个）")
                        .font(DesignTokens.Fonts.heading)
                    ForEach(source.skills) { entry in
                        Button {
                            onSelectSkill(entry.id)
                        } label: {
                            HStack {
                                Text(entry.displayName)
                                    .font(DesignTokens.Fonts.body)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(DesignTokens.Fonts.disclosure)
                                    .foregroundStyle(DesignTokens.Status.neutral)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressFeedback)
                    }
                }

                SourceIdentityBlock(sourceKey: source.id, repositoryRelativePath: nil)

                Spacer()
            }
            .padding(DesignTokens.Space.section)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 右侧详情：Skill（状态与检出、安装位置、来源标识、SKILL.md 原文）

private struct SkillDetailPanel: View {
    let entry: SkillDirectoryEntry
    let nameCollision: NameCollisionReadModel?
    let invocationSurfaces: [HostInvocationSurface]
    let piExtensionHealth: PiExtensionHealth
    let checkouts: [CheckoutCardReadModel]
    let markdown: String?
    let canStartUpdate: Bool
    let updateDisabledReason: String
    let isPreparingUpdate: Bool
    let startUpdate: (String?) -> Void
    let setExposureLevel: (AgentHost, ExposureLevel) async -> Void
    let setPiExposureLevel: (ExposureLevel) async -> Void
    let installOrUpdatePiExtension: () async -> Void
    let reapplyClaim: (AgentHost) async -> Void
    let adoptDiskConfiguration: (AgentHost) async -> Void
    let restoreConfiguration: (AgentHost) async -> Void
    let deleteMapping: (String) async -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Space.section) {
                VStack(alignment: .leading, spacing: DesignTokens.Space.block) {
                    Text(entry.displayName)
                        .font(DesignTokens.Fonts.panelTitle)
                    HostLogoSlots(hosts: entry.hosts)
                }

                if let nameCollision {
                    NameCollisionBlock(collision: nameCollision)
                }

                InvocationSurfaceBlock(
                    surfaces: invocationSurfaces,
                    piExtensionHealth: piExtensionHealth,
                    setExposureLevel: setExposureLevel,
                    setPiExposureLevel: setPiExposureLevel,
                    installOrUpdatePiExtension: installOrUpdatePiExtension,
                    reapplyClaim: reapplyClaim,
                    adoptDiskConfiguration: adoptDiskConfiguration,
                    restoreConfiguration: restoreConfiguration
                )

                CheckoutStatusBlock(
                    checkouts: checkouts,
                    canStartUpdate: canStartUpdate,
                    updateDisabledReason: updateDisabledReason,
                    isPreparingUpdate: isPreparingUpdate,
                    startUpdate: startUpdate
                )

                InstallationsBlock(
                    installations: entry.installations,
                    deleteMapping: deleteMapping
                )

                SourceIdentityBlock(
                    sourceKey: entry.id.sourceKey,
                    repositoryRelativePath: entry.id.repositoryRelativePath
                )

                MarkdownSourceBlock(markdown: markdown)

                UpdateActionBlock(
                    checkouts: checkouts,
                    canStartUpdate: canStartUpdate,
                    updateDisabledReason: updateDisabledReason,
                    isPreparingUpdate: isPreparingUpdate,
                    startUpdate: startUpdate
                )

                Spacer()
            }
            .padding(DesignTokens.Space.section)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 详情块：同名共存组（只读；不参与身份、归因或更新资格）

private struct NameCollisionBlock: View {
    let collision: NameCollisionReadModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.block) {
            HStack(spacing: DesignTokens.Space.inline) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .accessibilityHidden(true)
                Text(collision.badgeText)
            }
            .font(DesignTokens.Fonts.caption)
            .foregroundStyle(DesignTokens.Status.warning)
            .padding(.horizontal, DesignTokens.Space.block)
            .padding(.vertical, DesignTokens.Space.inline)
            .background(
                DesignTokens.Surface.bannerTint(DesignTokens.Status.warning),
                in: Capsule()
            )

            ForEach(collision.diagnosticTexts, id: \.self) { diagnostic in
                Text(diagnostic)
                    .font(DesignTokens.Fonts.rowTitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 详情块：调用面（实时文件事实 + Claude Code/Codex 显式主张动作）

// 配置读取失败时必须 fail-close。旧主张不能重新开放写入控件。
// TEST: repo://PaguguTests/PaguguTests.swift::testFailedInvocationSurfaceReadDisablesExposureLevelWritesEvenWithClaim
func exposureLevelPickerIsDisabled(
    isApplyingChange: Bool,
    surface: HostInvocationSurface
) -> Bool {
    guard !isApplyingChange else { return true }
    if case .readFailed = surface.state { return true }
    return false
}

// Pi 恢复与档位切换共用扩展健康门。AppModel 在执行点仍会实时重查。
// TEST: repo://PaguguTests/PaguguTests.swift::testPiRestoreControlIsDisabledWhenExtensionCannotWrite
func piRestoreConfigurationIsDisabled(
    isApplyingChange: Bool,
    health: PiExtensionHealth
) -> Bool {
    isApplyingChange || !health.allowsVisibilityWrites
}

private struct InvocationSurfaceBlock: View {
    let surfaces: [HostInvocationSurface]
    let piExtensionHealth: PiExtensionHealth?
    let setExposureLevel: ((AgentHost, ExposureLevel) async -> Void)?
    let setPiExposureLevel: ((ExposureLevel) async -> Void)?
    let installOrUpdatePiExtension: (() async -> Void)?
    let reapplyClaim: ((AgentHost) async -> Void)?
    let adoptDiskConfiguration: ((AgentHost) async -> Void)?
    let restoreConfiguration: ((AgentHost) async -> Void)?
    @State private var isApplyingChange = false
    @State private var isApplyingPiChange = false

    init(
        surfaces: [HostInvocationSurface],
        piExtensionHealth: PiExtensionHealth? = nil,
        setExposureLevel: ((AgentHost, ExposureLevel) async -> Void)? = nil,
        setPiExposureLevel: ((ExposureLevel) async -> Void)? = nil,
        installOrUpdatePiExtension: (() async -> Void)? = nil,
        reapplyClaim: ((AgentHost) async -> Void)? = nil,
        adoptDiskConfiguration: ((AgentHost) async -> Void)? = nil,
        restoreConfiguration: ((AgentHost) async -> Void)? = nil
    ) {
        self.surfaces = surfaces
        self.piExtensionHealth = piExtensionHealth
        self.setExposureLevel = setExposureLevel
        self.setPiExposureLevel = setPiExposureLevel
        self.installOrUpdatePiExtension = installOrUpdatePiExtension
        self.reapplyClaim = reapplyClaim
        self.adoptDiskConfiguration = adoptDiskConfiguration
        self.restoreConfiguration = restoreConfiguration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.block) {
            Text("调用面（Invocation Surface）")
                .font(DesignTokens.Fonts.heading)
            if surfaces.isEmpty {
                Text("未安装到任何 Agent Host。")
                    .font(DesignTokens.Fonts.caption)
                    .foregroundStyle(DesignTokens.Status.neutral)
            }
            ForEach(surfaces) { surface in
                VStack(alignment: .leading, spacing: DesignTokens.Space.row) {
                    HStack {
                        Text(surface.host.displayName)
                            .font(DesignTokens.Fonts.rowTitle)
                        Spacer()
                        Text(stateText(surface.state))
                            .font(DesignTokens.Fonts.rowTitle)
                            .foregroundStyle(stateColor(surface))
                    }
                    if surface.host != .pi, setExposureLevel != nil {
                        hostControls(for: surface)
                    }
                    if surface.host == .codex {
                        Text("“仅显式”写入 Codex 用户级策略，会影响所有 Codex Skill；刷新后各 Skill 按磁盘事实重新呈现。")
                            .font(DesignTokens.Fonts.caption)
                            .foregroundStyle(DesignTokens.Status.neutral)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if surface.host == .pi, setPiExposureLevel != nil,
                       let piExtensionHealth {
                        piControls(for: surface, health: piExtensionHealth)
                    }
                    if !surface.unsupportedLevels.isEmpty {
                        Text("档位缺口：" + surface.unsupportedLevels
                            .map { "\($0.displayName)（Unsupported）" }
                            .joined(separator: "、"))
                            .font(DesignTokens.Fonts.caption)
                            .foregroundStyle(DesignTokens.Status.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(DesignTokens.Space.cardPadding)
                .background(
                    DesignTokens.Surface.card,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                )
            }
        }
    }

    @ViewBuilder
    private func hostControls(for surface: HostInvocationSurface) -> some View {
        Picker(
            "主张档位",
            selection: Binding(
                get: { selectedLevel(for: surface) },
                set: { level in
                    guard let setExposureLevel,
                          !surface.unsupportedLevels.contains(level) else { return }
                    runHostAction { await setExposureLevel(surface.host, level) }
                }
            )
        ) {
            ForEach(ExposureLevel.allCases, id: \.self) { level in
                Text(level.displayName)
                    .tag(level)
                    .disabled(surface.unsupportedLevels.contains(level))
            }
        }
        .pickerStyle(.segmented)
        .disabled(
            exposureLevelPickerIsDisabled(
                isApplyingChange: isApplyingChange,
                surface: surface
            )
        )

        if let claimLevel = surface.claimLevel {
            Text("当前主张：\(claimLevel.displayName)")
                .font(DesignTokens.Fonts.caption)
                .foregroundStyle(DesignTokens.Status.neutral)
        } else {
            Text("尚无主张；当前显示磁盘配置。")
                .font(DesignTokens.Fonts.caption)
                .foregroundStyle(DesignTokens.Status.neutral)
        }

        if surface.hasDivergence {
            VStack(alignment: .leading, spacing: DesignTokens.Space.inline) {
                Label("主张与配置不一致", systemImage: "exclamationmark.triangle.fill")
                    .font(DesignTokens.Fonts.rowTitle)
                    .foregroundStyle(DesignTokens.Status.warning)
                Text("磁盘配置：\(stateText(surface.state))；当前主张：\(surface.claimLevel?.displayName ?? "无")。")
                    .font(DesignTokens.Fonts.caption)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if let reapplyClaim {
                        Button("重新应用主张") {
                            runHostAction { await reapplyClaim(surface.host) }
                        }
                    }
                    if let adoptDiskConfiguration {
                        Button("采用磁盘配置") {
                            runHostAction { await adoptDiskConfiguration(surface.host) }
                        }
                    }
                }
                .disabled(isApplyingChange)
            }
            .padding(DesignTokens.Space.block)
            .background(
                DesignTokens.Surface.bannerTint(DesignTokens.Status.warning),
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.inset)
            )
        }

        if let restoreConfiguration {
            Button("恢复 \(surface.host.displayName) 配置", systemImage: "arrow.uturn.backward") {
                runHostAction { await restoreConfiguration(surface.host) }
            }
            .disabled(isApplyingChange)
            .help("用最近一次 Pagugu 写入前的单槽备份恢复 \(surface.host.displayName) 用户配置。")
        }
    }

    @ViewBuilder
    private func piControls(
        for surface: HostInvocationSurface,
        health: PiExtensionHealth
    ) -> some View {
        if let recoverySuggestion = health.recoverySuggestion {
            VStack(alignment: .leading, spacing: DesignTokens.Space.inline) {
                Label("Pi 扩展需要修复", systemImage: "exclamationmark.triangle.fill")
                    .font(DesignTokens.Fonts.rowTitle)
                    .foregroundStyle(DesignTokens.Status.warning)
                Text(recoverySuggestion)
                    .font(DesignTokens.Fonts.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DesignTokens.Space.block)
            .background(
                DesignTokens.Surface.bannerTint(DesignTokens.Status.warning),
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.inset)
            )
        }

        Picker(
            "Pi 档位",
            selection: Binding(
                get: { currentLevel(for: surface) ?? .fullyExposed },
                set: { level in
                    guard let setPiExposureLevel else { return }
                    runPiAction { await setPiExposureLevel(level) }
                }
            )
        ) {
            ForEach(
                ExposureLevel.allCases.filter { !surface.unsupportedLevels.contains($0) },
                id: \.self
            ) { level in
                Text(level.displayName).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .disabled(
            isApplyingPiChange || !health.allowsVisibilityWrites ||
                currentLevel(for: surface) == nil
        )

        if case .readFailed = surface.state {
            Text("请修复或删除 ~/.pi/agent/pagugu/visibility.json 后重试。")
                .font(DesignTokens.Fonts.caption)
                .foregroundStyle(DesignTokens.Status.warning)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let restoreConfiguration {
            Button("恢复 Pi 配置", systemImage: "arrow.uturn.backward") {
                runPiAction { await restoreConfiguration(.pi) }
            }
            .disabled(piRestoreConfigurationIsDisabled(
                isApplyingChange: isApplyingPiChange,
                health: health
            ))
            .help("用最近一次 Pagugu 写入前的单槽备份恢复 Pi 可见性配置。")
        }

        Text("切换后请在 Pi 中运行 /reload 或重启 Pi。")
            .font(DesignTokens.Fonts.caption)
            .foregroundStyle(DesignTokens.Status.neutral)

        if let installOrUpdatePiExtension {
            Button("安装/更新 Pi 扩展", systemImage: "shippingbox.and.arrow.backward") {
                runPiAction { await installOrUpdatePiExtension() }
            }
            .disabled(isApplyingPiChange)
            .help("幂等安装或升级 ~/.pi/agent/extensions/pagugu-visibility/index.ts。")
        }
    }

    private func selectedLevel(for surface: HostInvocationSurface) -> ExposureLevel {
        surface.claimLevel ?? currentLevel(for: surface) ?? .fullyExposed
    }

    private func currentLevel(for surface: HostInvocationSurface) -> ExposureLevel? {
        switch surface.state {
        case .level(let level), .unsupported(let level): return level
        case .readFailed: return nil
        }
    }

    private func runHostAction(_ action: @escaping () async -> Void) {
        isApplyingChange = true
        Task {
            await action()
            isApplyingChange = false
        }
    }

    private func runPiAction(_ action: @escaping () async -> Void) {
        isApplyingPiChange = true
        Task {
            await action()
            isApplyingPiChange = false
        }
    }

    private func stateText(_ state: HostInvocationSurfaceState) -> String {
        switch state {
        case .level(let level): return level.displayName
        case .unsupported(let level): return "\(level.displayName)（Unsupported）"
        case .readFailed: return "读取失败"
        }
    }

    private func stateColor(_ surface: HostInvocationSurface) -> Color {
        if surface.hasDivergence { return DesignTokens.Status.warning }
        switch surface.state {
        case .level: return DesignTokens.Status.neutral
        case .unsupported, .readFailed: return DesignTokens.Status.warning
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
        VStack(alignment: .leading, spacing: DesignTokens.Space.block) {
            Text("状态与检出")
                .font(DesignTokens.Fonts.heading)
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
        VStack(alignment: .leading, spacing: DesignTokens.Space.block) {
            Text("更新动作")
                .font(DesignTokens.Fonts.heading)
            if eligibleCheckouts.isEmpty {
                Text("当前没有可更新的检出。")
                    .font(DesignTokens.Fonts.caption)
                    .foregroundStyle(DesignTokens.Status.neutral)
            } else {
                Text(eligibleCheckouts.count == 1
                     ? "1 个检出可更新。"
                     : "\(eligibleCheckouts.count) 个检出可更新；确认时当次选择一个，不持久化。")
                    .font(DesignTokens.Fonts.caption)
                    .foregroundStyle(DesignTokens.Status.neutral)
                Button {
                    startUpdate(nil)
                } label: {
                    if isPreparingUpdate {
                        HStack(spacing: DesignTokens.Space.row) {
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
        VStack(alignment: .leading, spacing: DesignTokens.Space.row) {
            HStack {
                // 状态名 + 语义状态色（静态提示之一），rawValue 保持无色以便区分
                Text(checkout.state.displayName)
                    .font(DesignTokens.Fonts.heading)
                    .foregroundStyle(DesignTokens.statusColor(for: checkout.state))
                Text(checkout.state.rawValue)
                    .font(DesignTokens.Fonts.evidence)
                    .foregroundStyle(DesignTokens.Status.neutral)
                Spacer()
                if isEligible {
                    Button {
                        startUpdate?(checkout.id)
                    } label: {
                        if isPreparingUpdate {
                            HStack(spacing: DesignTokens.Space.inline) {
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
                .font(DesignTokens.Fonts.caption)
                .foregroundStyle(DesignTokens.Status.neutral)
            if checkout.isChecking {
                Label("检查中", systemImage: "arrow.triangle.2.circlepath")
                    .font(DesignTokens.Fonts.caption)
                    .foregroundStyle(DesignTokens.Status.running)
            }
            if let outcome = checkout.checkOutcome {
                checkOutcome(outcome)
            }
            if checkout.observation?.result == .failure, checkout.checkOutcome == nil {
                Text(CheckRunFailure.fetchFailed.message)
                    .font(DesignTokens.Fonts.caption)
                    .foregroundStyle(DesignTokens.Status.error)
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
        .padding(DesignTokens.Space.cardPadding)
        .background(
            DesignTokens.Surface.card,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
        )
    }

    @ViewBuilder
    private func checkOutcome(_ outcome: CheckRunItemOutcome) -> some View {
        switch outcome {
        case .success:
            EmptyView()
        case .notApplicable:
            Text("本次检查：不适用")
                .font(DesignTokens.Fonts.caption)
                .foregroundStyle(DesignTokens.Status.neutral)
        case .failed(let reason):
            Text(reason.message)
                .font(DesignTokens.Fonts.caption)
                .foregroundStyle(DesignTokens.Status.error)
        case .discarded:
            Text("检查期间检出身份已变化。本次观察已丢弃；请重新检查。")
                .font(DesignTokens.Fonts.caption)
                .foregroundStyle(DesignTokens.Status.warning)
        }
    }

    private func fact(_ name: String, _ value: String) -> some View {
        LabeledContent(name) {
            Text(value)
                .font(DesignTokens.Fonts.evidence)
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
    let nameCollision: NameCollisionReadModel?
    let invocationSurfaces: [HostInvocationSurface]
    let markdown: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Space.section) {
                VStack(alignment: .leading, spacing: DesignTokens.Space.block) {
                    Text(item.displayName)
                        .font(DesignTokens.Fonts.panelTitle)
                    HostLogoSlots(hosts: item.hosts)
                }

                if let nameCollision {
                    NameCollisionBlock(collision: nameCollision)
                }

                InvocationSurfaceBlock(surfaces: invocationSurfaces)

                InstallationsBlock(installations: item.installations)

                VStack(alignment: .leading, spacing: DesignTokens.Space.inline) {
                    Text("来源标识")
                        .font(DesignTokens.Fonts.heading)
                    Text("来源不明")
                        .font(DesignTokens.Fonts.body)
                        .foregroundStyle(DesignTokens.Status.warning)
                    Text("复制投影未关联任何已发现 Skill Source；不参与更新。")
                        .font(DesignTokens.Fonts.caption)
                        .foregroundStyle(DesignTokens.Status.neutral)
                    if item.installations.count > 1 {
                        Text("内容完全一致的 \(item.installations.count) 个安装位置已聚合为一个条目（仍来源不明、不可更新）。")
                            .font(DesignTokens.Fonts.caption)
                            .foregroundStyle(DesignTokens.Status.neutral)
                    }
                }

                MarkdownSourceBlock(markdown: markdown)

                Spacer()
            }
            .padding(DesignTokens.Space.section)
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
        VStack(alignment: .leading, spacing: DesignTokens.Space.block) {
            Text("安装位置")
                .font(DesignTokens.Fonts.heading)
            if installations.isEmpty {
                Text("未安装到任何 Agent Host（仅在扫描范围内发现）。")
                    .font(DesignTokens.Fonts.caption)
                    .foregroundStyle(DesignTokens.Status.neutral)
            }
            ForEach(installations, id: \.asFoundPath) { installation in
                VStack(alignment: .leading, spacing: DesignTokens.Space.tight) {
                    Text(installation.asFoundPath)
                        .font(DesignTokens.Fonts.evidenceBody)
                        .textSelection(.enabled)
                    // 软链接安装的解析目标（归因证据）；as-found 即 canonical 时不重复显示
                    if installation.canonicalPath != (installation.asFoundPath as NSString).expandingTildeInPath {
                        Text("→ \(installation.canonicalPath)")
                            .font(DesignTokens.Fonts.evidence)
                            .foregroundStyle(DesignTokens.Status.neutral)
                            .textSelection(.enabled)
                    }
                    HStack(spacing: DesignTokens.Space.row) {
                        HostLogoSlots(hosts: installation.hosts)
                        Text(installation.projectionType.displayName + attributionNote(for: installation))
                    }
                    .font(DesignTokens.Fonts.caption)
                    .foregroundStyle(DesignTokens.Status.neutral)
                    if let mapping = installation.sourceMapping {
                        switch mapping.validity {
                        case .invalid(let reason):
                            Text("映射失效：\(reason.message)")
                                .font(DesignTokens.Fonts.caption)
                                .foregroundStyle(DesignTokens.Status.warning)
                        case .unverified:
                            Text("扫描不完整，暂不重验证该映射。")
                                .font(DesignTokens.Fonts.caption)
                                .foregroundStyle(DesignTokens.Status.neutral)
                        case .valid:
                            EmptyView()
                        }
                    }
                    if installation.isManuallyMapped, deleteMapping != nil {
                        Button("删除来源映射", role: .destructive) {
                            mappingPathToDelete = installation.canonicalPath
                        }
                        .font(DesignTokens.Fonts.caption)
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
        VStack(alignment: .leading, spacing: DesignTokens.Space.inline) {
            Text("来源标识")
                .font(DesignTokens.Fonts.heading)
            LabeledContent("Skill Source Key") {
                Text(sourceKey.displayString)
                    .font(DesignTokens.Fonts.evidenceBody)
                    .textSelection(.enabled)
            }
            if let repositoryRelativePath {
                LabeledContent("仓内相对路径") {
                    Text(repositoryRelativePath.isEmpty ? "（仓库根目录）" : repositoryRelativePath)
                        .font(DesignTokens.Fonts.evidenceBody)
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
        VStack(alignment: .leading, spacing: DesignTokens.Space.inline) {
            Text("SKILL.md 原文（只读）")
                .font(DesignTokens.Fonts.heading)
            if let markdown {
                Text(markdown)
                    .font(DesignTokens.Fonts.markdown)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignTokens.Space.block)
                    .background(
                        DesignTokens.Surface.inset,
                        in: RoundedRectangle(cornerRadius: DesignTokens.Radius.inset)
                    )
            } else {
                Text("无法读取 SKILL.md。")
                    .font(DesignTokens.Fonts.rowTitle)
                    .foregroundStyle(DesignTokens.Status.neutral)
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
        VStack(alignment: .leading, spacing: DesignTokens.Space.block) {
            HStack {
                VStack(alignment: .leading, spacing: DesignTokens.Space.tight) {
                    Text("指定来源")
                        .font(DesignTokens.Fonts.panelTitle)
                    Text(installation.asFoundPath)
                        .font(DesignTokens.Fonts.evidence)
                        .foregroundStyle(DesignTokens.Status.neutral)
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
                                    VStack(alignment: .leading, spacing: DesignTokens.Space.tight) {
                                        Text(target.displayName)
                                        Text(target.id.repositoryRelativePath.isEmpty
                                             ? "（仓库根目录）"
                                             : target.id.repositoryRelativePath)
                                            .font(DesignTokens.Fonts.evidence)
                                            .foregroundStyle(DesignTokens.Status.neutral)
                                        if target.displayName != displayName {
                                            Label(
                                                "frontmatter name 不同；名称不参与身份，不阻断指定。",
                                                systemImage: "exclamationmark.triangle"
                                            )
                                            .font(DesignTokens.Fonts.caption)
                                            .foregroundStyle(DesignTokens.Status.warning)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.pressFeedback)
                                .accessibilityLabel("指定来源为 \(target.displayName)")
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(DesignTokens.Brand.themeBackground)
                .searchable(text: $query, prompt: "筛选 Skill 或来源")
            }
        }
        .padding(DesignTokens.Space.sheetPadding)
        .frame(minWidth: 680, minHeight: 480)
        .background(DesignTokens.Brand.themeBackground)
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
            VStack(spacing: DesignTokens.Space.block) {
                Text(mapping.installationCanonicalPath)
                    .font(DesignTokens.Fonts.evidenceBody)
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
            VStack(spacing: DesignTokens.Space.block) {
                Image("PaguguLogoRounded")
                    .resizable()
                    .scaledToFit()
                    .frame(width: DesignTokens.Size.welcomeLogo, height: DesignTokens.Size.welcomeLogo)
                    .accessibilityHidden(true)
                Text("欢迎使用 Pagugu")
                    .font(DesignTokens.Fonts.heading)
            }
        } description: {
            Text("Pagugu 自动发现四个 Personal Skill Root 下的 Skill。\n从左侧目录选择一个 Skill 查看详情，或添加 Project Scan Root 扩展扫描范围。")
        } actions: {
            Button("添加 Project Scan Root", systemImage: "folder.badge.plus") {
                addProjectScanRoot()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Brand.themeBackground)
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
        VStack(alignment: .leading, spacing: DesignTokens.Space.block) {
            HStack {
                Text("最近活动")
                    .font(DesignTokens.Fonts.panelTitle)
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
                .scrollContentBackground(.hidden)
                .background(DesignTokens.Brand.themeBackground)

                if let item = history.items.first(where: { $0.id == selectedItemID }) {
                    AuditRecordDetailView(item: item, openSkill: openSkill)
                }
            }

            HStack {
                Text("清空只删除历史记录，不影响 Skill、Registry 与 Git 仓库。")
                    .font(DesignTokens.Fonts.caption)
                    .foregroundStyle(DesignTokens.Status.neutral)
                Spacer()
                Button("清空历史", systemImage: "trash", role: .destructive) {
                    showsClearConfirmation = true
                }
                .disabled(history.items.isEmpty && !history.isUnavailable)
            }
        }
        .padding(DesignTokens.Space.sheetPadding)
        .frame(minWidth: 660, minHeight: 480)
        .background(DesignTokens.Brand.themeBackground)
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
        HStack(spacing: DesignTokens.Space.block) {
            Text(item.title)
                .font(DesignTokens.Fonts.rowTitle)
                .lineLimit(1)
                .truncationMode(.tail)
            if let identity = item.skillIdentity {
                Text(identity.repositoryRelativePath.isEmpty
                     ? identity.sourceKey
                     : "\(identity.sourceKey)/\(identity.repositoryRelativePath)")
                    .font(DesignTokens.Fonts.evidence)
                    .foregroundStyle(DesignTokens.Status.neutral)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(item.outcomeDisplayName)
                .font(DesignTokens.Fonts.caption)
                .foregroundStyle(outcomeColor)
            Text(item.recordedAt.formatted(date: .abbreviated, time: .standard))
                .font(DesignTokens.Fonts.captionSmall)
                .foregroundStyle(DesignTokens.Status.neutral)
                .lineLimit(1)
        }
        .padding(.vertical, DesignTokens.Space.rowVertical)
    }

    private var outcomeColor: Color {
        switch item.outcome {
        case .interruptedUnknown: return DesignTokens.Status.warning
        case .record(let outcome):
            switch outcome {
            case .success, .complete, .created: return DesignTokens.Status.ok
            case .partial, .cancelled: return DesignTokens.Status.warning
            case .failed, .deleted: return DesignTokens.Status.error
            }
        }
    }
}

private struct AuditRecordDetailView: View {
    let item: AuditActivityItem
    let openSkill: (String, String) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.block) {
            Label("当时记录：以下为该动作发生时的历史快照，不代表当前实时状态。",
                  systemImage: "clock.arrow.circlepath")
                .font(DesignTokens.Fonts.caption)
                .foregroundStyle(DesignTokens.Status.neutral)

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
                    .font(DesignTokens.Fonts.caption)
                    .foregroundStyle(DesignTokens.Status.neutral)
            }

            if item.action == .updateRun, let identity = item.skillIdentity {
                Button("查看相关 Skill") {
                    _ = openSkill(identity.sourceKey, identity.repositoryRelativePath)
                }
                .font(DesignTokens.Fonts.rowTitle)
            }
        }
        .padding(DesignTokens.Space.cardPadding)
        .background(
            DesignTokens.Surface.card,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
        )
    }

    private func detailText(_ value: String) -> some View {
        Text(value)
            .font(DesignTokens.Fonts.evidence)
            .textSelection(.enabled)
            .multilineTextAlignment(.trailing)
    }
}

#Preview {
    ContentView(model: AppModel())
}
