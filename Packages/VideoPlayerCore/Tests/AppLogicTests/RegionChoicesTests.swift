import XCTest
@testable import AppLogic

/// R334: Settings > Online Lookup's Region is a picker of ISO 3166-1 alpha-2 country codes.
final class RegionChoicesTests: XCTestCase {
    private let names: [String: String] = ["US": "United States", "DE": "Germany", "GB": "United Kingdom", "AT": "Austria"]

    func testOnlyTwoLetterCodesOnceSortedByName() {
        let options: [RegionOption] = RegionChoices.options(codes: ["US", "001", "150", "de", "GB", "DE", "AT"], current: "US") { self.names[$0] }
        XCTAssertEqual(options.map(\.code), ["AT", "DE", "GB", "US"], "no UN M.49 numbers, no duplicates, sorted by name")
        XCTAssertEqual(options.map(\.title), ["Austria", "Germany", "United Kingdom", "United States"])
    }

    func testTheCurrentRegionIsAlwaysAnAnswer() {
        let options: [RegionOption] = RegionChoices.options(codes: ["DE"], current: "nz") { self.names[$0] }
        XCTAssertEqual(Set(options.map(\.code)), ["DE", "NZ"], "a stored code the system list lacks is kept")
        XCTAssertEqual(options.first { $0.code == "NZ" }?.title, "NZ", "no system name: the code")
        let fallback: [RegionOption] = RegionChoices.options(codes: ["DE"], current: "USA") { self.names[$0] }
        XCTAssertTrue(fallback.contains { $0.code == OnlineLookupPrefs.defaultRegion }, "an invalid stored value shows as the default")
    }

    func testCountryCodeShape() {
        for good in ["US", "DE", "GB"] { XCTAssertTrue(RegionChoices.isCountryCode(good), good) }
        for bad in ["", "U", "USA", "us", "001", "1A", "É1"] { XCTAssertFalse(RegionChoices.isCountryCode(bad), bad) }
    }

    func testRegionRowTextsAndThatItIsNotSent() {
        XCTAssertEqual(OnlineLookupText.regionLabel, "Region")
        XCTAssertTrue(OnlineLookupText.regionHelp.contains("it is not sent"))
        XCTAssertFalse(OnlineLookupText.regionHelp.contains("two-letter"), "nothing is typed any more")
    }
}
