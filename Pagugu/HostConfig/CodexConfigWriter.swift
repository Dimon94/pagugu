import Foundation

// L3 COORD: Pagugu/HostConfig/CodexConfigWriter.swift
// INPUT: Codex Skill name、Installation 路径、三档 Exposure Level，以及 ~/.codex/config.toml 与 agents/openai.yaml。
// OUTPUT: `[[skills.config]]` 与 `policy.allow_implicit_invocation` 的行级最小写入/删除、实时分歧派生和单动作双文件快照恢复。
// POS: HostConfig 模块的 Codex adapter。复用 HostConfigWriter 的漂移检测、备份与原子替换；
//      does not own Visibility Claim、UI、Pi 写通道或 Skill Source 内容。
// TEST: repo://PaguguTests/CodexConfigWriterTests.swift、repo://PaguguTests/AppModelCodexTests.swift。

struct CodexSkillConfiguration: Sendable {
    let name: String?
    let path: String?
    let enabled: Bool
}

/// 把 Codex TOML/YAML 协议隐藏在 typed Exposure Level interface 后。
struct CodexConfigWriter: Sendable {
    private let homeDirectory: URL
    private let configurationURL: URL
    private let policyURL: URL
    private let writer: HostConfigWriter

    // L5 PARAM: 用户级 TOML 固定为 ~/.codex/config.toml；用户级 YAML 固定为 ~/.codex/agents/openai.yaml。
    // PAIR: fullyDisabled ↔ 匹配 skills.config.enabled=false；explicitOnly ↔ policy.allow_implicit_invocation=false；
    //       fullyExposed ↔ 两处对应配置都不存在；nameOnly 永远 Unsupported。
    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        writer: HostConfigWriter = HostConfigWriter()
    ) {
        let standardizedHome = homeDirectory.standardizedFileURL
        self.homeDirectory = standardizedHome
        configurationURL = standardizedHome.appendingPathComponent(".codex/config.toml")
        policyURL = standardizedHome.appendingPathComponent(".codex/agents/openai.yaml")
        self.writer = writer
    }

    // L4 IN: skillName 非空；installations 至少含一个 Codex Installation；仅接受 Codex 支持的三档。
    // OUT: fullyDisabled 写/改一个匹配 `[[skills.config]]` 为 false；explicitOnly 写 YAML false 并移除禁用条目；
    //      fullyExposed 移除对应 TOML 条目与 YAML key。只改目标行/条目，未知字段、注释与其他格式保持。
    // FAIL: 任一相关文件格式损坏、身份不明确、提交前漂移或文件操作失败均 fail closed，不把 Registry Claim 冒充文件成功。
    // L6 CHAIN: Reader 预检全部当前 Codex 事实 → 一次解析两个用户文件并产出最小文本差异 → 全部重读防漂移 → 同动作快照备份 → 先提交更保守档位的一侧 → 另一侧。
    func apply(
        exposureLevel: ExposureLevel,
        forSkillNamed skillName: String,
        installations: [SkillInstallation]
    ) throws {
        guard !skillName.isEmpty else { throw HostConfigWriterError.invalidConfiguration }
        let paths = skillPaths(from: installations)
        guard let preferredPath = paths.preferred.first else {
            throw HostConfigWriterError.invalidConfiguration
        }
        guard exposureLevel != .nameOnly else {
            throw HostConfigWriterError.unsupportedExposureLevel
        }
        _ = try claimState(
            expecting: exposureLevel,
            forSkillNamed: skillName,
            installations: installations
        )

        let enabled: Bool? = exposureLevel == .fullyDisabled ? false : nil
        let allowsImplicitInvocation: Bool? = exposureLevel == .explicitOnly ? false : nil
        let shouldRewritePolicy = exposureLevel != .fullyDisabled

        let configurationURLs = exposureLevel == .explicitOnly
            ? [policyURL, configurationURL]
            : [configurationURL, policyURL]
        try writer.rewriteConfigurations(at: configurationURLs) { url, originalBytes in
            switch url {
            case configurationURL:
                return try CodexLineConfiguration.rewriteTOML(
                    originalBytes,
                    skillName: skillName,
                    matchingPaths: paths.matching,
                    preferredPath: preferredPath,
                    enabled: enabled,
                    homeDirectory: homeDirectory
                )
            case policyURL:
                guard shouldRewritePolicy else { return nil }
                return try CodexLineConfiguration.rewriteYAML(
                    originalBytes,
                    allowsImplicitInvocation: allowsImplicitInvocation
                )
            default:
                throw HostConfigWriterError.invalidConfiguration
            }
        }
        guard try claimState(
            expecting: exposureLevel,
            forSkillNamed: skillName,
            installations: installations
        ) == .consistent else {
            throw HostConfigWriterError.effectiveConfigurationMismatch
        }
    }

    /// 每次通过 HostConfigReader 重读全部 Codex 文件事实，再与 typed 主张比较。
    func claimState(
        expecting exposureLevel: ExposureLevel,
        forSkillNamed skillName: String,
        installations: [SkillInstallation]
    ) throws -> HostConfigClaimState {
        guard exposureLevel != .nameOnly else {
            throw HostConfigWriterError.unsupportedExposureLevel
        }
        let surface = HostConfigReader(homeDirectory: homeDirectory)
            .invocationSurfaces(skillName: skillName, installations: installations)
            .first { $0.host == .codex }
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

    /// 恢复两个 Codex 用户级配置中全部现存的最近写前备份；没有任一备份时明确失败。
    func restoreConfiguration() throws {
        try writer.restoreBackups(for: [configurationURL, policyURL])
    }

    private func skillPaths(
        from installations: [SkillInstallation]
    ) -> (preferred: [String], matching: Set<String>) {
        let codexInstallations = installations.filter { $0.hosts.contains(.codex) }
        let preferred = Set(codexInstallations.map { installation in
            normalizedSkillMarkdownPath(installation.asFoundPath)
        }).sorted()
        let matching = Set(codexInstallations.flatMap { installation in
            [installation.asFoundPath, installation.canonicalPath].map(normalizedSkillMarkdownPath)
        })
        return (preferred, matching)
    }

    private func normalizedSkillMarkdownPath(_ skillDirectoryPath: String) -> String {
        CodexLineConfiguration.normalizedPath(
            URL(fileURLWithPath: expandHome(in: skillDirectoryPath))
                .appendingPathComponent("SKILL.md")
                .standardizedFileURL.path,
            homeDirectory: homeDirectory
        )
    }

    private func expandHome(in path: String) -> String {
        if path == "~" { return homeDirectory.path }
        if path.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(path.dropFirst(2))).path
        }
        return path
    }
}

