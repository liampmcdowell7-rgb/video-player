import XCTest
import VideoPlayerCore
import UserData
@testable import AppLogic

/// R333: Settings > Online Lookup's key (36) and the Move cover (66) as value rows with entry pages (`TextEntryRow`).
final class TextEntryRulesTests: XCTestCase {
    func testSecretRowNeverShowsTheKeyOrItsLength() {
        let key: String = "abcdef0123456789abcdef0123456789"
        XCTAssertEqual(TextEntryRules.rowValue(key, isSecret: true), String(repeating: "\u{2022}", count: 8))
        XCTAssertEqual(TextEntryRules.rowValue("ab", isSecret: true), String(repeating: "\u{2022}", count: 8), "same dots for any length")
        XCTAssertFalse(TextEntryRules.rowValue(key, isSecret: true).contains("6789"))
        XCTAssertEqual(TextEntryRules.rowValue("", isSecret: true), "", "nothing typed: nothing trailing")
        XCTAssertEqual(TextEntryRules.spokenValue(key, isSecret: true), "Entered")
        XCTAssertEqual(TextEntryRules.spokenValue("", isSecret: true), "")
    }

    func testPlainRowShowsTheValue() {
        XCTAssertEqual(TextEntryRules.rowValue("Sample Show", isSecret: false), "Sample Show")
        XCTAssertEqual(TextEntryRules.rowValue("", isSecret: false), "")
        XCTAssertEqual(TextEntryRules.spokenValue("2024", isSecret: false), "2024")
    }

    func testKeyEntryIsASecretTypedAsIs() {
        let entry: SourceFieldEntry = TextEntryRules.keyEntry
        XCTAssertTrue(entry.isSecret)
        XCTAssertEqual(entry.keyboard, .standard)
        XCTAssertEqual(entry.content, .none, "no saved passwords offered for an API key")
        XCTAssertFalse(entry.capitalizesWords)
        XCTAssertFalse(entry.autocorrects)
        XCTAssertEqual(TextEntryRules.keySummary("TMDB"), "Type the TMDB key on the keyboard.")
    }

    func testMoveFieldsPerKind() {
        XCTAssertEqual(TextEntryRules.moveFields(.movie), [.title, .year])
        XCTAssertEqual(TextEntryRules.moveFields(.episode), [.title, .year, .season, .episode, .episodeEnd])
        XCTAssertEqual(TextEntryRules.moveFields(.movie).map { TextEntryRules.moveTitle($0, kind: .movie) }, ["Title", "Year"])
        XCTAssertEqual(TextEntryRules.moveFields(.episode).map { TextEntryRules.moveTitle($0, kind: .episode) },
                       ["Show", "Year", "Season", "Episode", "Last Episode"])
        // The title matches the draft's own label, so the row and the old sheet name the same thing.
        XCTAssertEqual(TextEntryRules.moveTitle(.title, kind: .movie), SortMoveDraft(kind: .movie, title: "").titleLabel)
        XCTAssertEqual(TextEntryRules.moveTitle(.title, kind: .episode), SortMoveDraft(kind: .episode, title: "").titleLabel)
    }

    func testMoveNamesNeverSayOptionalAndTheFooterDoesOnce() {
        for kind in [UDSortOverrideValue.Kind.movie, .episode] {
            for field in TextEntryRules.moveFields(kind) {
                XCTAssertFalse(TextEntryRules.moveTitle(field, kind: kind).contains("Optional"), field.rawValue)
            }
        }
        XCTAssertEqual(TextEntryRules.moveOptionalLine(.movie), "Optional: Year.")
        XCTAssertEqual(TextEntryRules.moveOptionalLine(.episode), "Optional: Year and Last Episode.")
    }

    func testMoveKeyboards() {
        XCTAssertEqual(TextEntryRules.moveEntry(.title).keyboard, .standard)
        XCTAssertTrue(TextEntryRules.moveEntry(.title).capitalizesWords)
        for field in [TextEntryRules.MoveField.year, .season, .episode, .episodeEnd] {
            XCTAssertEqual(TextEntryRules.moveEntry(field).keyboard, .numberPad, field.rawValue)
            XCTAssertFalse(TextEntryRules.moveEntry(field).isSecret)
        }
        XCTAssertEqual(TextEntryRules.summary("Last Episode"), "Type the last episode on the keyboard.")
    }
}
