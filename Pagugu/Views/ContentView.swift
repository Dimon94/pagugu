import AppKit
import SwiftUI
import UniformTypeIdentifiers

// L3 COORD: Pagugu/Views/ContentView.swift
// POS: 主窗口内容（Variant F 主从结构，#16 落地目录 IA，#20 落地目录状态短语与静默排序）。
//      左侧：平铺目录——来源仓库行（可收起/展开子 Skill 行，默认展开，chevron 独立热区）
//      + 无仓库可归行（来源不明）；消费 Skill Read Model 给出的逐态短语与五档顺序；无分组标题、无筛选 UI。
//      右侧：Skill 详情四块（状态与检出、安装位置、来源标识、SKILL.md 原文只读可选中）；
//      空选择回欢迎引导。「相关记录」「更新动作」块归后续票。
//      工具栏管理 Project Scan Root；Registry 故障由全窗口门面接管。
//      View 只消费 Skill Read Model、只发 AppModel intent，不做 IO。
// TEST: repo://PaguguTests/AppModelTests.swift（AppModel 正常/阻断投影与 intent 路由 smoke）。

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var selection: SkillDirectoryNode?
    @State private var showsProjectScanRoots = false
    @State private var showsProjectRootImporter = false

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
        .alert(
            "无法保存 App Registry",
            isPresented: Binding(
                get: { model.projectScanRootError != nil },
                set: { isPresented in
                    if !isPresented { model.clearProjectScanRootError() }
                }
            )
        ) {
            Button("好") {
                model.clearProjectScanRootError()
            }
        } message: {
            Text(model.projectScanRootError?.reason ?? "Unknown")
        }
    }

    private var skillBrowser: some View {
        NavigationSplitView {
            SkillDirectoryListView(
                readModel: model.readModel,
                collapsedSources: model.collapsedSources,
                onToggleSource: { model.toggleSourceCollapsed($0) },
                selection: $selection
            )
        } detail: {
            detailView
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("扫描范围", systemImage: "folder.badge.gearshape") {
                    showsProjectScanRoots = true
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
                    markdown: model.skillMarkdown(canonicalPath: entry.canonicalPath)
                )
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
                UnattributedInstallationRow(item: item)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.displayName)
                        .font(.title2.bold())
                    HostLogoSlots(hosts: entry.hosts)
                }

                Divider()

                CheckoutStatusBlock(checkouts: checkouts)

                Divider()

                InstallationsBlock(installations: entry.installations)

                Divider()

                SourceIdentityBlock(
                    sourceKey: entry.id.sourceKey,
                    repositoryRelativePath: entry.id.repositoryRelativePath
                )

                Divider()

                MarkdownSourceBlock(markdown: markdown)

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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("状态与检出")
                .font(.headline)
            ForEach(checkouts) { checkout in
                CheckoutCard(checkout: checkout)
            }
        }
    }
}

private struct CheckoutCard: View {
    let checkout: CheckoutCardReadModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(checkout.state.displayName)
                    .font(.headline)
                Text(checkout.state.rawValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(checkout.state.recoveryDirection)
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private func fact(_ name: String, _ value: String) -> some View {
        LabeledContent(name) {
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
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
                        Text(installation.projectionType.displayName + attributionNote(for: installation.projectionType))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func attributionNote(for type: ProjectionType) -> String {
        switch type {
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

#Preview {
    ContentView(model: AppModel())
}