/// Codex 当前窄 TOML/YAML schema 的共享行级 parser/rewriter。它不尝试成为通用 TOML/YAML parser。
enum CodexLineConfiguration {
    private struct TextLine {
        var content: String
        var terminator: String
    }

    private struct TextDocument {
        var lines: [TextLine]
        let preferredTerminator: String
        let originallyEndedWithTerminator: Bool

        init(data: Data?) throws {
            guard let data else {
                lines = []
                preferredTerminator = "\n"
                originallyEndedWithTerminator = false
                return
            }
            guard let contents = String(data: data, encoding: .utf8) else {
                throw HostConfigWriterError.invalidConfiguration
            }
            lines = Self.split(contents)
            preferredTerminator = lines.first(where: { !$0.terminator.isEmpty })?.terminator ?? "\n"
            originallyEndedWithTerminator = lines.last?.terminator.isEmpty == false
        }

        var data: Data { Data(lines.flatMap { ($0.content + $0.terminator).utf8 }) }

        mutating func removeLines(at indexes: Set<Int>) {
            lines = lines.enumerated().compactMap { indexes.contains($0.offset) ? nil : $0.element }
        }

        mutating func insertLine(_ content: String, at index: Int) {
            if index < lines.count {
                lines.insert(TextLine(content: content, terminator: preferredTerminator), at: index)
                return
            }
            appendLines([content], separatingBlock: false)
        }

        mutating func appendLines(_ contents: [String], separatingBlock: Bool) {
            guard !contents.isEmpty else { return }
            if !lines.isEmpty {
                if lines[lines.count - 1].terminator.isEmpty {
                    lines[lines.count - 1].terminator = preferredTerminator
                }
                if separatingBlock, lines.last?.content.isEmpty == false {
                    lines.append(TextLine(content: "", terminator: preferredTerminator))
                }
            }
            for content in contents {
                lines.append(TextLine(content: content, terminator: preferredTerminator))
            }
            if !originallyEndedWithTerminator {
                lines[lines.count - 1].terminator = ""
            }
        }

