import Foundation

// L3 COORD: Pagugu/HostConfig/HostConfigReader.swift
// INPUT: Host Profile 能力矩阵、Skill 展示名与逐 Installation 路径、宿主实时配置文件。
// OUTPUT: 逐已安装 Agent Host 的调用面只读事实；不写文件、不持久化、不生成 Visibility Claim。
// POS: HostConfig 模块。owns Claude JSON、Codex TOML/YAML 与 Pi 独占 JSON 的窄读取协议；
//      Codex 与 Writer 共用 CodexLineConfiguration parser，避免读写 schema 分叉；
//      Reader owns 配置值到 Exposure Level/Unsupported/读取失败的确定性翻译。
// TEST: repo://PaguguTests/HostConfigReaderTests.swift、repo://PaguguTests/AppModelSurfaceTests.swift。

/// 单个宿主当前调用面事实。读取失败与宿主能力缺口都不能冒充其他档位。
enum HostInvocationSurfaceState: Equatable, Sendable {
    case level(ExposureLevel)
    case unsupported(ExposureLevel)
    case readFailed
}

/// Skill × Agent Host 的调用面投影。Reader 只填文件事实；AppModel 可附加 Registry Claim 并派生分歧。
struct HostInvocationSurface: Identifiable, Equatable, Sendable {
    var id: AgentHost { host }

    let host: AgentHost
    let state: HostInvocationSurfaceState
    let unsupportedLevels: [ExposureLevel]
    let claimLevel: ExposureLevel?

    init(
        host: AgentHost,
        state: HostInvocationSurfaceState,
        unsupportedLevels: [ExposureLevel],
        claimLevel: ExposureLevel? = nil
    ) {
        self.host = host
        self.state = state
        self.unsupportedLevels = unsupportedLevels
        self.claimLevel = claimLevel
    }

    /// 分歧只由当前可验证文件档位与持久主张派生；读取失败保持 Unknown，不冒充分歧结论。
    var hasDivergence: Bool {
        guard let claimLevel else { return false }
        switch state {
        case .level(let currentLevel), .unsupported(let currentLevel):
            return currentLevel != claimLevel
        case .readFailed:
            return false
        }
    }

    func withClaimLevel(_ claimLevel: ExposureLevel?) -> HostInvocationSurface {
        HostInvocationSurface(
            host: host,
            state: state,
            unsupportedLevels: unsupportedLevels,
            claimLevel: claimLevel
        )
    }
}

/// 实时读取宿主配置。文件不存在表示宿主默认行为；已存在但不可读或格式无效时 fail closed。
struct HostConfigReader: Sendable {
    private enum ReadError: Error {
        case invalidDocument
    }

    private enum ClaudeOverride: String, Decodable {
        case on
        case nameOnly = "name-only"
        case userInvocableOnly = "user-invocable-only"
        case off

        var exposureLevel: ExposureLevel {
            switch self {
            case .on: return .fullyExposed
            case .nameOnly: return .nameOnly
            case .userInvocableOnly: return .explicitOnly
            case .off: return .fullyDisabled
            }
        }
    }

    private struct ClaudeSettings: Decodable {
        let skillOverrides: [String: ClaudeOverride]?
    }

    private struct PiVisibilityDocument: Decodable {
        let skills: [String: ExposureLevel]
    }

    let homeDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    // L4 IN: skillName 是宿主配置使用的 Skill 展示名；installations 保留 as-found 路径、scope 与宿主归因。
    // OUT: 只返回至少有一个 Installation 的宿主，按 AgentHost.allCases 固定顺序；每次调用都重读磁盘。
    // INVARIANT: 文件缺失采用宿主默认完全暴露；已存在文件任一相关格式无法验证时只返回 readFailed；
    //            Claude 项目 key 覆盖用户 key，多 Installation 上下文取最严格档位以避免假报更宽暴露；
    //            不支持的磁盘档位返回 unsupported，绝不静默映射到其他档位。
    // TEST: repo://PaguguTests/HostConfigReaderTests.swift。
    func invocationSurfaces(
        skillName: String,
        installations: [SkillInstallation]
    ) -> [HostInvocationSurface] {
        let installedHosts = Set(installations.flatMap(\.hosts))
        return HostProfiles.all.compactMap { profile in
            guard installedHosts.contains(profile.host) else { return nil }
            let level: Result<ExposureLevel, ReadError>
            do {
                switch profile.host {
                case .claude:
                    level = .success(try claudeLevel(
                        skillName: skillName,
                        installations: installations
                    ))
                case .codex:
                    level = .success(try codexLevel(
                        skillName: skillName,
                        installations: installations
                    ))
                case .pi:
                    level = .success(try piLevel(skillName: skillName))
                }
            } catch {
                level = .failure(.invalidDocument)
            }
            return surface(profile: profile, level: level)
        }
    }

    private func surface(
        profile: HostProfile,
        level: Result<ExposureLevel, ReadError>
    ) -> HostInvocationSurface {
        let state: HostInvocationSurfaceState
        switch level {
        case .success(let exposureLevel):
            state = profile.supports(exposureLevel)
                ? .level(exposureLevel)
                : .unsupported(exposureLevel)
        case .failure:
            state = .readFailed
        }
        return HostInvocationSurface(
            host: profile.host,
            state: state,
            unsupportedLevels: ExposureLevel.allCases.filter { !profile.supports($0) }
        )
    }

    // MARK: - Claude Code settings.json

