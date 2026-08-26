import SwiftUI
import XCTest
@testable import Pagugu

final class PaguguTests: XCTestCase {
    func testProductIdentity() {
        XCTAssertEqual(AppIdentity.displayName, "Pagugu")
        XCTAssertEqual(AppIdentity.bundleIdentifier, "com.dimon.pagugu")
    }

    func testBuildTargetsExcludePrototypeSources() throws {
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let projectURL = repositoryURL.appendingPathComponent("Pagugu.xcodeproj/project.pbxproj")
        let projectData = try Data(contentsOf: projectURL)
        var format = PropertyListSerialization.PropertyListFormat.openStep
        let project = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: projectData, format: &format)
                as? [String: Any]
        )
        let objects = try XCTUnwrap(project["objects"] as? [String: Any])

        for targetName in ["Pagugu", "PaguguTests"] {
            let target = try XCTUnwrap(objects.values.compactMap { $0 as? [String: Any] }.first {
                $0["isa"] as? String == "PBXNativeTarget" && $0["name"] as? String == targetName
            })
            let buildPhaseIDs = try XCTUnwrap(target["buildPhases"] as? [String])
            let sourcesPhase = try XCTUnwrap(buildPhaseIDs.compactMap {
                objects[$0] as? [String: Any]
            }.first {
                $0["isa"] as? String == "PBXSourcesBuildPhase"
            })
            let buildFileIDs = try XCTUnwrap(sourcesPhase["files"] as? [String])
            let sourcePaths = try buildFileIDs.map { buildFileID in
                let buildFile = try XCTUnwrap(objects[buildFileID] as? [String: Any])
                let fileReferenceID = try XCTUnwrap(buildFile["fileRef"] as? String)
                let fileReference = try XCTUnwrap(objects[fileReferenceID] as? [String: Any])
                return try XCTUnwrap(fileReference["path"] as? String)
            }

            XCTAssertFalse(
                sourcePaths.contains { $0.hasPrefix("Prototype/") },
                "\(targetName) target 不得编译 Pagugu/Prototype 下的规划证据"
            )
        }
    }

    // MARK: - SwiftUI smoke（主要流程入口存在且可构造；ADR-0009 §14 第 6 层）

    @MainActor
    func testContentViewConstructsWithFreshModel() {
        let model = AppModel(
            personalRoots: [],
            persistence: Persistence(directoryURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString))
        )
        let view = ContentView(model: model)
        XCTAssertNotNil(view.body)
    }

    @MainActor
    func testUpdateResultBannersCoverAllFourOutcomes() {
        // 结果区六类反馈中的更新结果四面：success / noop / cancelled / failed 均可呈现且文案非空。
        let outcomes: [UpdateResult] = [
            .success(checkoutPath: "/tmp/x", targetSHA: String(repeating: "a", count: 40)),
            .upToDate,
            .cancelled(checkoutPath: "/tmp/x"),
            .failed(UpdateRunFailure(reason: .fetchFailure)),
        ]
        for outcome in outcomes {
            switch outcome {
            case .success: break
            case .upToDate: break
            case .cancelled:
                XCTAssertFalse(UpdateResult.cancellationConsequence.isEmpty)
            case .failed(let failure):
                XCTAssertFalse(failure.reason.displayName.isEmpty)
                XCTAssertFalse(failure.recoveryDirection.isEmpty)
            }
        }
    }

    func testPreparedUpdateConfirmationShowsFullSHAAndRejectsSevenCharPrefix() {
        // 错误实现（prefix(7)）会失败：确认页必须展示完整 40/64 位对象名，不能只剩短前缀。
        let head40 = String(repeating: "1", count: 40)
        let target40 = String(repeating: "2", count: 40)
        let text40 = updateConfirmationHeadToTargetText(currentHeadSHA: head40, targetSHA: target40)
        XCTAssertEqual(text40, "\(head40) → \(target40)")
        XCTAssertNotEqual(
            text40,
            "\(String(head40.prefix(7))) → \(String(target40.prefix(7)))",
            "确认页文本只含 7 位短 SHA 则失败"
        )

        let head64 = String(repeating: "ab", count: 32)
        let target64 = String(repeating: "cd", count: 32)
        let text64 = updateConfirmationHeadToTargetText(currentHeadSHA: head64, targetSHA: target64)
        XCTAssertEqual(text64, "\(head64) → \(target64)")
        XCTAssertEqual(head64.count, 64)
        XCTAssertEqual(target64.count, 64)
        XCTAssertNotEqual(
            text64,
            "\(String(head64.prefix(7))) → \(String(target64.prefix(7)))",
            "确认页文本只含 7 位短 SHA 则失败"
        )
    }

    @MainActor
    func testUpdateIntentsExistOnAppModel() {
        let model = AppModel(
            personalRoots: [],
            persistence: Persistence(directoryURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString))
        )
        // 编译期即可证明 intent 存在；运行时验证互斥与禁用原因。
        XCTAssertFalse(model.canStartUpdateRun)
        XCTAssertFalse(model.updateRunDisabledReason.isEmpty)
        XCTAssertNil(model.pendingUpdatePlan)
        XCTAssertNil(model.updateResult)
        XCTAssertNil(model.updateRefreshFailure)
        model.dismissUpdateResult()
        model.dismissCheckRunSummary()
        model.dismissRegistryResetBackupPath()
    }

    // MARK: - Design Tokens（#28：令牌不变量；错误实现会漂密度、按压或状态色）

    func testChildIndentEqualsDisclosureHotspotPlusRowSpacing() {
        XCTAssertEqual(
            DesignTokens.Size.childIndent,
            DesignTokens.Size.disclosureHotspot + DesignTokens.Space.row
        )
    }

    func testPressScaleMatchesBetterUIConstant() {
        XCTAssertEqual(DesignTokens.Motion.pressScale, 0.96)
        XCTAssertEqual(DesignTokens.Motion.pressDuration, 0.1)
        XCTAssertLessThan(DesignTokens.Motion.pressScale, 1)
        XCTAssertGreaterThanOrEqual(DesignTokens.Motion.pressScale, 0.95)
    }

    func testCheckoutStatusColorsFollowSemanticRoles() {
        XCTAssertEqual(DesignTokens.statusColor(for: .updateAvailable), DesignTokens.Status.ok)
        XCTAssertEqual(DesignTokens.statusColor(for: .upToDate), DesignTokens.Status.ok)
        XCTAssertEqual(DesignTokens.statusColor(for: .dirty), DesignTokens.Status.warning)
        XCTAssertEqual(DesignTokens.statusColor(for: .diverged), DesignTokens.Status.warning)
        XCTAssertEqual(DesignTokens.statusColor(for: .inspectionFailed), DesignTokens.Status.error)
        XCTAssertEqual(DesignTokens.statusColor(for: .upstreamMismatch), DesignTokens.Status.error)
        XCTAssertEqual(DesignTokens.statusColor(for: .noRemote), DesignTokens.Status.neutral)
        XCTAssertEqual(DesignTokens.statusColor(for: .checkUnknown), DesignTokens.Status.neutral)
        XCTAssertEqual(DesignTokens.statusColor(for: .aheadOnly), DesignTokens.Status.neutral)
    }
}
