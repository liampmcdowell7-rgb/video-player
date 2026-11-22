import XCTest
@testable import AppLogic

/// R353 (item 4 of the 15): Online Lookup's Region opened a blank page. The page lists `RegionChoices.options`; these
/// cases check that the list it gets is never empty and every row has a title, whatever the system passes.
final class RegionPageNeverBlankTests: XCTestCase {
    func testAnEmptySystemListStillGivesTheCurrentRegion() {
        let options: [RegionOption] = RegionChoices.options(codes: [], current: "DE") { _ in nil }
        XCTAssertEqual(options, [RegionOption(code: "DE", title: "DE")])
    }

    func testAnEmptySystemListAndAnInvalidStoredValueGiveTheDefault() {
        let options: [RegionOption] = RegionChoices.options(codes: [], current: "") { _ in nil }
        XCTAssertEqual(options.map(\.code), [OnlineLookupPrefs.defaultRegion])
    }

    func testAnEmptyNameFallsBackToTheCode() {
        let options: [RegionOption] = RegionChoices.options(codes: ["FR"], current: "FR") { _ in "" }
        XCTAssertEqual(options.first?.title, "FR", "a row never has an empty title")
    }

    func testEveryRowHasATitleAndAValidUniqueCode() {
        let codes: [String] = ["US", "us", "DE", "001", "419", "GB", "XK", ""]
        let options: [RegionOption] = RegionChoices.options(codes: codes, current: " gb ") { $0 == "US" ? "United States" : nil }
        XCTAssertFalse(options.isEmpty)
        XCTAssertEqual(Set(options.map(\.id)).count, options.count, "ids are unique, so the list draws every row")
        for option in options {
            XCTAssertTrue(RegionChoices.isCountryCode(option.code), option.code)
            XCTAssertFalse(option.title.isEmpty, option.code)
        }
        XCTAssertTrue(options.contains { $0.code == "GB" }, "the stored value is trimmed and upper-cased")
    }

    func testEqualNamesAreOrderedByCode() {
        let options: [RegionOption] = RegionChoices.options(codes: ["ZA", "AB"], current: "ZA") { _ in "Same" }
        XCTAssertEqual(options.map(\.code), ["AB", "ZA"])
    }
}
