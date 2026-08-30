import Foundation

// L3 COORD: Pagugu/HostConfig/HostConfigWriter.swift
// INPUT: 宿主配置路径、Pagugu-owned 局部字节变换；JSON 通道另接收非空 key path、目标值或删除意图。
// OUTPUT: 提交前漂移拒绝、原子替换、单动作多文件 `<file>.pagugu-backup` 快照/缺失标记备份与恢复；JSON key-path 合并和实时分歧派生。
// POS: HostConfig 模块的通用文件提交机制与 JSON 写通道。does not own TOML/YAML 协议、具体宿主档位映射、Visibility Claim、UI 或监听。
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
    case unsupportedExposureLevel
    case effectiveConfigurationMismatch
    case backupUnavailable
    case externallyModified
    case fileOperationFailed

    var recoverySuggestion: String {
        switch self {
        case .invalidKeyPath:
            return "请修正 Pagugu 的宿主配置映射后重试。"
        case .invalidConfiguration:
            return "请修复宿主配置格式后重试。"
        case .unsupportedExposureLevel:
            return "请选择该 Agent Host 支持的调用面档位后重试。"
        case .effectiveConfigurationMismatch:
            return "当前宿主配置无法达到所选档位。请检查更高优先级配置，或采用磁盘配置。"
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
    /// OUT: 写入前把原文件完整字节或「原本不存在」状态覆盖到固定单槽备份；随后原子替换目标文件。未知 JSON 值保持语义不变。
    /// FAIL: 原文件不可读、JSON 非对象、路径中间值非对象、备份或目标写失败时动作明确失败；备份失败时目标不写；提交前磁盘漂移时不备份、不覆写。
    /// L6 CHAIN: 实时读取并解析完整对象 → 只变更目标叶子 → 完整编码 → 提交前重读比对 → 原子覆盖单槽备份 → 原子替换目标。
    func merge(
        _ value: HostConfigValue?,
        at keyPath: [String],
        in configurationURL: URL
    ) throws {
        try validate(keyPath)
        try rewriteConfiguration(at: configurationURL) { originalBytes in
            let root = try decodeRoot(from: originalBytes)
            let updated = try replacing(value, at: ArraySlice(keyPath), in: root)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                return try encoder.encode(updated)
            } catch {
                throw HostConfigWriterError.invalidConfiguration
            }
        }
    }

    /// L4 IN: transform 接收首次实时读取的完整字节；nil 返回表示该文件无需写入。
    /// OUT: 只提交 transform 产出的完整字节；提交前重读防漂移，未漂移才备份并原子替换。
    /// FAIL: 读取、transform、备份或目标替换失败时不冒充成功；漂移时不生成备份、不覆盖外部写入。
    func rewriteConfiguration(
        at configurationURL: URL,
        transform: (Data?) throws -> Data?
    ) throws {
        try rewriteConfigurations(at: [configurationURL]) { _, originalBytes in
            try transform(originalBytes)
        }
    }

    /// L4 IN: configurationURLs 必须非空且不重复；transform 分别接收同一动作开始时的逐文件完整字节。
    /// OUT: 任一文件需变更时，先把动作涉及的全部现存文件快照到各自单槽备份，再逐文件原子提交变更。
    /// FAIL: 任一 transform 失败或任一文件在提交前漂移时全部目标零写入；提交中断时保留同动作备份供显式恢复。
    /// L6 CHAIN: 一次读取全部文件 → 产出全部局部变换 → 一次 hook → 全部重读防漂移 → 全部快照备份 → 逐文件原子替换。
    func rewriteConfigurations(
        at configurationURLs: [URL],
        transform: (URL, Data?) throws -> Data?
    ) throws {
        guard !configurationURLs.isEmpty,
              Set(configurationURLs).count == configurationURLs.count else {
            throw HostConfigWriterError.invalidConfiguration
        }

        let snapshots = try configurationURLs.map { configurationURL in
            ConfigurationSnapshot(
                url: configurationURL,
                originalBytes: try readBytesIfPresent(at: configurationURL)
            )
        }
        let rewrites = try snapshots.compactMap { snapshot -> ConfigurationRewrite? in
            guard let updatedBytes = try transform(snapshot.url, snapshot.originalBytes),
                  updatedBytes != snapshot.originalBytes else {
                return nil
            }
            return ConfigurationRewrite(url: snapshot.url, updatedBytes: updatedBytes)
        }
        guard !rewrites.isEmpty else { return }

        for snapshot in snapshots {
            try ensureParentDirectory(of: snapshot.url)
        }
        do {
            try beforeCommit()
        } catch {
            throw HostConfigWriterError.fileOperationFailed
        }
        for snapshot in snapshots {
            guard try readBytesIfPresent(at: snapshot.url) == snapshot.originalBytes else {
                throw HostConfigWriterError.externallyModified
            }
        }
        for snapshot in snapshots {
            try ensureParentDirectory(of: snapshot.url)
            if let originalBytes = snapshot.originalBytes {
                try writeAtomically(originalBytes, to: backupURL(for: snapshot.url))
                try removeIfPresent(at: missingBackupMarkerURL(for: snapshot.url))
            } else {
                try writeAtomically(Data(), to: missingBackupMarkerURL(for: snapshot.url))
                try removeIfPresent(at: backupURL(for: snapshot.url))
            }
        }
        for rewrite in rewrites {
            try ensureParentDirectory(of: rewrite.url)
            try writeAtomically(rewrite.updatedBytes, to: rewrite.url)
        }
    }

    /// L4 OUT: 将固定单槽备份的完整字节原子覆盖回目标文件；缺失标记则删除 Pagugu 创建的目标。备份状态保留。
    /// FAIL: 缺少备份状态时零副作用；读取、覆盖或删除失败时返回稳定错误与恢复方向。
    func restoreBackup(for configurationURL: URL) throws {
        try restoreBackups(for: [configurationURL])
    }

    /// L4 OUT: 一次动作恢复全部现存单槽备份；没有任何备份状态时明确失败。目标原子覆盖或删除，备份状态保留。
    func restoreBackups(for configurationURLs: [URL]) throws {
        let uniqueURLs = Array(Set(configurationURLs)).sorted { $0.path < $1.path }
        let restorable = try uniqueURLs.compactMap { configurationURL -> ConfigurationBackup? in
            let hasMissingMarker = FileManager.default.fileExists(
                atPath: missingBackupMarkerURL(for: configurationURL).path
            )
            let backupBytes = try readBytesIfPresent(at: backupURL(for: configurationURL))
            guard !(hasMissingMarker && backupBytes != nil) else {
                throw HostConfigWriterError.fileOperationFailed
            }
            if hasMissingMarker { return .missing(configurationURL) }
            return backupBytes.map { .bytes(configurationURL, $0) }
        }
        guard !restorable.isEmpty else {
            throw HostConfigWriterError.backupUnavailable
        }
        for backup in restorable {
            switch backup {
            case .bytes(let configurationURL, let bytes):
                try ensureParentDirectory(of: configurationURL)
                try writeAtomically(bytes, to: configurationURL)
            case .missing(let configurationURL):
                try removeIfPresent(at: configurationURL)
            }
        }
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

    private struct ConfigurationSnapshot {
        let url: URL
        let originalBytes: Data?
    }

    private struct ConfigurationRewrite {
        let url: URL
        let updatedBytes: Data
    }

    private enum ConfigurationBackup {
        case bytes(URL, Data)
        case missing(URL)
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

    private func removeIfPresent(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw HostConfigWriterError.fileOperationFailed
        }
    }

    private func backupURL(for configurationURL: URL) -> URL {
        configurationURL.appendingPathExtension("pagugu-backup")
    }

    private func missingBackupMarkerURL(for configurationURL: URL) -> URL {
        configurationURL.appendingPathExtension("pagugu-backup-missing")
    }
}
