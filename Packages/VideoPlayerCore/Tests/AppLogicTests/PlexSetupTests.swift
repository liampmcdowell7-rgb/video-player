import XCTest
import VideoPlayerCore
import LibraryIndex
import UserData
@testable import AppLogic

/// Stages 2 and 3 (R302, R303): the Plex setup page's state machine and its texts. The account side is a stand-in; no network.
final class PlexSetupTests: XCTestCase {
    actor FakeAccount: PlexAccountConnecting {
        var signedIn: Bool
        var codes: [PlexCode]
        var outcome: Result<Void, Error>
        var serverList: Result<[PlexServerChoice], Error>
        var connection: Result<PlexServerConnection, Error>
        private(set) var asked = 0
        init(signedIn: Bool = false, codes: [PlexCode] = [], outcome: Result<Void, Error> = .success(()),
             servers: Result<[PlexServerChoice], Error> = .success([]),
             connection: Result<PlexServerConnection, Error> = .failure(PlexSetupError.unreachable)) {
            self.signedIn = signedIn; self.codes = codes; self.outcome = outcome; self.serverList = servers; self.connection = connection
        }
        func isSignedIn() async -> Bool { signedIn }
        func newCode() async throws -> PlexCode {
            asked += 1
            return codes.isEmpty ? PlexCode(code: "NONE", linkText: "plex.tv/link", expiresAt: .distantFuture) : codes.removeFirst()
        }
        func waitForSignIn(_ code: PlexCode) async throws { try outcome.get() }
        func servers() async throws -> [PlexServerChoice] { try serverList.get() }
        func connect(_ server: PlexServerChoice) async throws -> PlexServerConnection { try connection.get() }
        func setOutcome(_ outcome: Result<Void, Error>) { self.outcome = outcome }
    }

    actor Secrets: SecretSaving {
        private(set) var saved: [String: String] = [:]
        func saveSecret(_ secret: String, for sourceID: String) async throws -> CloudSecretState { saved[sourceID] = secret; return .synced }
    }

    actor Definitions: SourceDefinitionSaving {
        private(set) var saved: [UDSourceDefinition] = []
        func saveDefinition(_ definition: UDSourceDefinition) async throws { saved.append(definition) }
    }

    struct Offline: Error, LocalizedError { var errorDescription: String? { "The network is not available." } }

    private let first = PlexCode(code: "AB12", linkText: "plex.tv/link", expiresAt: Date(timeIntervalSince1970: 100))
    private let second = PlexCode(code: "CD34", linkText: "plex.tv/link", expiresAt: Date(timeIntervalSince1970: 200))
    private let home = PlexServerChoice(id: "machine-0001", name: "Home PC", isLocal: true)
    private let friend = PlexServerChoice(id: "machine-0003", name: "Friend's Server", isLocal: false)

    private func model(_ account: FakeAccount, secrets: Secrets = Secrets(), definitions: Definitions = Definitions(),
                       store: SQLiteLibraryStore? = nil) throws -> PlexSetupModel {
        PlexSetupModel(account: account, store: try store ?? SQLiteLibraryStore(path: ":memory:"), secrets: secrets, definitions: definitions, makeID: { "plex-source-1" })
    }

    // MARK: Sign-in (stage 2)

    func testTheCodeIsShownThenTheServersAreListed() async throws {
        var model = try model(FakeAccount(codes: [first], servers: .success([home, friend])))
        XCTAssertEqual(model.phase, .gettingCode)
        await model.start()
        XCTAssertEqual(model.phase, .code(first))
        await model.waitForSignIn()
        XCTAssertEqual(model.phase, .servers([home, friend]))
    }

    func testAnAppleTVAlreadySignedInGoesStraightToTheServers() async throws {
        let account = FakeAccount(signedIn: true, servers: .success([home]))
        var model = try model(account)
        await model.start()
        XCTAssertEqual(model.phase, .servers([home]))
        let asked = await account.asked
        XCTAssertEqual(asked, 0, "no code is asked for")
    }

    func testAnExpiredCodeOffersANewOne() async throws {
        let account = FakeAccount(codes: [first, second], outcome: .failure(PlexSetupError.codeExpired), servers: .success([home]))
        var model = try model(account)
        await model.requestCode()
        await model.waitForSignIn()
        XCTAssertEqual(model.phase, .codeExpired)
        await account.setOutcome(.success(()))
        await model.requestCode()
        XCTAssertEqual(model.phase, .code(second), "Get a New Code shows a different code")
        await model.waitForSignIn()
        XCTAssertEqual(model.phase, .servers([home]))
        let asked = await account.asked
        XCTAssertEqual(asked, 2)
    }

    func testAFailureIsOneCalmSentenceWithTryAgain() async throws {
        var model = try model(FakeAccount(codes: [first], outcome: .failure(Offline())))
        await model.requestCode()
        await model.waitForSignIn()
        guard case .failed(let error) = model.phase else { return XCTFail("expected a failure, got \(model.phase)") }
        XCTAssertEqual(error.retryTitle, "Try Again")
        XCTAssertFalse(error.message.contains("Offline"), "no type names")
    }