        private static func split(_ contents: String) -> [TextLine] {
            guard !contents.isEmpty else { return [] }
            var result: [TextLine] = []
            var lineStart = contents.startIndex
            var index = contents.startIndex
            while index < contents.endIndex {
                guard contents[index] == "\n" else {
                    index = contents.index(after: index)
                    continue
                }
                var contentEnd = index
                var terminator = "\n"
                if contentEnd > lineStart {
                    let previous = contents.index(before: contentEnd)
                    if contents[previous] == "\r" {
                        contentEnd = previous
                        terminator = "\r\n"
                    }
                }
                result.append(TextLine(
                    content: String(contents[lineStart..<contentEnd]),
                    terminator: terminator
                ))
                lineStart = contents.index(after: index)
                index = lineStart
            }
            if lineStart < contents.endIndex {
                result.append(TextLine(
                    content: String(contents[lineStart..<contents.endIndex]),
                    terminator: ""
                ))
            }
            return result
        }
    }

    private struct TOMLField {
        let rawValue: String
        let lineIndex: Int
    }

    private struct TOMLSection {
        let startLine: Int
        let endLine: Int
        let configuration: CodexSkillConfiguration
        let enabledLine: Int
    }

    private struct YAMLDocumentInfo {
        let targetLine: Int?
        let policyHeaderLine: Int?
        let policyEndLine: Int
        let policyIndent: Int
        let policyChildIndent: Int?
    }

    static func skillConfigurations(from data: Data) throws -> [CodexSkillConfiguration] {
        try parseTOML(TextDocument(data: data)).map(\.configuration)
    }

    static func allowsImplicitInvocation(from data: Data) throws -> Bool? {
        let document = try TextDocument(data: data)
        let info = try parseYAML(document)
        guard let targetLine = info.targetLine else { return nil }
        return try booleanValue(inYAMLLine: document.lines[targetLine].content)
    }

    static func rewriteTOML(
        _ data: Data?,
        skillName: String,
        matchingPaths: Set<String>,
        preferredPath: String,
        enabled: Bool?,
        homeDirectory: URL
    ) throws -> Data? {
        var document = try TextDocument(data: data)
        let sections = try parseTOML(document)
        let matchingSections = sections.filter { section in
            section.configuration.name == skillName || section.configuration.path.map {
                matchingPaths.contains(normalizedPath($0, homeDirectory: homeDirectory))
            } == true
        }

        if let enabled {
            if matchingSections.isEmpty {
                let encodedPath = try tomlString(preferredPath)
                document.appendLines(
                    ["[[skills.config]]", "path = \(encodedPath)", "enabled = \(enabled)"],
                    separatingBlock: true
                )
                return document.data
            }
            var changed = false
            for section in matchingSections {
                let original = document.lines[section.enabledLine].content
                let replacement = try replacingAssignmentValue(
                    in: original,
                    delimiter: "=",
                    with: String(enabled)
                )
                if replacement != original {
                    document.lines[section.enabledLine].content = replacement
                    changed = true
                }
            }
            return changed ? document.data : nil
        }

        guard !matchingSections.isEmpty else { return nil }
        var removedIndexes = Set<Int>()
        for section in matchingSections {
            removedIndexes.formUnion(section.startLine..<section.endLine)
        }
        document.removeLines(at: removedIndexes)
        return document.data
    }

