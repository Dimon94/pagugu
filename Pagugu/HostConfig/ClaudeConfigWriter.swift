import Foundation

// L3 COORD: Pagugu/HostConfig/ClaudeConfigWriter.swift
// INPUT: Claude Code Skill name、Exposure Level 或删除 override 意图，以及用户级 ~/.claude/settings.json。
// OUTPUT: `skillOverrides.<skill name>` 的四档合并写/删除、实时分歧派生与单槽备份恢复。
// POS: HostConfig 模块的 Claude Code adapter。复用 HostConfigWriter 的 JSON 合并、漂移检测、备份与原子替换；
//      does not own Visibility Claim 持久化、Project settings、UI 或自动重应用。
// TEST: repo://PaguguTests/ClaudeConfigWriterTests.swift。

/// 把 Claude Code 的 `skillOverrides` 协议隐藏在 typed Exposure Level interface 后。
struct ClaudeConfigWriter: Sendable {
    private let configurationURL: URL
    private let writer: HostConfigWriter

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        writer: HostConfigWriter = HostConfigWriter()
    ) {
        configurationURL = homeDirectory.standardizedFileURL
            .appendingPathComponent(".claude/settings.json")
        self.writer = writer
    }

    /// L4 IN: skillName 是 Claude Code 使用的非空 Skill name；nil 表示删除对应配置 override key。
    /// OUT: 只合并 `skillOverrides.<skillName>`；四档分别写 on/name-only/user-invocable-only/off。
    /// FAIL: 继承 HostConfigWriter 的 fail-closed 错误与恢复方向；失败时不把配置写入冒充成功。
    func apply(exposureLevel: ExposureLevel?, forSkillNamed skillName: String) throws {
        try writer.merge(
            exposureLevel.map(configurationValue(for:)),
            at: ["skillOverrides", skillName],
            in: configurationURL
        )
    }

    /// 每次实时读取用户级 Claude 配置，并与 typed 主张比较。
    func claimState(
        expecting exposureLevel: ExposureLevel,
        forSkillNamed skillName: String
    ) throws -> HostConfigClaimState {
        try writer.claimState(
            expecting: configurationValue(for: exposureLevel),
            at: ["skillOverrides", skillName],
            in: configurationURL
        )
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
