import Foundation

// L3 COORD: Pagugu/HostConfig/HostConfigWriter.swift
// INPUT: JSON 宿主配置路径、Pagugu 负责的非空 key path、目标 JSON 值或删除意图，以及 Registry Claim 映射后的期望值。
// OUTPUT: 只修改目标 key 的原子合并写、提交前漂移拒绝、`<file>.pagugu-backup` 单槽备份、备份恢复与实时一致/分歧派生。
// POS: HostConfig 模块的通用 JSON 写通道。does not own 具体宿主档位映射、Visibility Claim 持久化、UI 或文件监听。
// TEST: repo://PaguguTests/HostConfigWriterTests.swift。

/// 宿主配置 JSON 的类型安全值。未知配置经此类型解码并在合并写中保留。
indirect enum HostConfigValue: Codable, Equatable, Sendable {
    case object([String: HostConfigValue])
    case array([HostConfigValue])
    case string(String)
    case number(Decimal)
    case bool(Bool)
    case null

    private struct DynamicCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var object: [String: HostConfigValue] = [:]
            for key in container.allKeys {
                object[key.stringValue] = try container.decode(HostConfigValue.self, forKey: key)
            }
            self = .object(object)
            return
        }

        if var container = try? decoder.unkeyedContainer() {
            var array: [HostConfigValue] = []
            while !container.isAtEnd {
                array.append(try container.decode(HostConfigValue.self))
            }
            self = .array(array)
            return
        }

        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Decimal.self) {
            self = .number(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "不支持的 JSON 值"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .object(let object):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in object {
                try container.encode(value, forKey: DynamicCodingKey(stringValue: key)!)
            }
        case .array(let array):
            var container = encoder.unkeyedContainer()
            for value in array {
                try container.encode(value)
            }
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .number(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }
}

enum HostConfigClaimState: Equatable, Sendable {
    case consistent
    case divergent

    var hasDivergence: Bool { self == .divergent }
}

enum HostConfigWriterError: Error, Equatable, Sendable {
    case invalidKeyPath
    case invalidConfiguration
    case backupUnavailable
    case externallyModified
    case fileOperationFailed

    var recoverySuggestion: String {
        switch self {
        case .invalidKeyPath:
            return "请修正 Pagugu 的宿主配置映射后重试。"
        case .invalidConfiguration:
            return "请修复宿主 JSON 配置格式后重试。"
        case .backupUnavailable:
            return "当前没有可恢复的 Pagugu 写前备份。"
        case .externallyModified:
            return "宿主配置已被外部修改。请重新读取当前配置后显式重试。"
        case .fileOperationFailed:
            return "请检查配置目录与文件权限后重试。"
        }
    }
}

struct HostConfigWriter: Sendable {
    typealias BeforeCommitHook = @Sendable () throws -> Void

    private let beforeCommit: BeforeCommitHook

    init(beforeCommit: @escaping BeforeCommitHook = {}) {
        self.beforeCommit = beforeCommit
    }

    /// L4 IN: keyPath 必须非空且每段非空；value 为 nil 表示只删除该叶子 key。
    /// OUT: 写入前把原文件完整字节覆盖到固定单槽备份；随后原子替换目标文件。未知 JSON 值保持语义不变。
    /// FAIL: 原文件不可读、JSON 非对象、路径中间值非对象、备份或目标写失败时动作明确失败；备份失败时目标不写；提交前磁盘漂移时不备份、不覆写。
    /// L6 CHAIN: 实时读取并解析完整对象 → 只变更目标叶子 → 完整编码 → 提交前重读比对 → 原子覆盖单槽备份 → 原子替换目标。
    func merge(
        _ value: HostConfigValue?,
        at keyPath: [String],
        in configurationURL: URL
    ) throws {
        try validate(keyPath)
        let originalBytes = try readBytesIfPresent(at: configurationURL)
        let root = try decodeRoot(from: originalBytes)
        let updated = try replacing(value, at: ArraySlice(keyPath), in: root)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let updatedBytes: Data
        do {
            updatedBytes = try encoder.encode(updated)
        } catch {
            throw HostConfigWriterError.invalidConfiguration
        }

        try ensureParentDirectory(of: configurationURL)
        do {
            try beforeCommit()
        } catch {
            throw HostConfigWriterError.fileOperationFailed
        }
        guard try readBytesIfPresent(at: configurationURL) == originalBytes else {
            throw HostConfigWriterError.externallyModified
        }
        if let originalBytes {
            try writeAtomically(originalBytes, to: backupURL(for: configurationURL))
        }
        try writeAtomically(updatedBytes, to: configurationURL)
    }

    /// L4 OUT: 将固定单槽备份的完整字节原子覆盖回目标文件；备份本身保留。
    /// FAIL: 缺少备份时零副作用；读取或覆盖失败时返回稳定错误与恢复方向。
    func restoreBackup(for configurationURL: URL) throws {
        let backupURL = backupURL(for: configurationURL)
        guard let bytes = try readBytesIfPresent(at: backupURL) else {
            throw HostConfigWriterError.backupUnavailable
        }
        try ensureParentDirectory(of: configurationURL)
        try writeAtomically(bytes, to: configurationURL)
    }

    /// L4 IN: expecting 是 Registry Claim 经具体宿主 adapter 映射后的 JSON 期望值；nil 表示期望 key 不存在。
    /// OUT: 每次调用实时读盘，只比较目标 key；一致/分歧均为派生状态，不写 Registry 或配置。
    func claimState(
        expecting expectedValue: HostConfigValue?,
        at keyPath: [String],
        in configurationURL: URL
    ) throws -> HostConfigClaimState {
        try validate(keyPath)
        let root = try decodeRoot(from: readBytesIfPresent(at: configurationURL))
        let currentValue = try value(at: ArraySlice(keyPath), in: root)
        return currentValue == expectedValue ? .consistent : .divergent
    }

    private func validate(_ keyPath: [String]) throws {
        guard !keyPath.isEmpty, keyPath.allSatisfy({ !$0.isEmpty }) else {
            throw HostConfigWriterError.invalidKeyPath
        }
    }

    private func replacing(
        _ value: HostConfigValue?,
        at keyPath: ArraySlice<String>,
        in current: HostConfigValue
    ) throws -> HostConfigValue {
        guard case .object(var object) = current, let key = keyPath.first else {
            throw HostConfigWriterError.invalidConfiguration
        }
        let remaining = keyPath.dropFirst()
        if remaining.isEmpty {
            object[key] = value
            return .object(object)
        }

        let child = object[key] ?? .object([:])
        object[key] = try replacing(value, at: remaining, in: child)
        return .object(object)
    }

    private func value(
        at keyPath: ArraySlice<String>,
        in current: HostConfigValue
    ) throws -> HostConfigValue? {
        guard let key = keyPath.first else { return current }
        guard case .object(let object) = current else {
            throw HostConfigWriterError.invalidConfiguration
        }
        guard let child = object[key] else { return nil }
        let remaining = keyPath.dropFirst()
        return remaining.isEmpty ? child : try value(at: remaining, in: child)
    }

    private func decodeRoot(from bytes: Data?) throws -> HostConfigValue {
        guard let bytes else { return .object([:]) }
        do {
            let root = try JSONDecoder().decode(HostConfigValue.self, from: bytes)
            guard case .object = root else {
                throw HostConfigWriterError.invalidConfiguration
            }
            return root
        } catch let error as HostConfigWriterError {
            throw error
        } catch {
            throw HostConfigWriterError.invalidConfiguration
        }
    }

    private func readBytesIfPresent(at url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw HostConfigWriterError.fileOperationFailed
        }
    }

    private func ensureParentDirectory(of url: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw HostConfigWriterError.fileOperationFailed
        }
    }

    private func writeAtomically(_ bytes: Data, to url: URL) throws {
        do {
            try bytes.write(to: url, options: .atomic)
        } catch {
            throw HostConfigWriterError.fileOperationFailed
        }
    }

    private func backupURL(for configurationURL: URL) -> URL {
        configurationURL.appendingPathExtension("pagugu-backup")
    }
}
