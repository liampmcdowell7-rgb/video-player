import XCTest
@testable import AppLogic

/// Stage 5 (R305): the message for a Plex file only the server could convert. The server is never asked to convert.
final class PlexPlaybackFailureTests: XCTestCase {
    func testTheMessageSaysTheFileCannotBePlayedAndNamesTheFormat() {
        let failure = PlaybackFailures.needsServerConversion(formatName: "MPEG-2 video")
        XCTAssertEqual(failure.kind, .unsupportedVideo)
        XCTAssertEqual(failure.alertTitle, "Format Not Supported")
        XCTAssertFalse(failure.canTryAgain, "trying again fails the same way")
        XCTAssertTrue(failure.message.contains("cannot play this file"))
        XCTAssertTrue(failure.message.contains("MPEG-2 video"))
        XCTAssertFalse(failure.advice.isEmpty, "a what-to-do sentence")
        XCTAssertFalse(failure.text.contains("…") || failure.text.contains("..."))
        XCTAssertFalse(failure.text.lowercased().contains("transcod"), "plain words, no server jargon")
    }
}
