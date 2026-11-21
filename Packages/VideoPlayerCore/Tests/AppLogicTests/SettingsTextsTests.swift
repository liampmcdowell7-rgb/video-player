import XCTest
@testable import AppLogic

/// #15 Part 3, rule L5: short footers, and the long texts moved unchanged to "Learn More" pages.
final class SettingsTextsTests: XCTestCase {
    func testShortFootersStayWithinTwoLines() {
        for footer in SettingsTexts.shortFooters {
            XCTAssertLessThanOrEqual(footer.count, SettingsTexts.shortFooterLimit, footer)
            XCTAssertLessThanOrEqual(footer.components(separatedBy: ". ").count, 2, "at most two sentences: \(footer)")
        }
        for summary in [SettingsTexts.rootSummary, SettingsTexts.playbackSummary, SettingsTexts.homeSummary,
                        SettingsTexts.sourcesSummary, SettingsTexts.librarySummary, SettingsTexts.storageSummary,
                        SettingsTexts.accessibilitySummary, SettingsTexts.aboutSummary, SettingsTexts.onlineSummary] {
            XCTAssertLessThanOrEqual(summary.count, SettingsTexts.shortFooterLimit, summary)
        }
    }

    func testTheLongTextsAreKeptWordForWord() {
        // R314 to R316: the text says where markers come from now, and that the comparison stays on the Apple TV.
        XCTAssertTrue(SettingsTexts.skipFull.hasPrefix("Skip buttons and automatic skips need"))
        XCTAssertTrue(SettingsTexts.skipFull.contains("nothing about it is sent anywhere"))
        XCTAssertFalse(SettingsTexts.skipFull.contains("not available yet"))
        XCTAssertTrue(SettingsTexts.trueHDFull.contains("which is lossy. Applies to the next title you play."))
        XCTAssertTrue(SettingsTexts.accessibilityFull.contains("This app follows them and has no separate copies."))
        for note in [OnlineLookupText.keysAreOptional, OnlineLookupText.storage, OnlineLookupText.removeNote] {
            XCTAssertTrue(SettingsTexts.aboutKeysFull.contains(note), note)
        }
    }

    /// The short "What Is Sent" footer must not promise less than the full page says: nothing is sent without a key or Free Data Sources.
    func testTheShortWhatIsSentAgreesWithTheFullText() {
        XCTAssertTrue(SettingsTexts.whatIsSentShort.hasPrefix("Nothing is sent until you add a key or turn on Free Data Sources."))
        XCTAssertTrue(OnlineLookupText.whatIsSent.hasPrefix("Nothing is sent to any online service until you enter a key or turn on Free Data Sources below."))
        // #15 3.5 and 9.5: the full text says that title logos are downloaded too, and how to stop it.
        XCTAssertTrue(OnlineLookupText.whatIsSent.contains("title logos"))
        XCTAssertTrue(OnlineLookupText.whatIsSent.contains("Show Title Logos is on in Settings > Library"))
    }
}
