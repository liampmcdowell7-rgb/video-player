import XCTest
@testable import VideoPlayerCore

final class AppInfoTests: XCTestCase {
    func testVersionIsNotEmpty() {
        XCTAssertFalse(AppInfo.version.isEmpty)
    }
}