    func testCancellingLeavesTheCodeOnScreen() async throws {
        var model = try model(FakeAccount(codes: [first], outcome: .failure(CancellationError())))
        await model.requestCode()
        await model.waitForSignIn()
        XCTAssertEqual(model.phase, .code(first))
    }

    func testWaitingWithoutACodeDoesNothing() async throws {
        var model = try model(FakeAccount())
        await model.waitForSignIn()
        XCTAssertEqual(model.phase, .gettingCode)
    }

    // MARK: Servers (stage 3)

    func testAnAccountWithoutServersSaysSo() async throws {
        var model = try model(FakeAccount(signedIn: true, servers: .success([])))
        await model.start()
        XCTAssertEqual(model.phase, .noServers)
    }

    func testRowsSayLocalOrRemote() {
        XCTAssertEqual(home.detail, "Local")
        XCTAssertEqual(friend.detail, "Remote")
    }

    func testAddingAServerSavesTheSourceTheDefinitionAndTheServerTokenAsTheSecret() async throws {
        let secrets = Secrets(), definitions = Definitions(), store = try SQLiteLibraryStore(path: ":memory:")
        let connection = PlexServerConnection(machineIdentifier: "machine-0001", name: "Home PC",
                                              uri: "https://192-168-1-20.machine0001.plex.direct:32400", token: "server-token-placeholder")
        var model = try model(FakeAccount(signedIn: true, servers: .success([home]), connection: .success(connection)),
                          secrets: secrets, definitions: definitions, store: store)
        await model.start()
        await model.add(home)
        guard case .saved(let record) = model.phase else { return XCTFail("expected saved, got \(model.phase)") }
        XCTAssertEqual(record.kind, .plex)
        XCTAssertEqual(record.name, "Home PC")
        let saved = await secrets.saved
        XCTAssertEqual(saved, ["plex-source-1": "server-token-placeholder"])
        let definition = try await XCTUnwrapAsync(await definitions.saved.first)
        XCTAssertEqual(definition.kind, "plex")
        XCTAssertEqual(definition.host, "192-168-1-20.machine0001.plex.direct")
        XCTAssertEqual(definition.port, 32400)
        XCTAssertEqual(definition.path, "https://192-168-1-20.machine0001.plex.direct:32400")
        XCTAssertEqual(definition.auth, "token")
        XCTAssertEqual(SourceOptions.parse(definition.options), ["machine": "machine-0001", "relay": "off"])
        for field in [definition.host, definition.path, definition.options, definition.name, definition.username] {
            XCTAssertFalse(field.contains("server-token-placeholder"), "no token in the definition")
        }
        let sources = try await store.sources()
        XCTAssertEqual(sources.map(\.id), ["plex-source-1"])
    }

    func testARelayOnlyServerExplainsWhatToDoAndSavesNothing() async throws {
        let secrets = Secrets(), store = try SQLiteLibraryStore(path: ":memory:")
        var model = try model(FakeAccount(signedIn: true, servers: .success([friend]), connection: .failure(PlexSetupError.onlyRelay)),
                          secrets: secrets, store: store)
        await model.start()
        await model.add(friend)
        guard case .failed(let error) = model.phase else { return XCTFail("expected a failure, got \(model.phase)") }
        XCTAssertEqual(error.message, PlexSetupText.onlyRelay)
        let saved = await secrets.saved
        XCTAssertTrue(saved.isEmpty)
        let sources = try await store.sources()
        XCTAssertTrue(sources.isEmpty)
    }

    func testAServerThatIsOffSaysSo() async throws {
        var model = try model(FakeAccount(signedIn: true, servers: .success([home]), connection: .failure(PlexSetupError.unreachable)))
        await model.start()
        await model.add(home)
        guard case .failed(let error) = model.phase else { return XCTFail("expected a failure, got \(model.phase)") }
        XCTAssertEqual(error.message, PlexSetupText.unreachable)
    }

    /// HIG Managing accounts (read 20 Nov 2026): name the method, say why, never "passcode"; S1: no "..." in short texts.
    func testTheTextsFollowTheGuidance() {
        let all = [PlexSetupText.signInTitle, PlexSetupText.instruction(link: "plex.tv/link"), PlexSetupText.why,
                   PlexSetupText.waiting, PlexSetupText.expired, PlexSetupText.newCode, PlexSetupText.gettingCode,
                   PlexSetupText.serversTitle, PlexSetupText.serversFooter, PlexSetupText.loadingServers,
                   PlexSetupText.noServersTitle, PlexSetupText.noServers, PlexSetupText.onlyRelay, PlexSetupText.unreachable]
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

private func XCTUnwrapAsync<T>(_ value: @autoclosure () async throws -> T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
    let v = try await value()
    return try XCTUnwrap(v, file: file, line: line)
}
