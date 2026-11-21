import XCTest
import VideoPlayerCore
@testable import AppLogic

/// Stage 2 (R302): the Plex sign-in page's state machine and its texts. The account side is a stand-in; no network.
final class PlexSetupTests: XCTestCase {
    actor FakeAccount: PlexAccountConnecting {
        var codes: [PlexCode]
        var outcome: Result<Void, Error>
        private(set) var asked = 0
        init(codes: [PlexCode], outcome: Result<Void, Error>) { self.codes = codes; self.outcome = outcome }
        func newCode() async throws -> PlexCode {
            asked += 1
            return codes.isEmpty ? PlexCode(code: "NONE", linkText: "plex.tv/link", expiresAt: .distantFuture) : codes.removeFirst()
        }
        func waitForSignIn(_ code: PlexCode) async throws { try outcome.get() }
        func setOutcome(_ outcome: Result<Void, Error>) { self.outcome = outcome }
    }

    struct Offline: Error, LocalizedError { var errorDescription: String? { "The network is not available." } }

    private let first = PlexCode(code: "AB12", linkText: "plex.tv/link", expiresAt: Date(timeIntervalSince1970: 100))
    private let second = PlexCode(code: "CD34", linkText: "plex.tv/link", expiresAt: Date(timeIntervalSince1970: 200))

    func testTheCodeIsShownThenSignedIn() async {
        var model = PlexSetupModel(account: FakeAccount(codes: [first], outcome: .success(())))
        XCTAssertEqual(model.phase, .gettingCode)
        await model.requestCode()
        XCTAssertEqual(model.phase, .code(first))
        await model.waitForSignIn()
        XCTAssertEqual(model.phase, .signedIn)
    }

    func testAnExpiredCodeOffersANewOne() async {
        let account = FakeAccount(codes: [first, second], outcome: .failure(PlexSetupError.codeExpired))
        var model = PlexSetupModel(account: account)
        await model.requestCode()
        await model.waitForSignIn()
        XCTAssertEqual(model.phase, .codeExpired)
        await account.setOutcome(.success(()))
        await model.requestCode()
        XCTAssertEqual(model.phase, .code(second), "Get a New Code shows a different code")
        await model.waitForSignIn()
        XCTAssertEqual(model.phase, .signedIn)
        let asked = await account.asked
        XCTAssertEqual(asked, 2)
    }

    func testAFailureIsOneCalmSentenceWithTryAgain() async {
        var model = PlexSetupModel(account: FakeAccount(codes: [first], outcome: .failure(Offline())))
        await model.requestCode()
        await model.waitForSignIn()
        guard case .failed(let error) = model.phase else { return XCTFail("expected a failure, got \(model.phase)") }
        XCTAssertEqual(error.retryTitle, "Try Again")
        XCTAssertFalse(error.message.contains("Offline"), "no type names")
    }

    func testCancellingLeavesTheCodeOnScreen() async {
        var model = PlexSetupModel(account: FakeAccount(codes: [first], outcome: .failure(CancellationError())))
        await model.requestCode()
        await model.waitForSignIn()
        XCTAssertEqual(model.phase, .code(first))
    }

    func testWaitingWithoutACodeDoesNothing() async {
        var model = PlexSetupModel(account: FakeAccount(codes: [], outcome: .success(())))
        await model.waitForSignIn()
        XCTAssertEqual(model.phase, .gettingCode)
    }

    /// HIG Managing accounts (read 20 Nov 2026): name the method, say why, never "passcode"; S1: no "..." in short texts.
    func testTheTextsFollowTheGuidance() {
        let all = [PlexSetupText.signInTitle, PlexSetupText.instruction(link: "plex.tv/link"), PlexSetupText.why,
                   PlexSetupText.waiting, PlexSetupText.expired, PlexSetupText.newCode, PlexSetupText.gettingCode]
        XCTAssertTrue(PlexSetupText.instruction(link: "plex.tv/link").contains("plex.tv/link"))
        XCTAssertTrue(PlexSetupText.signInTitle.contains("Plex"), "the method is named")
        XCTAssertTrue(PlexSetupText.why.contains("password is never entered"))
        XCTAssertEqual(PlexSetupText.newCode, "Get a New Code")
        for text in all {
            XCTAssertFalse(text.lowercased().contains("passcode"), text)
            XCTAssertFalse(text.contains("…") || text.contains("..."), text)
        }
    }
}
