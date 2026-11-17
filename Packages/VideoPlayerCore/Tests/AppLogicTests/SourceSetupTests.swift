import XCTest
import VideoPlayerCore
import LibraryIndex
import UserData
@testable import AppLogic

private final class ScriptedConnector: SourceConnecting, @unchecked Sendable {
    enum Mode: Sendable { case ok, untrusted(host: String, hex: String), unauthorized, unreachable }
    private let lock = NSLock()
    private let mode: Mode
    private var fingerprints: [String?] = []
    init(_ mode: Mode) { self.mode = mode }
    var seenFingerprints: [String?] { lock.withLock { fingerprints } }
    var callCount: Int { lock.withLock { fingerprints.count } }
    func test(_ draft: SourceDraft, trustedFingerprint: String?) async throws -> ConnectionOutcome {
        lock.withLock { fingerprints.append(trustedFingerprint) }
        switch mode {
        case .ok: return .connected
        case .untrusted(let host, let hex): return trustedFingerprint == nil ? .untrustedCertificate(host: host, fingerprintHex: hex) : .connected
        case .unauthorized: throw SourceError.unauthorized
        case .unreachable: throw SourceError.invalidURL
        }
    }
}

private final class RecordingSecrets: SecretSaving, @unchecked Sendable {
    private let lock = NSLock()
    private var saved: [String: String] = [:]
    var all: [String: String] { lock.withLock { saved } }
    func saveSecret(_ secret: String, for sourceID: String) async throws -> CloudSecretState {
        lock.withLock { saved[sourceID] = secret }
        return .synced
    }
}

private final class RecordingDefinitions: SourceDefinitionSaving, @unchecked Sendable {
    private let lock = NSLock()
    private var saved: [UDSourceDefinition] = []
    var all: [UDSourceDefinition] { lock.withLock { saved } }
    func saveDefinition(_ definition: UDSourceDefinition) async throws { lock.withLock { saved.append(definition) } }
}

final class SourceSetupTests: XCTestCase {
    private func webdav(address: String = "https://nas.local:8443/dav", password: String = "hunter2") -> SourceDraft {
        SourceDraft(kind: .webdav, values: [.name: "My NAS", .address: address, .username: "me", .password: password])
    }

    private func viewModel(_ draft: SourceDraft, connector: ScriptedConnector, secrets: RecordingSecrets = RecordingSecrets(),
                           definitions: RecordingDefinitions? = RecordingDefinitions()) throws
        -> (SourceSetupViewModel, SQLiteLibraryStore, RecordingSecrets, RecordingDefinitions?) {
        let store = try SQLiteLibraryStore(path: ":memory:")
        let vm = SourceSetupViewModel(store: store, connector: connector, secrets: secrets, draft: draft, definitions: definitions,
                                      makeID: { "fixed-id" })
        return (vm, store, secrets, definitions)
    }

    func testTheDraftsUsedHereAreValid() {
        XCTAssertEqual(SourceDraftValidator.problems(webdav()), [])
    }

    func testASuccessfulConnectionSavesTheSourceTheDefinitionAndThePasswordSeparately() async throws {
        var (vm, store, secrets, definitions) = try viewModel(webdav(), connector: ScriptedConnector(.ok))
        await vm.connect()
        guard case .saved(let record) = vm.phase else { return XCTFail("phase \(vm.phase)") }
        XCTAssertEqual(record.id, "fixed-id")
        XCTAssertEqual(record.name, "My NAS")
        let listed = try await store.sources()
        XCTAssertEqual(listed.map(\.id), ["fixed-id"])
        XCTAssertEqual(secrets.all, ["fixed-id": "hunter2"])
        let definition = try XCTUnwrap(definitions?.all.first)
        XCTAssertEqual(definition.id, "fixed-id")
        XCTAssertEqual(definition.kind, "webdav")
        XCTAssertEqual(definition.host, "nas.local")
        XCTAssertEqual(definition.port, 8443)
        XCTAssertEqual(definition.path, "https://nas.local:8443/dav")
        XCTAssertEqual(definition.username, "me")
        XCTAssertEqual(definition.auth, "password")
        for text in [definition.id, definition.kind, definition.name, definition.host, definition.path, definition.username, definition.auth] {
            XCTAssertFalse(text.contains("hunter2"), "the password must never be part of the definition")
        }
    }

    func testAnInvalidDraftDoesNotConnectAndShowsItsProblems() async throws {
        let connector = ScriptedConnector(.ok)
        var (vm, _, _, _) = try viewModel(SourceDraft(kind: .webdav), connector: connector)
        XCTAssertEqual(vm.problems, [], "problems stay hidden until the first attempt")
        await vm.connect()
        XCTAssertEqual(vm.phase, .editing)
        XCTAssertFalse(vm.problems.isEmpty)
        XCTAssertNotNil(vm.problem(for: .address))
        XCTAssertEqual(connector.callCount, 0)
        XCTAssertFalse(vm.canSave)
    }