    static func rewriteYAML(
        _ data: Data?,
        allowsImplicitInvocation: Bool?
    ) throws -> Data? {
        var document = try TextDocument(data: data)
        let info = try parseYAML(document)
        if let allowsImplicitInvocation {
            if let targetLine = info.targetLine {
                let original = document.lines[targetLine].content
                let replacement = try replacingAssignmentValue(
                    in: original,
                    delimiter: ":",
                    with: String(allowsImplicitInvocation)
                )
                guard replacement != original else { return nil }
                document.lines[targetLine].content = replacement
                return document.data
            }
            if let policyHeaderLine = info.policyHeaderLine {
                let indent = info.policyChildIndent ?? info.policyIndent + 2
                document.insertLine(
                    String(repeating: " ", count: indent)
                        + "allow_implicit_invocation: \(allowsImplicitInvocation)",
                    at: max(policyHeaderLine + 1, info.policyEndLine)
                )
                return document.data
            }
            document.appendLines(
                ["policy:", "  allow_implicit_invocation: \(allowsImplicitInvocation)"],
                separatingBlock: true
            )
            return document.data
        }

        guard let targetLine = info.targetLine else { return nil }
        document.removeLines(at: [targetLine])
        return document.data
    }

    static func normalizedPath(_ path: String, homeDirectory: URL) -> String {
        let expandedPath: String
        if path == "~" {
            expandedPath = homeDirectory.path
        } else if path.hasPrefix("~/") {
            expandedPath = homeDirectory.appendingPathComponent(String(path.dropFirst(2))).path
        } else {
            expandedPath = path
        }
        return URL(fileURLWithPath: expandedPath).standardizedFileURL.path
    }

