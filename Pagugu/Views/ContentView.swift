import AppKit
import SwiftUI

// L3 COORD: Pagugu/Views/ContentView.swift
// POS: 主窗口内容（Variant F 主从结构的 #15 简化版）。
//      左侧：平铺 Skill 目录行（宿主 logo 槽位点亮/灰显）；
//      右侧：欢迎引导或详情；Registry 加载与受限恢复时由全窗口门面接管。
// TEST: repo://PaguguTests/AppModelTests.swift（AppModel 正常/阻断投影 smoke）。

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var selectedEntryID: SkillIdentity?

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
    }

    private var skillBrowser: some View {
        NavigationSplitView {
            // 左侧：平铺 Skill 目录
            SkillDirectoryListView(
                entries: model.readModel.entries,
                issues: model.readModel.issues,
                scanOutcome: model.readModel.scanOutcome,
                selection: $selectedEntryID
            )
        } detail: {
            // 右侧：欢迎引导或详情
            if let selectedID = selectedEntryID,
               let entry = model.readModel.entries.first(where: { $0.id == selectedID }) {
                SkillInfoPanel(entry: entry)
            } else {
                WelcomePanel()
            }
        }
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
    let entries: [SkillDirectoryEntry]
    let issues: [ScanIssue]
    let scanOutcome: ScanOutcome
    @Binding var selection: SkillIdentity?

    var body: some View {
        Group {
            if entries.isEmpty && issues.isEmpty {
                // 正常空态
                ContentUnavailableView(
                    "未发现 Skill",
                    systemImage: "tray",
                    description: Text("三个 Personal Skill Root 下没有可解析的 Skill。")
                )
            } else {
                List(selection: $selection) {
                    if !issues.isEmpty {
                        Section {
                            ForEach(issues, id: \.path) { issue in
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
                        ForEach(entries) { entry in
                            SkillDirectoryRow(entry: entry)
                                .tag(entry.id)
                        }
                    }
                }
            }
        }
        .navigationTitle("Skills")
    }
}

private struct SkillDirectoryRow: View {
    let entry: SkillDirectoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.displayName)
                .font(.headline)

            // 宿主 logo 槽位（ADR-0009 §15）：点亮 = 已安装，灰显 = 未安装
            HostLogoSlots(hosts: allHosts)
        }
        .padding(.vertical, 2)
    }

    private var allHosts: Set<AgentHost> {
        Set(entry.installations.flatMap(\.hosts))
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

// MARK: - 右侧详情

private struct SkillInfoPanel: View {
    let entry: SkillDirectoryEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 基础信息
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.displayName)
                        .font(.title2.bold())

                    HostLogoSlots(hosts: Set(entry.installations.flatMap(\.hosts)))
                }

                Divider()

                // 安装位置
                VStack(alignment: .leading, spacing: 4) {
                    Text("安装位置")
                        .font(.headline)
                    ForEach(entry.installations, id: \.asFoundPath) { inst in
                        HStack {
                            Text(inst.asFoundPath)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                            if inst.isSymlink {
                                Image(systemName: "link")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Divider()

                // 来源标识
                VStack(alignment: .leading, spacing: 4) {
                    Text("来源标识")
                        .font(.headline)
                    Text(sourceKeyDescription)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sourceKeyDescription: String {
        switch entry.id.sourceKey {
        case .remoteURL(let url): return url
        case .localPath(let path): return path
        }
    }
}

// MARK: - 欢迎引导

private struct WelcomePanel: View {
    var body: some View {
        ContentUnavailableView(
            "欢迎使用 Pagugu",
            systemImage: "shippingbox",
            description: Text("Pagugu 自动发现三个 Personal Skill Root 下的 Skill。\n从左侧目录选择一个 Skill 查看详情，或添加 Project Scan Root 扩展扫描范围。")
        )
    }
}

#Preview {
    ContentView(model: AppModel())
}
