import XCTest
@testable import Pagugu

final class PaguguTests: XCTestCase {
    func testProductIdentity() {
        XCTAssertEqual(AppIdentity.displayName, "Pagugu")
        XCTAssertEqual(AppIdentity.bundleIdentifier, "com.dimon.pagugu")
    }
}
