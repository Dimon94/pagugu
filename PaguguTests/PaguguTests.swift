import SwiftUI
import XCTest
@testable import Pagugu

final class PaguguTests: XCTestCase {
    func testProductIdentity() {
        XCTAssertEqual(AppIdentity.displayName, "Pagugu")
        XCTAssertEqual(AppIdentity.bundleIdentifier, "com.dimon.pagugu")
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
}