    private static func parseTOML(_ document: TextDocument) throws -> [TOMLSection] {
        var sections: [TOMLSection] = []
        var sectionStart: Int?
        var fields: [String: TOMLField]?

        func finishSection(at endLine: Int) throws {
            guard let currentFields = fields, let startLine = sectionStart else { return }
            guard let enabledField = currentFields["enabled"],
                  let enabled = parseBoolean(enabledField.rawValue),
                  currentFields["name"] != nil || currentFields["path"] != nil else {
                throw HostConfigWriterError.invalidConfiguration
            }
            let name = try currentFields["name"].map { try parseTOMLString($0.rawValue) }
            let path = try currentFields["path"].map { try parseTOMLString($0.rawValue) }
            sections.append(TOMLSection(
                startLine: startLine,
                endLine: endLine,
                configuration: CodexSkillConfiguration(name: name, path: path, enabled: enabled),
                enabledLine: enabledField.lineIndex
            ))
        }

        for (lineIndex, rawLine) in document.lines.map(\.content).enumerated() {
            let line = stripComment(from: rawLine).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("[") {
                try finishSection(at: lineIndex)
                if line == "[[skills.config]]" {
                    sectionStart = lineIndex
                    fields = [:]
                } else {
                    if line.contains("skills.config") {
                        throw HostConfigWriterError.invalidConfiguration
                    }
                    sectionStart = nil
                    fields = nil
                }
                continue
            }
            guard fields != nil else { continue }
            guard let equalsIndex = line.firstIndex(of: "=") else {
                throw HostConfigWriterError.invalidConfiguration
            }
            let key = line[..<equalsIndex].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equalsIndex)...].trimmingCharacters(in: .whitespaces)
            guard ["name", "path", "enabled"].contains(key) else { continue }
            guard fields?[key] == nil, !value.isEmpty else {
                throw HostConfigWriterError.invalidConfiguration
            }
            fields?[key] = TOMLField(rawValue: value, lineIndex: lineIndex)
        }
        try finishSection(at: document.lines.count)
        return sections
    }

    private static func parseYAML(_ document: TextDocument) throws -> YAMLDocumentInfo {
        let rootIndent = document.lines.compactMap { line -> Int? in
            let content = stripComment(from: line.content)
            guard !content.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return content.prefix { $0 == " " || $0 == "\t" }.count
        }.min() ?? 0
        var targetLine: Int?
        var policyHeaderLine: Int?
        var policyIndent = 0
        var policyEndLine = document.lines.count
        var policyChildIndent: Int?
        var activePolicyIndent: Int?

        for (lineIndex, rawLine) in document.lines.map(\.content).enumerated() {
            let withoutComment = stripComment(from: rawLine)
            guard !withoutComment.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let indentation = withoutComment.prefix { $0 == " " || $0 == "\t" }
            guard !indentation.contains("\t") else {
                throw HostConfigWriterError.invalidConfiguration
            }
            let indent = indentation.count
            let line = withoutComment.trimmingCharacters(in: .whitespaces)
            if indent == rootIndent, line == "policy:" {
                guard policyHeaderLine == nil else {
                    throw HostConfigWriterError.invalidConfiguration
                }
                policyHeaderLine = lineIndex
                policyIndent = indent
                activePolicyIndent = indent
                continue
            }
            if indent == rootIndent, line.hasPrefix("policy:") {
                throw HostConfigWriterError.invalidConfiguration
            }
            if let currentPolicyIndent = activePolicyIndent, indent <= currentPolicyIndent {
                policyEndLine = lineIndex
                activePolicyIndent = nil
            } else if activePolicyIndent != nil, policyChildIndent == nil {
                policyChildIndent = indent
            }
            guard line.hasPrefix("allow_implicit_invocation"),
                  let colonIndex = line.firstIndex(of: ":"),
                  line[..<colonIndex].trimmingCharacters(in: .whitespaces)
                    == "allow_implicit_invocation" else {
                continue
            }
            guard activePolicyIndent.map({ indent > $0 }) == true,
                  policyChildIndent == indent else {
                continue
            }
            guard targetLine == nil,
                  parseBoolean(String(line[line.index(after: colonIndex)...])) != nil else {
                throw HostConfigWriterError.invalidConfiguration
            }
            targetLine = lineIndex
        }
        return YAMLDocumentInfo(
            targetLine: targetLine,
            policyHeaderLine: policyHeaderLine,
            policyEndLine: policyEndLine,
            policyIndent: policyIndent,
            policyChildIndent: policyChildIndent
        )
    }

    private static func booleanValue(inYAMLLine line: String) throws -> Bool {
        let withoutComment = stripComment(from: line)
        guard let colonIndex = withoutComment.firstIndex(of: ":"),
              let value = parseBoolean(String(withoutComment[withoutComment.index(after: colonIndex)...])) else {
            throw HostConfigWriterError.invalidConfiguration
        }
        return value
    }

    private static func replacingAssignmentValue(
        in line: String,
        delimiter: Character,
        with newValue: String
    ) throws -> String {
        guard let delimiterIndex = line.firstIndex(of: delimiter) else {
            throw HostConfigWriterError.invalidConfiguration
        }
        let valueStart = line.index(after: delimiterIndex)
        let commentStart = commentStartIndex(in: line) ?? line.endIndex
        guard valueStart <= commentStart else {
            throw HostConfigWriterError.invalidConfiguration
        }
        let valueRegion = line[valueStart..<commentStart]
        let leadingWhitespace = valueRegion.prefix { $0 == " " || $0 == "\t" }
        let trailingWhitespace = valueRegion.reversed().prefix { $0 == " " || $0 == "\t" }.reversed()
        return String(line[..<valueStart]) + leadingWhitespace + newValue + trailingWhitespace
            + String(line[commentStart...])
    }

    private static func parseTOMLString(_ rawValue: String) throws -> String {
        let value = rawValue.trimmingCharacters(in: .whitespaces)
        if value.count >= 2, value.first == "'", value.last == "'" {
            return String(value.dropFirst().dropLast())
        }
        if value.count >= 2, value.first == "\"", value.last == "\"",
           let data = value.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: data) {
            return decoded
        }
        throw HostConfigWriterError.invalidConfiguration
    }

    private static func tomlString(_ value: String) throws -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            return try String(decoding: encoder.encode(value), as: UTF8.self)
        } catch {
            throw HostConfigWriterError.invalidConfiguration
        }
    }

    private static func parseBoolean(_ rawValue: String) -> Bool? {
        switch rawValue.trimmingCharacters(in: .whitespaces) {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    private static func stripComment(from line: String) -> String {
        guard let commentStart = commentStartIndex(in: line) else { return line }
        return String(line[..<commentStart])
    }

    private static func commentStartIndex(in line: String) -> String.Index? {
        var inSingleQuote = false
        var inDoubleQuote = false
        var escaped = false
        for index in line.indices {
            let character = line[index]
            if inDoubleQuote && escaped {
                escaped = false
                continue
            }
            if inDoubleQuote && character == "\\" {
                escaped = true
                continue
            }
            if character == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                continue
            }
            if character == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                continue
            }
            if character == "#" && !inSingleQuote && !inDoubleQuote {
                return index
            }
        }
        return nil
    }
}