    func testAWrongPasswordGivesAPlainMessageAndNothingIsSaved() async throws {
        var (vm, store, secrets, definitions) = try viewModel(webdav(), connector: ScriptedConnector(.unauthorized))
        await vm.connect()
        guard case .failed(let error) = vm.phase else { return XCTFail("phase \(vm.phase)") }
        XCTAssertEqual(error.title, "Could Not Sign In")
        let listed = try await store.sources()
        XCTAssertTrue(listed.isEmpty)
        XCTAssertTrue(secrets.all.isEmpty)
        XCTAssertEqual(definitions?.all.count, 0)
        vm.dismissFailure()
        XCTAssertEqual(vm.phase, .editing)
    }

    func testAnyOtherFailureIsShownAndEditingAFieldClearsIt() async throws {
        var (vm, _, _, _) = try viewModel(webdav(), connector: ScriptedConnector(.unreachable))
        await vm.connect()
        guard case .failed = vm.phase else { return XCTFail("phase \(vm.phase)") }
        vm.set(.address, "https://other.local/dav")
        XCTAssertEqual(vm.phase, .editing)
        XCTAssertEqual(vm.draft[.address], "https://other.local/dav")
    }

    func testAnUntrustedCertificateAsksFirstThenTheGroupedFingerprintIsTrustedWithoutColons() async throws {
        let connector = ScriptedConnector(.untrusted(host: "nas.local", hex: "ab12cd34"))
        var (vm, store, _, _) = try viewModel(webdav(), connector: connector)
        await vm.connect()
        guard case .needsTrust(let prompt) = vm.phase else { return XCTFail("phase \(vm.phase)") }
        XCTAssertEqual(prompt.host, "nas.local")
        XCTAssertEqual(prompt.fingerprint, "AB:12:CD:34")
        let beforeTrust = try await store.sources()
        XCTAssertTrue(beforeTrust.isEmpty, "nothing is saved before the user trusts the certificate")
        await vm.trustAndContinue()
        guard case .saved = vm.phase else { return XCTFail("phase \(vm.phase)") }
        XCTAssertEqual(connector.seenFingerprints.count, 2)
        XCTAssertNil(connector.seenFingerprints[0] ?? nil)
        XCTAssertEqual(connector.seenFingerprints[1], "AB12CD34")
    }

    func testCancellingTheTrustQuestionGoesBackToEditingAndSavesNothing() async throws {
        var (vm, store, _, _) = try viewModel(webdav(), connector: ScriptedConnector(.untrusted(host: "nas.local", hex: "ab12")))
        await vm.connect()
        vm.cancelTrust()
        XCTAssertEqual(vm.phase, .editing)
        let listed = try await store.sources()
        XCTAssertTrue(listed.isEmpty)
    }

    func testATypeThatCannotBeOpenedYetNeverConnects() async throws {
        let unavailable = try XCTUnwrap(SourceCatalog.all.first { !$0.isAvailable })
        let connector = ScriptedConnector(.ok)
        var (vm, _, _, _) = try viewModel(SourceDraft(kind: unavailable.kind), connector: connector)
        await vm.connect()
        XCTAssertEqual(connector.callCount, 0)
        XCTAssertFalse(vm.canSave)
        XCTAssertNotNil(unavailable.unavailableNote)
    }

    func testNoPasswordMeansNoSecretIsSavedAndAuthIsNone() async throws {
        var (vm, _, secrets, definitions) = try viewModel(webdav(password: ""), connector: ScriptedConnector(.ok))
        await vm.connect()
        XCTAssertTrue(secrets.all.isEmpty)
        XCTAssertEqual(definitions?.all.first?.auth, "none")
    }

    func testDefinitionMappingForShareAndFolderKinds() {
        let smb = SourceDraft(kind: .smb, values: [.host: " nas ", .port: "445", .share: "Movies", .username: "u", .password: "p"])
        let a = smb.definition(id: "s", addedAt: epoch)
        XCTAssertEqual([a.kind, a.host, a.path, a.username, a.auth], ["smb", "nas", "Movies", "u", "password"])
        XCTAssertEqual(a.port, 445)
        XCTAssertEqual(a.addedAt, epoch)
        let nfs = SourceDraft(kind: .nfs, values: [.host: "nas", .folder: "/export/media"])
        let b = nfs.definition(id: "n")
        XCTAssertEqual([b.kind, b.host, b.path, b.auth], ["nfs", "nas", "/export/media", "none"])
        XCTAssertNil(b.port)
    }

    func testTheLedgerSavesTheDefinitionAndCopiesItToTheEssentials() async throws {
        let ledger = UserDataLedger(deviceID: "dev")
        let kv = InMemoryKeyValueStore()
        let essentials = UDEssentialsStore(store: kv)
        let saver = LedgerSourceDefinitions(ledger: ledger, essentials: essentials)
        let definition = webdav().definition(id: "abc", addedAt: epoch)
        try await saver.saveDefinition(definition)
        XCTAssertEqual(ledger.sourceDefinitions(), [definition])
        XCTAssertGreaterThan(essentials.storedBytes, 0)
        // A fresh install restores the same list from the essentials copy.
        let fresh = UserDataLedger(deviceID: "dev2")
        _ = UDEssentialsStore(store: kv).restore(into: fresh)
        XCTAssertEqual(fresh.sourceDefinitions(), [definition])
        XCTAssertFalse(String(decoding: kv.data(forKey: UDEssentialsStore.storageKey) ?? Data(), as: UTF8.self).contains("hunter2"))
    }
}
