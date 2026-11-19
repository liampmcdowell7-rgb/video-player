import Foundation
import XCTest
@testable import MixedFixture

/// scripts/test-core-tests.sh runs this package twice: once as is (one pass, one skip), once with VP_FIXTURE_FAIL=1 (one
/// pass, one skip, one failure). test-core.sh must exit 0 the first time and non-zero the second.
final class MixedFixtureTests: XCTestCase {
    func testPasses() {
        XCTAssertEqual(fixtureSum(2, 3), 5)
    }

    func testIsSkipped() throws {
        throw XCTSkip("fixture: always skipped, must be reported as skipped and never fail the run")
    }

    func testFailsOnlyWhenAsked() {
        if ProcessInfo.processInfo.environment["VP_FIXTURE_FAIL"] == "1" {
            XCTFail("fixture: deliberate failure")
        }
    }
}
