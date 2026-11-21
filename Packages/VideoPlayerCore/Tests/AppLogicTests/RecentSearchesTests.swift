import XCTest
@testable import AppLogic

/// R343: recent searches, kept on this Apple TV only.
final class RecentSearchesTests: XCTestCase {
    func testTheNewestComesFirstOnceAndTheListIsCapped() {
        var list: [String] = []
        for q in ["sample", "Movie", "  SAMPLE  ", "x"] { list = RecentSearches.recording(q, in: list) }
        XCTAssertEqual(list, ["SAMPLE", "Movie"], "trimmed, once, newest spelling first, one letter not kept")
        for n in 1...20 { list = RecentSearches.recording("search \(n)", in: list) }
        XCTAssertEqual(list.count, RecentSearches.limit)
        XCTAssertEqual(list.first, "search 20")
    }

    func testTheStoredValueRoundTrips() {
        let list = ["one", "two words", "three"]
        XCTAssertEqual(RecentSearches.decode(RecentSearches.encode(list)), list)
        XCTAssertEqual(RecentSearches.decode(RecentSearches.encode(["a\nb"])), ["a b"])
        XCTAssertEqual(RecentSearches.decode(""), [])
    }

    func testTheyShowOnlyWhileNothingIsTyped() {
        XCTAssertEqual(RecentSearches.shown(["a1"], query: ""), ["a1"])
        XCTAssertEqual(RecentSearches.shown(["a1"], query: " "), ["a1"])
        XCTAssertEqual(RecentSearches.shown(["a1"], query: "s"), [])
    }

    func testTheKeyIsNotASyncedSetting() {
        XCTAssertNil(SettingsKey(rawValue: RecentSearches.defaultsKey), "never one of the settings that the essentials copy keeps")
        XCTAssertEqual(RecentSearches.clearTitle, "Clear Recent Searches")
    }
}
