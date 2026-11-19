// Fixture for scripts/test-counts-tests.sh (never compiled): a test class name used in two targets.
import XCTest

final class SharedNameTests: XCTestCase {
    func testOne() {}
}

final class AlphaOnlyTests: XCTestCase {
    func testOne() {}
}

/// A helper class with the same name in both targets is not a test class and is not reported.
final class Locked {}