    private func claudeLevel(
        skillName: String,
        installations: [SkillInstallation]
    ) throws -> ExposureLevel {
        let userSettingsURL = homeDirectory.appendingPathComponent(".claude/settings.json")
        let userLevel = try claudeOverride(skillName: skillName, at: userSettingsURL)?.exposureLevel
            ?? .fullyExposed
        let claudeInstallations = installations.filter { $0.hosts.contains(.claude) }
        var effectiveLevels: [ExposureLevel] = []
        if claudeInstallations.contains(where: { $0.scope == .personal }) {
            effectiveLevels.append(userLevel)
        }
        let projectSettingsURLs = Set(claudeInstallations.compactMap(projectClaudeSettingsURL))
        for settingsURL in projectSettingsURLs.sorted(by: { $0.path < $1.path }) {
            let projectLevel = try claudeOverride(skillName: skillName, at: settingsURL)?.exposureLevel
                ?? userLevel
            effectiveLevels.append(projectLevel)
        }
        return mostRestrictive(effectiveLevels.isEmpty ? [userLevel] : effectiveLevels)
    }

    private func claudeOverride(skillName: String, at url: URL) throws -> ClaudeOverride? {
        guard let data = try readExistingFile(at: url) else { return nil }
        do {
            return try JSONDecoder().decode(ClaudeSettings.self, from: data).skillOverrides?[skillName]
        } catch {
            throw ReadError.invalidDocument
        }
    }

    private func projectClaudeSettingsURL(for installation: SkillInstallation) -> URL? {
        guard installation.scope == .project, installation.hosts.contains(.claude) else { return nil }
        let expandedPath = expandHome(in: installation.asFoundPath)
        let components = URL(fileURLWithPath: expandedPath).standardizedFileURL.pathComponents
        guard let claudeIndex = components.indices.first(where: { index in
            components[index] == ".claude" && components.indices.contains(index + 1)
                && components[index + 1] == "skills"
        }) else { return nil }
        let projectRootPath = NSString.path(withComponents: Array(components[..<claudeIndex]))
        return URL(fileURLWithPath: projectRootPath, isDirectory: true)
            .appendingPathComponent(".claude/settings.json")
    }

    // MARK: - Codex config.toml + agents/openai.yaml

    private func codexLevel(
        skillName: String,
        installations: [SkillInstallation]
    ) throws -> ExposureLevel {
        let codexInstallations = installations.filter { $0.hosts.contains(.codex) }
        let skillMarkdownPaths = Set(codexInstallations.flatMap { installation in
            [installation.asFoundPath, installation.canonicalPath].map {
                normalizedPath($0, appendingSkillMarkdown: true)
            }
        })
        let configURL = homeDirectory.appendingPathComponent(".codex/config.toml")
        let configurations = try codexSkillConfigurations(at: configURL)
        var policyURLs = Set([
            homeDirectory.appendingPathComponent(".codex/agents/openai.yaml"),
        ])
        for installation in codexInstallations {
            policyURLs.insert(
                URL(fileURLWithPath: expandHome(in: installation.asFoundPath), isDirectory: true)
                    .appendingPathComponent("agents/openai.yaml")
            )
            policyURLs.insert(
                URL(fileURLWithPath: installation.canonicalPath, isDirectory: true)
                    .appendingPathComponent("agents/openai.yaml")
            )
        }
        let implicitPolicies = try policyURLs.sorted(by: { $0.path < $1.path }).map {
            try codexAllowsImplicitInvocation(at: $0)
        }
        let isDisabled = configurations.contains { configuration in
            let matchesName = configuration.name == skillName
            let matchesPath = configuration.path.map {
                skillMarkdownPaths.contains(normalizedPath($0, appendingSkillMarkdown: false))
            } ?? false
            return (matchesName || matchesPath) && !configuration.enabled
        }
        if isDisabled { return .fullyDisabled }
        return implicitPolicies.contains(false) ? .explicitOnly : .fullyExposed
    }

    private func codexSkillConfigurations(at url: URL) throws -> [CodexSkillConfiguration] {
        guard let data = try readExistingFile(at: url) else { return [] }
        return try CodexLineConfiguration.skillConfigurations(from: data)
    }

    private func codexAllowsImplicitInvocation(at url: URL) throws -> Bool? {
        guard let data = try readExistingFile(at: url) else { return nil }
        return try CodexLineConfiguration.allowsImplicitInvocation(from: data)
    }

    // MARK: - Pi visibility.json

    private func piLevel(skillName: String) throws -> ExposureLevel {
        let url = homeDirectory.appendingPathComponent(".pi/agent/pagugu/visibility.json")
        guard let data = try readExistingFile(at: url) else { return .fullyExposed }
        do {
            return try JSONDecoder().decode(PiVisibilityDocument.self, from: data).skills[skillName]
                ?? .fullyExposed
        } catch {
            throw ReadError.invalidDocument
        }
    }

    // MARK: - Narrow parsing helpers

    private func readExistingFile(at url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch let error as NSError
            where error.domain == NSPOSIXErrorDomain
                && error.code == POSIXErrorCode.ENOENT.rawValue {
            return nil
        } catch {
            throw ReadError.invalidDocument
        }
    }

    private func normalizedPath(_ path: String, appendingSkillMarkdown: Bool) -> String {
        var url = URL(fileURLWithPath: expandHome(in: path))
        if appendingSkillMarkdown {
            url.appendPathComponent("SKILL.md")
        }
        return url.standardizedFileURL.path
    }

    private func expandHome(in path: String) -> String {
        if path == "~" { return homeDirectory.path }
        if path.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(path.dropFirst(2))).path
        }
        return path
    }

    private func mostRestrictive(_ levels: [ExposureLevel]) -> ExposureLevel {
        levels.max { restrictionRank($0) < restrictionRank($1) } ?? .fullyExposed
    }

    private func restrictionRank(_ level: ExposureLevel) -> Int {
        switch level {
        case .fullyExposed: return 0
        case .nameOnly: return 1
        case .explicitOnly: return 2
        case .fullyDisabled: return 3
        }
    }
}
