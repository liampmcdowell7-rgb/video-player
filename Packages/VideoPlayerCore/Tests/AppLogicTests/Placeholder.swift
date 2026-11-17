import XCTest
@testable import AppLogic

final class PlaceholderTests: XCTestCase {
    func testModuleName() { XCTAssertEqual(AppLogicModule.name, "AppLogic") }
}
