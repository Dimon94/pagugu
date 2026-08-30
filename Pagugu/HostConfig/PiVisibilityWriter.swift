import Foundation

// L3 COORD: Pagugu/HostConfig/PiVisibilityWriter.swift
// INPUT: Pi Skill name、三档 Exposure Level 与 Pagugu 独占的 ~/.pi/agent/pagugu/visibility.json。
// OUTPUT: hiddenSkills / disabledSkills 的类型化原子写入；文件本身是 Pi 可见性主张的 canonical。
// POS: HostConfig 模块的 Pi 独占配置 adapter。does not own 扩展安装、Registry Claim、UI 或 Pi settings.json。
// TEST: repo://PaguguTests/PiVisibilityWriterTests.swift、repo://PaguguTests/HostConfigReaderTests.swift。

struct PiVisibilityDocument: Codable, Equatable, Sendable {
    var hiddenSkills: [String]
    var disabledSkills: [String]

    static let empty = PiVisibilityDocument(hiddenSkills: [], disabledSkills: [])

    var isValid: Bool {
        let hidden = Set(hiddenSkills)
        let disabled = Set(disabledSkills)
        return hidden.count == hiddenSkills.count && disabled.count == disabledSkills.count
            && hiddenSkills.allSatisfy { !$0.isEmpty }
            && disabledSkills.allSatisfy { !$0.isEmpty }
            && hidden.isDisjoint(with: disabled)
    }

    func exposureLevel(for skillName: String) -> ExposureLevel {
        if disabledSkills.contains(skillName) { return .fullyDisabled }
        if hiddenSkills.contains(skillName) { return .explicitOnly }
        return .fullyExposed
    }
}

enum PiVisibilityWriterError: Error, Equatable, Sendable {
    case invalidSkillName
    case unsupportedExposureLevel
    case invalidConfiguration
    case fileOperationFailed

    var recoverySuggestion: String {
        switch self {
        case .invalidSkillName:
            return "请修复 Pi Skill name 后重新扫描。"
        case .unsupportedExposureLevel:
            return "Pi 只支持完全暴露、仅显式与全禁用。请选择受支持档位。"
        case .invalidConfiguration:
            return "请修复或删除 ~/.pi/agent/pagugu/visibility.json 后重试。"
        case .fileOperationFailed:
            return "请检查 ~/.pi/agent/pagugu 目录与文件权限后重试。"
        }
    }
}

/// 独占配置只有 Pagugu 一个写者，因此直接类型化读改写，不引入共享宿主配置的漂移与备份协议。
struct PiVisibilityWriter: Sendable {
    private let configurationURL: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        configurationURL = homeDirectory.standardizedFileURL
            .appendingPathComponent(".pi/agent/pagugu/visibility.json")
    }

    /// L4 IN: skillName 非空；只接受 Pi 支持的三档，nameOnly 必须 fail closed。
    /// OUT: 原子替换独占 JSON；同一 Skill 只进入 hiddenSkills 或 disabledSkills 一个集合。
    /// FAIL: 已存在文件损坏时保留原字节并返回修复方向；目录或原子写失败不冒充成功。
    func apply(exposureLevel: ExposureLevel, forSkillNamed skillName: String) throws {
        guard !skillName.isEmpty else { throw PiVisibilityWriterError.invalidSkillName }
        var document = try readDocument()
        var hiddenSkills = Set(document.hiddenSkills)
        var disabledSkills = Set(document.disabledSkills)
        hiddenSkills.remove(skillName)
        disabledSkills.remove(skillName)

        switch exposureLevel {
        case .fullyExposed:
            break
        case .explicitOnly:
            hiddenSkills.insert(skillName)
        case .fullyDisabled:
            disabledSkills.insert(skillName)
        case .nameOnly:
            throw PiVisibilityWriterError.unsupportedExposureLevel
        }

        document.hiddenSkills = hiddenSkills.sorted()
        document.disabledSkills = disabledSkills.sorted()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes: Data
        do {
            bytes = try encoder.encode(document)
        } catch {
            throw PiVisibilityWriterError.invalidConfiguration
        }

        do {
            try FileManager.default.createDirectory(
                at: configurationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try bytes.write(to: configurationURL, options: .atomic)
        } catch {
            throw PiVisibilityWriterError.fileOperationFailed
        }
    }

    private func readDocument() throws -> PiVisibilityDocument {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else { return .empty }
        let bytes: Data
        do {
            bytes = try Data(contentsOf: configurationURL)
        } catch {
            throw PiVisibilityWriterError.fileOperationFailed
        }
        do {
            let document = try JSONDecoder().decode(PiVisibilityDocument.self, from: bytes)
            guard document.isValid else { throw PiVisibilityWriterError.invalidConfiguration }
            return document
        } catch let error as PiVisibilityWriterError {
            throw error
        } catch {
            throw PiVisibilityWriterError.invalidConfiguration
        }
    }
}
