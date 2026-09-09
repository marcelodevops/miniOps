import XCTest
@testable import MiniOpsCore

final class MiniOpsCoreTests: XCTestCase {
    func testInfo() {
        XCTAssertEqual(MiniOpsCoreInfo.name, "MiniOpsCore")
    }
}
