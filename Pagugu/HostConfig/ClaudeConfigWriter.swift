import Foundation

// L3 COORD: Pagugu/HostConfig/ClaudeConfigWriter.swift
// INPUT: Claude Code Skill name、Installation 上下文、Exposure Level 或删除 override 意图，以及用户级/项目级 settings.json。
// OUTPUT: 用户级 `skillOverrides.<skill name>` 的四档合并写/删除、完整事实写后校验、实时分歧派生与单槽备份恢复。
// POS: HostConfig 模块的 Claude Code adapter。复用 HostConfigWriter 的 JSON 合并、漂移检测、备份与原子替换；
//      does not own Visibility Claim 持久化、Project settings、UI 或自动重应用。
// TEST: repo://PaguguTests/ClaudeConfigWriterTests.swift。

/// 把 Claude Code 的 `skillOverrides` 协议隐藏在 typed Exposure Level interface 后。
struct ClaudeConfigWriter: Sendable {
    private let homeDirectory: URL
    private let configurationURL: URL
    private let writer: HostConfigWriter

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        writer: HostConfigWriter = HostConfigWriter()
    ) {
        let standardizedHome = homeDirectory.standardizedFileURL
        self.homeDirectory = standardizedHome
        configurationURL = standardizedHome.appendingPathComponent(".claude/settings.json")
        self.writer = writer
    }

    /// L4 IN: skillName 是 Claude Code 使用的非空 Skill name；installations 提供当前 Personal/Project 生效上下文；nil 表示删除用户 override key。
    /// OUT: 只合并用户级 `skillOverrides.<skillName>`；四档分别写 on/name-only/user-invocable-only/off；非 nil 写入后重读完整事实。
    /// FAIL: 继承 HostConfigWriter 的 fail-closed 错误；项目 override 等更高优先级事实阻止目标档位时明确失败。
    func apply(
        exposureLevel: ExposureLevel?,
        forSkillNamed skillName: String,
        installations: [SkillInstallation]
    ) throws {
        if let exposureLevel {
            _ = try claimState(
                expecting: exposureLevel,
                forSkillNamed: skillName,
                installations: installations
            )
        }
        try writer.merge(
            exposureLevel.map(configurationValue(for:)),
            at: ["skillOverrides", skillName],
            in: configurationURL
        )
        if let exposureLevel {
            guard try claimState(
                expecting: exposureLevel,
                forSkillNamed: skillName,
                installations: installations
            ) == .consistent else {
                throw HostConfigWriterError.effectiveConfigurationMismatch
            }
        }
    }

    /// 每次通过 HostConfigReader 重读用户级与全部项目级 Claude 配置事实，再与 typed 主张比较。
    func claimState(
        expecting exposureLevel: ExposureLevel,
        forSkillNamed skillName: String,
        installations: [SkillInstallation]
    ) throws -> HostConfigClaimState {
        let surface = HostConfigReader(homeDirectory: homeDirectory)
            .invocationSurfaces(skillName: skillName, installations: installations)
            .first { $0.host == .claude }
        guard let surface else { throw HostConfigWriterError.invalidConfiguration }
        let currentLevel: ExposureLevel
        switch surface.state {
        case .level(let level), .unsupported(let level):
            currentLevel = level
        case .readFailed:
            throw HostConfigWriterError.invalidConfiguration
        }
        return currentLevel == exposureLevel ? .consistent : .divergent
    }

    /// 恢复最近一次 Pagugu 写入该用户级 Claude 配置前的完整字节；备份本身保留。
    func restoreConfiguration() throws {
        try writer.restoreBackup(for: configurationURL)
    }

    private func configurationValue(for exposureLevel: ExposureLevel) -> HostConfigValue {
        switch exposureLevel {
        case .fullyExposed: return .string("on")
        case .nameOnly: return .string("name-only")
        case .explicitOnly: return .string("user-invocable-only")
        case .fullyDisabled: return .string("off")
        }
    }
}
