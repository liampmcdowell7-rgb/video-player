import XCTest
@testable import ScreenChecks

/// R471 (62), PROVISIONAL (owner 25 Nov 2026 round 6, Part B item 3): R349's clear top of the hero (0.35 of its height) is
/// kept as the cover's starting point before the text is measured, in one place. The backdrop no longer declares a second,
/// unused copy of it. Structure only, from the source: nothing is compiled or run on tvOS.
extension ScreenChecksTests {
    func testTheHeroClearTopLivesInOnePlace() throws {
        guard let backdrop = try appSource("App/Shared/BackdropView.swift") else { return }
        XCTAssertFalse(backdrop.contains("heroClearTop"), "no unused copy of the clear top")
        XCTAssertTrue(backdrop.contains("ArtReadability.coverStart(textTop:"), "the hero cover starts where the readability rule says")
        guard let rule = try appSource("Packages/VideoPlayerCore/Sources/AppLogic/ArtReadability.swift") else { return }
        XCTAssertTrue(rule.contains("public static let fallbackStart: Double = 0.35"), "R349's share, until the text is measured")
    }
}
