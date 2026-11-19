import XCTest
@testable import LibraryBackup

/// #15 3.9 and #17 D: the Backup page has short lines; nothing of the old text is lost, it moved to "About Backup".
final class BackupTextTests: XCTestCase {
    func testTheShortLinesFitTwoLinesAndKeepTheNeverIncludedPromise() {
        XCTAssertLessThanOrEqual(BackupStatusText.summary.count, 130)
        XCTAssertLessThanOrEqual(BackupStatusText.whatShort.count, 130)
        for word in ["videos", "passwords", "sign-in tokens", "API keys"] {
            XCTAssertTrue(BackupStatusText.whatShort.contains(word), word)
        }
    }

    func testTheLearnMorePageKeepsEveryOriginalSentenceUnchanged() {
        for text in [BackupStatusText.intro, BackupStatusText.storageNote, BackupStatusText.libraryDetail,
                     BackupStatusText.artworkDetail, BackupStatusText.userDataDetail, BackupStatusText.neverIncluded] {
            XCTAssertTrue(BackupStatusText.learnMore.contains(text), text)
        }
    }
}
