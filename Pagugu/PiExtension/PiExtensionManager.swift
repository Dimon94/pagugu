import Foundation

// L3 COORD: Pagugu/PiExtension/PiExtensionManager.swift
// INPUT: App Bundle 内的 Pagugu Pi 扩展资产、目标 ~/.pi/agent/extensions/pagugu-visibility/index.ts 与版本常量。
// OUTPUT: 缺失/不兼容/健康投影，以及幂等原子安装或升级。
// POS: PiExtension 模块的交付物生命周期 owner。does not own visibility.json、Registry Claim、UI 或 Pi reload。
// TEST: repo://PaguguTests/PiExtensionHealthTests.swift。

enum PiExtensionHealth: Equatable, Sendable {
    case healthy
    case missing
    case incompatible(installedVersion: String?)
    case unreadable

    var allowsVisibilityWrites: Bool { self == .healthy }

    var recoverySuggestion: String? {
        switch self {
        case .healthy:
            return nil
        case .missing:
            return "Pi 扩展尚未安装。请安装/更新 Pi 扩展后再切换档位。"
        case .incompatible:
            return "Pi 扩展版本不兼容。请更新 Pi 扩展后再切换档位。"
        case .unreadable:
            return "无法读取 Pi 扩展。请检查文件权限，再安装/更新 Pi 扩展。"
        }
    }
}

enum PiExtensionManagerError: Error, Equatable, Sendable {
    case sourceAssetUnavailable
    case invalidSourceAsset
    case fileOperationFailed

    var recoverySuggestion: String {
        switch self {
        case .sourceAssetUnavailable, .invalidSourceAsset:
            return "Pagugu 内置 Pi 扩展资产不可用。请重新安装 Pagugu 后重试。"
        case .fileOperationFailed:
            return "请检查 ~/.pi/agent/extensions 目录与扩展文件权限后重试。"
        }
    }
}

struct PiExtensionManager: Sendable {
    static let currentVersion = "1"
    private static let versionPrefix = "export const PAGUGU_PI_EXTENSION_VERSION = \""

    private let sourceURL: URL?
    private let installationURL: URL

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        sourceURL: URL? = Bundle.main.url(forResource: "index", withExtension: "ts")
    ) {
        self.sourceURL = sourceURL
        installationURL = homeDirectory.standardizedFileURL
            .appendingPathComponent(".pi/agent/extensions/pagugu-visibility/index.ts")
    }

    /// L4 OUT: 只按已安装文件内嵌版本常量派生实时健康；缺失与读取失败不冒充兼容。
    func health() -> PiExtensionHealth {
        guard FileManager.default.fileExists(atPath: installationURL.path) else { return .missing }
        let contents: String
        do {
            contents = try String(contentsOf: installationURL, encoding: .utf8)
        } catch {
            return .unreadable
        }
        let installedVersion = Self.version(in: contents)
        return installedVersion == Self.currentVersion
            ? .healthy
            : .incompatible(installedVersion: installedVersion)
    }

    /// L4 OUT: 将 Bundle 资产原子复制到固定自动发现路径；内容已一致时 no-op 并返回 false。
    /// FAIL: 资产缺失/版本常量不匹配或目标写失败时保留现有扩展并返回稳定恢复方向。
    func installOrUpdate() throws -> Bool {
        guard let sourceURL else { throw PiExtensionManagerError.sourceAssetUnavailable }
        let sourceBytes: Data
        let sourceContents: String
        do {
            sourceBytes = try Data(contentsOf: sourceURL)
            guard let decoded = String(data: sourceBytes, encoding: .utf8) else {
                throw PiExtensionManagerError.invalidSourceAsset
            }
            sourceContents = decoded
        } catch let error as PiExtensionManagerError {
            throw error
        } catch {
            throw PiExtensionManagerError.sourceAssetUnavailable
        }
        guard Self.version(in: sourceContents) == Self.currentVersion else {
            throw PiExtensionManagerError.invalidSourceAsset
        }
        if let installedBytes = try? Data(contentsOf: installationURL), installedBytes == sourceBytes {
            return false
        }
        do {
            try FileManager.default.createDirectory(
                at: installationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try sourceBytes.write(to: installationURL, options: .atomic)
            return true
        } catch {
            throw PiExtensionManagerError.fileOperationFailed
        }
    }

    private static func version(in contents: String) -> String? {
        guard let prefixRange = contents.range(of: versionPrefix) else { return nil }
        let remainder = contents[prefixRange.upperBound...]
        guard let suffixRange = remainder.range(of: "\";") else { return nil }
        let version = String(remainder[..<suffixRange.lowerBound])
        return version.isEmpty ? nil : version
    }
}
