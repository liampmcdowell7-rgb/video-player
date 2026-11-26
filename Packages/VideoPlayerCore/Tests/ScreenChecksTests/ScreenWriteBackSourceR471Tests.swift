import XCTest
@testable import ScreenChecks

/// R471 (72), PROVISIONAL (owner 25 Nov 2026 round 8, Part B item 3, finding D): the detail page reads the header and Fix
/// Match searches outside `ScreenModel.run`, and apply the answer in a run with no wait. Structure only, from the source.
extension ScreenChecksTests {
    func testTheHeaderReadAndTheMatchSearchDoNotWriteAnOlderCopyBack() throws {
        guard let detail = try appSource("App/Features/Detail/ItemDetailView.swift"),
              let fix = try appSource("App/Features/FixMatch/FixMatchView.swift") else { return }
        XCTAssertFalse(detail.contains("run { await $0.loadTrackDetails() }"), "no copy of the page held across the read")
        XCTAssertTrue(detail.contains("if let read = await model?.screen.readTrackDetails() {"))
        XCTAssertTrue(detail.contains("await model?.run { $0.applyTrackDetails(read) }"))
        XCTAssertFalse(fix.contains("run { await $0.search(typed) }"), "no copy of the model held across the search")
        XCTAssertTrue(fix.contains("await model?.run { asked = $0.beginSearch(typed) }"))
        XCTAssertTrue(fix.contains("guard let asked, let found = await model?.screen.findMatches(asked) else { return }"))
        XCTAssertTrue(fix.contains("await model?.run { $0.finishSearch(found) }"))
    }
}
