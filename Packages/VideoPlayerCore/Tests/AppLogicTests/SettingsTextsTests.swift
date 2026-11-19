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
        XCTAssertTrue(SettingsTexts.skipFull.hasPrefix("Skip buttons and the next-episode card appear only"))
        XCTAssertTrue(SettingsTexts.skipFull.contains("Markers from online lookups or from analysing the video are not available yet."))
        XCTAssertTrue(SettingsTexts.trueHDFull.contains("which is lossy. Applies to the next title you play."))
        XCTAssertTrue(SettingsTexts.accessibilityFull.contains("This app follows them and has no separate copies."))
        for note in [OnlineLookupText.keysAreOptional, OnlineLookupText.storage, OnlineLookupText.removeNote] {
            XCTAssertTrue(SettingsTexts.aboutKeysFull.contains(note), note)
        }
    }

    /// The short "What Is Sent" footer must not promise less than the full page says: nothing is sent without a key.
    func testTheShortWhatIsSentAgreesWithTheFullText() {
        XCTAssertTrue(SettingsTexts.whatIsSentShort.hasPrefix("Nothing is sent until you enter a key."))
        XCTAssertTrue(OnlineLookupText.whatIsSent.hasPrefix("Nothing is sent to any online service until you enter a key below."))
        // #15 3.5 and 9.5: the full text says that title logos are downloaded too, and how to stop it.
        XCTAssertTrue(OnlineLookupText.whatIsSent.contains("title logos"))
        XCTAssertTrue(OnlineLookupText.whatIsSent.contains("Show Title Logos is on in Settings > Library"))
    }
}
