import XCTest
import VideoPlayerCore
import LibraryIndex
import UserData
@testable import AppLogic

// Per-kind wiring of the add-a-source flow: catalog, labels, draft -> definition, the approved fingerprint, Bonjour mapping.
// FIXTURE: every host, address and fingerprint below is made up; no server is contacted.

private final class StubConnector: SourceConnecting, @unchecked Sendable {
    enum Mode: Sendable {
        case ok, tlsAlways(host: String, hex: String), tlsFirstUse(host: String, hex: String), sshFirstUse(host: String, fingerprint: String), signIn, tokens(String)
    }
    private let lock = NSLock()
    private let mode: Mode
    private var trustedSeen: [String?] = []
    private var finished = 0
    init(_ mode: Mode) { self.mode = mode }
    var trusted: [String?] { lock.withLock { trustedSeen } }
    var signInFinished: Int { lock.withLock { finished } }

    func test(_ draft: SourceDraft, trustedFingerprint: String?) async throws -> ConnectionOutcome {
        lock.withLock { trustedSeen.append(trustedFingerprint) }
        switch mode {
        case .ok, .tokens: return .connected
        case .tlsAlways(let host, let hex): return .untrustedCertificate(host: host, fingerprintHex: hex)
        case .tlsFirstUse(let host, let hex): return trustedFingerprint == nil ? .untrustedCertificate(host: host, fingerprintHex: hex) : .connected
        case .sshFirstUse(let host, let fp): return trustedFingerprint == nil ? .unapprovedHostKey(host: host, fingerprint: fp) : .connected
        case .signIn: return .needsSignIn(DeviceSignIn(userCode: "ABCD-EFGH", verificationAddress: "example.invalid/device", expiresInSeconds: 900))
        }
    }
    func finishSignIn(_ draft: SourceDraft) async throws -> ConnectionOutcome { lock.withLock { finished += 1 }; return .connected }
    func secretToSave(for draft: SourceDraft) async -> String? {
        if case .tokens(let json) = mode { return json }
        return draft[.password].isEmpty ? nil : draft[.password]
    }
}

private final class Secrets: SecretSaving, @unchecked Sendable {
    private let lock = NSLock(); private var saved: [String: String] = [:]
    var all: [String: String] { lock.withLock { saved } }
    func saveSecret(_ secret: String, for sourceID: String) async throws -> CloudSecretState { lock.withLock { saved[sourceID] = secret }; return .synced }
}

private final class Definitions: SourceDefinitionSaving, @unchecked Sendable {
    private let lock = NSLock(); private var saved: [UDSourceDefinition] = []
    var all: [UDSourceDefinition] { lock.withLock { saved } }
    func saveDefinition(_ definition: UDSourceDefinition) async throws { lock.withLock { saved.append(definition) } }
}

final class SourceWiringTests: XCTestCase {
    private let at = Date(timeIntervalSince1970: 1_000)

    // MARK: Catalog

    func testEveryKindAppearsExactlyOnceInTheCatalog() {
        let kinds = SourceCatalog.all.map(\.kind)
        XCTAssertEqual(kinds.count, SourceKind.allCases.count)
        XCTAssertEqual(Set(kinds), Set(SourceKind.allCases))
        XCTAssertEqual(Set(SourceCatalog.all.map(\.title)).count, SourceKind.allCases.count, "no two kinds share a title")
    }

    func testTheKindsTheUserListedAreAvailableAndPlexDropboxDriveAndOneDriveAreNot() {
        for kind in [SourceKind.smb, .nfs, .sftp, .ftp, .upnp, .jellyfin, .emby, .directLink, .webdav] {
            XCTAssertTrue(SourceCatalog.info(for: kind).isAvailable, "\(kind)")
            XCTAssertFalse(SourceCatalog.info(for: kind).fields.isEmpty, "\(kind) has fields to fill in")
        }
        for kind in [SourceKind.plex, .oneDrive, .dropbox, .googleDrive] {
            XCTAssertFalse(SourceCatalog.info(for: kind).isAvailable, "\(kind)")
            XCTAssertTrue(SourceCatalog.info(for: kind).fields.isEmpty)
        }
    }

    func testOneDriveIsBlockedWithTheExactStatusUntilAClientIDExists() {
        let blocked = SourceCatalog.info(for: .oneDrive)
        XCTAssertTrue(blocked.unavailableNote?.hasPrefix("blocked: needs an app registration") == true)
        XCTAssertEqual(SourceCatalog.info(for: .oneDrive, oneDriveClientID: "").unavailableNote, blocked.unavailableNote)
        XCTAssertEqual(SourceCatalog.info(for: .oneDrive, oneDriveClientID: nil).unavailableNote, blocked.unavailableNote)
        // Once an ID is configured the kind opens up (a made-up value; the app never ships one invented).
        let open = SourceCatalog.info(for: .oneDrive, oneDriveClientID: "fixture-client-id")
        XCTAssertTrue(open.isAvailable)
        XCTAssertEqual(open.fields.map(\.kind), [.name])
        XCTAssertEqual(SourceCatalog.catalog().filter { $0.kind == .oneDrive }.count, 1)
    }

    func testPlexNoteNamesPlexAndSaysWhatIsMissing() {
        XCTAssertEqual(SourceCatalog.info(for: .plex).unavailableNote,
                       "blocked: Plex needs a Plex account sign-in, which this app does not offer yet. Use the Plex server’s media folder through SMB or WebDAV instead.")
    }

    /// docs/NAMES.md: every source type is listed by its real name, and every blocked one says "blocked:" and names the
    /// service it is about (no generic "the provider" / "media server" wording).
    func testEverySourceTypeHasItsRealNameAndBlockedOnesNameTheService() {
        let expected: [SourceKind: String] = [
            .webdav: "WebDAV", .smb: "SMB", .nfs: "NFS", .sftp: "SFTP", .ftp: "FTP", .upnp: "UPnP/DLNA",
            .jellyfin: "Jellyfin", .emby: "Emby", .plex: "Plex", .oneDrive: "OneDrive", .dropbox: "Dropbox",
            .googleDrive: "Google Drive", .directLink: "Web Link",
        ]
        for info in SourceCatalog.catalog() {
            XCTAssertEqual(info.title, expected[info.kind], "\(info.kind)")
            if let note = info.unavailableNote {
                XCTAssertTrue(note.hasPrefix("blocked: "), note)
                XCTAssertTrue(note.contains(info.title), "a blocked note names the service: \(note)")
                XCTAssertFalse(note.contains("the provider"), note)
            }
        }
        XCTAssertEqual(SourceCatalog.catalog().count, expected.count, "every kind is listed once")
    }

    // MARK: Verification label, per kind, exact text

    func testTheVerificationLabelTextPerKind() {
        let notVerified = "Not yet verified against a real server"
        let recordedOnly = "Tested with recorded replies only; not yet verified against a real server"
        let real = "Tested against a real server"
        let expected: [SourceKind: String] = [
            .webdav: real, .jellyfin: real, .emby: real, .ftp: real, .upnp: real,
            .smb: recordedOnly, .nfs: recordedOnly, .sftp: recordedOnly, .directLink: recordedOnly, .oneDrive: recordedOnly,
            .plex: notVerified, .dropbox: notVerified, .googleDrive: notVerified,
        ]
        XCTAssertEqual(expected.count, SourceKind.allCases.count, "the table covers every kind")
        for kind in SourceKind.allCases {
            XCTAssertEqual(SourceCatalog.info(for: kind).statusLine, expected[kind], "\(kind)")
            XCTAssertEqual(SourceCatalog.statusLine(kind), expected[kind], "\(kind)")
            // Anything below a real-server test must carry the words "not yet verified against a real server".
            if kind.verification < .realServer {
                XCTAssertTrue(SourceCatalog.statusLine(kind).lowercased().contains("not yet verified against a real server"), "\(kind)")
            }
        }
    }

    func testASavedSourceShowsItsKindsLabelAndCaveat() {
        let smb = UDSourceDefinition(id: "1", kind: "smb", name: "NAS")
        XCTAssertEqual(smb.verificationLabel, "Tested with recorded replies only; not yet verified against a real server")
        XCTAssertEqual(smb.kindTitle, "SMB")
        let ftp = UDSourceDefinition(id: "2", kind: "ftp", name: "FTP")
        XCTAssertEqual(ftp.verificationLabel, "Tested against a real server")
        XCTAssertTrue(ftp.caveat?.contains("FTPS") == true, "plain FTP was tested; FTPS was not, and the screen says so")
        let unknown = UDSourceDefinition(id: "3", kind: "somethingnew", name: "?")
        XCTAssertNil(unknown.verificationLabel)
        XCTAssertEqual(unknown.kindTitle, "somethingnew")
    }

    // MARK: Draft -> definition, per kind

    func testDefinitionMappingPerKind() {
        func def(_ kind: SourceKind, _ v: [SourceFieldKind: String]) -> UDSourceDefinition { SourceDraft(kind: kind, values: v).definition(id: "x", addedAt: at) }

        let webdav = def(.webdav, [.address: "https://nas.local:8443/dav", .username: "u", .password: "p"])
        XCTAssertEqual([webdav.kind, webdav.host, webdav.path, webdav.auth], ["webdav", "nas.local", "https://nas.local:8443/dav", "password"])
        XCTAssertEqual(webdav.port, 8443)

        let smb = def(.smb, [.host: "nas", .share: "Videos", .port: "4455"])
        XCTAssertEqual([smb.kind, smb.host, smb.path, smb.auth], ["smb", "nas", "Videos", "none"])
        XCTAssertEqual(smb.port, 4455)

        let nfs = def(.nfs, [.host: "nas", .folder: "/volume1/video"])
        XCTAssertEqual([nfs.kind, nfs.host, nfs.path], ["nfs", "nas", "/volume1/video"])

        let sftp = def(.sftp, [.host: "box", .port: "2222", .folder: " /media ", .username: "me", .password: "pw"])
        XCTAssertEqual([sftp.kind, sftp.host, sftp.path, sftp.username, sftp.auth], ["sftp", "box", "/media", "me", "password"])
        XCTAssertEqual(sftp.port, 2222)

        let ftp = def(.ftp, [.host: "box", .security: "explicit"])
        XCTAssertEqual(ftp.optionValues, ["security": "explicit"])
        XCTAssertEqual(ftp.auth, "none")
        XCTAssertEqual(def(.ftp, [.host: "box"]).optionValues, ["security": "none"], "an untouched picker means plain FTP")
        XCTAssertEqual(def(.ftp, [.host: "box", .security: "implicit"]).optionValues["security"], "implicit")

        let upnp = def(.upnp, [.address: "http://192.168.1.20:8200/rootDesc.xml"])
        XCTAssertEqual([upnp.kind, upnp.host, upnp.path], ["upnp", "192.168.1.20", "http://192.168.1.20:8200/rootDesc.xml"])
        XCTAssertEqual(upnp.port, 8200)

        for kind in [SourceKind.jellyfin, .emby] {
            let d = def(kind, [.address: "http://server.local:8096", .username: "me", .password: "pw"])
            XCTAssertEqual([d.kind, d.host, d.path, d.username, d.auth], [kind.rawValue, "server.local", "http://server.local:8096", "me", "password"])
            XCTAssertEqual(d.port, 8096)
        }

        let link = def(.directLink, [.address: "https://example.com/video.mkv", .name: "Clip"])
        XCTAssertEqual([link.kind, link.name, link.host, link.path, link.auth], ["directLink", "Clip", "example.com", "https://example.com/video.mkv", "none"])

        XCTAssertEqual(def(.oneDrive, [.name: "My OneDrive"]).auth, "oauth")
    }

    func testNoDefinitionEverContainsThePassword() {
        for kind in SourceKind.allCases {
            let d = SourceDraft(kind: kind, values: [.password: "s3cret-pw", .username: "u", .host: "h", .address: "http://h/x", .share: "s", .folder: "/f"])
                .definition(id: "i", addedAt: at, trustedFingerprint: "AB12")
            for text in [d.id, d.kind, d.name, d.host, d.path, d.username, d.auth, d.options, d.trustedFingerprint] {
                XCTAssertFalse(text.contains("s3cret-pw"), "\(kind)")
            }
        }
    }

    func testTheFTPEncryptionPickerOnlyAcceptsItsChoices() {
        var draft = SourceDraft(kind: .ftp, values: [.host: "box", .security: "tls-please"])
        XCTAssertEqual(SourceDraftValidator.problems(draft).map(\.field), [.security])
        for ok in ["none", "explicit", "implicit", ""] {
            draft[.security] = ok
            XCTAssertEqual(SourceDraftValidator.problems(draft), [], "'\(ok)'")
        }
    }

    func testRequiredFieldsPerKind() {
        XCTAssertEqual(Set(SourceDraftValidator.problems(SourceDraft(kind: .sftp)).map(\.field)), [.host, .username, .password])
        XCTAssertEqual(Set(SourceDraftValidator.problems(SourceDraft(kind: .smb)).map(\.field)), [.host, .share])
        XCTAssertEqual(Set(SourceDraftValidator.problems(SourceDraft(kind: .upnp)).map(\.field)), [.address])
        XCTAssertEqual(Set(SourceDraftValidator.problems(SourceDraft(kind: .jellyfin)).map(\.field)), [.address, .username])
        XCTAssertEqual(Set(SourceDraftValidator.problems(SourceDraft(kind: .directLink)).map(\.field)), [.address])
    }

    func testAFoundServerFillsTheFormIncludingItsFullAddress() {
        let upnp = SourceDraft(discovered: DiscoveredSource(kind: .upnp, name: "Media", host: "192.168.1.20", port: 8200, address: "http://192.168.1.20:8200/rootDesc.xml"))
        XCTAssertEqual(upnp[.address], "http://192.168.1.20:8200/rootDesc.xml")
        let dav = SourceDraft(discovered: DiscoveredSource(kind: .webdav, name: "Dav", host: "nas.local", port: 5006, address: "https://nas.local:5006"))
        XCTAssertEqual(dav[.address], "https://nas.local:5006")
        let plain = SourceDraft(discovered: DiscoveredSource(kind: .webdav, name: "Dav", host: "nas.local", port: 8080))
        XCTAssertEqual(plain[.address], "http://nas.local:8080")
    }

    // MARK: The approved fingerprint is saved and restored

    func testTheApprovedCertificateIsSavedInTheDefinitionAndSurvivesTheLedgerAndEssentials() async throws {
        let definitions = Definitions()
        let connector = StubConnector(.tlsFirstUse(host: "nas.local", hex: "ab12cd34"))
        var vm = SourceSetupViewModel(store: try SQLiteLibraryStore(path: ":memory:"), connector: connector, secrets: Secrets(),
                                      draft: SourceDraft(kind: .webdav, values: [.address: "https://nas.local/dav"]), definitions: definitions, makeID: { "id1" })
        await vm.connect()
        guard case .needsTrust(let prompt) = vm.phase else { return XCTFail("\(vm.phase)") }
        XCTAssertEqual(prompt.kind, .tlsCertificate)
        XCTAssertEqual(definitions.all.count, 0, "nothing is saved before the user approves")
        await vm.trustAndContinue()
        guard case .saved = vm.phase else { return XCTFail("\(vm.phase)") }
        let saved = try XCTUnwrap(definitions.all.first)
        XCTAssertEqual(saved.trustedFingerprint, "AB12CD34")

        let ledger = UserDataLedger(deviceID: "a")
        let kv = InMemoryKeyValueStore()
        try await LedgerSourceDefinitions(ledger: ledger, essentials: UDEssentialsStore(store: kv)).saveDefinition(saved)
        let fresh = UserDataLedger(deviceID: "b")
        UDEssentialsStore(store: kv).restore(into: fresh)
        XCTAssertEqual(fresh.sourceDefinitions().first?.trustedFingerprint, "AB12CD34")
        XCTAssertEqual(fresh.sourceDefinitions().first?.approvedFingerprintDisplay, "AB:12:CD:34")
    }

    func testAnSSHHostKeyIsAskedAboutThenSavedExactlyAsShown() async throws {
        let definitions = Definitions()
        let connector = StubConnector(.sshFirstUse(host: "box.local", fingerprint: "SHA256:abcDEF123+/"))
        var vm = SourceSetupViewModel(store: try SQLiteLibraryStore(path: ":memory:"), connector: connector, secrets: Secrets(),
                                      draft: SourceDraft(kind: .sftp, values: [.host: "box.local", .username: "me", .password: "pw"]),
                                      definitions: definitions, makeID: { "id2" })
        await vm.connect()
        guard case .needsTrust(let prompt) = vm.phase else { return XCTFail("\(vm.phase)") }
        XCTAssertEqual(prompt.kind, .sshHostKey)
        XCTAssertEqual(prompt.fingerprint, "SHA256:abcDEF123+/", "a host key is shown as ssh-keygen prints it, not regrouped")
        XCTAssertTrue(prompt.message.contains("first time"))
        await vm.trustAndContinue()
        XCTAssertEqual(connector.trusted.last ?? nil, "SHA256:abcDEF123+/")
        XCTAssertEqual(definitions.all.first?.trustedFingerprint, "SHA256:abcDEF123+/")
        XCTAssertEqual(definitions.all.first?.approvedFingerprintDisplay, "SHA256:abcDEF123+/")
    }

    func testChangingTheServerAfterApprovingDropsTheApproval() async throws {
        // A server whose certificate never gets accepted (it keeps showing something new), so the flow stays at the question.
        let connector = StubConnector(.tlsAlways(host: "a.local", hex: "ab12"))
        var vm = SourceSetupViewModel(store: try SQLiteLibraryStore(path: ":memory:"), connector: connector, secrets: Secrets(),
                                      draft: SourceDraft(kind: .webdav, values: [.address: "https://a.local/dav"]), definitions: Definitions(), makeID: { "i" })
        await vm.connect()
        await vm.trustAndContinue()
        XCTAssertEqual(connector.trusted.last ?? nil, "AB12", "the approval is sent along on the retry")
        let before = connector.trusted.count
        vm.set(.address, "https://b.local/dav")
        await vm.connect()
        XCTAssertNil(connector.trusted[before] ?? nil, "the approval belonged to a.local and is dropped when the address changes")
    }

    func testPasswordsGoToTheSecretStoreAndTokensReplaceThemForSignInKinds() async throws {
        let secrets = Secrets()
        var vm = SourceSetupViewModel(store: try SQLiteLibraryStore(path: ":memory:"), connector: StubConnector(.ok), secrets: secrets,
                                      draft: SourceDraft(kind: .jellyfin, values: [.address: "http://j.local:8096", .username: "me", .password: "pw1"]),
                                      definitions: Definitions(), makeID: { "j" })
        await vm.connect()
        XCTAssertEqual(secrets.all, ["j": "pw1"])
        let tokenSecrets = Secrets()
        var od = SourceSetupViewModel(store: try SQLiteLibraryStore(path: ":memory:"), connector: StubConnector(.tokens("{\"fixture\":true}")), secrets: tokenSecrets,
                                      draft: SourceDraft(kind: .oneDrive, values: [.name: "OD"]), definitions: Definitions(), makeID: { "o" })
        od.oneDriveClientID = "fixture-client-id"
        await od.connect()
        XCTAssertEqual(tokenSecrets.all, ["o": "{\"fixture\":true}"])
    }

    func testTheDeviceSignInStepAsksThenContinuesAndSaves() async throws {
        let connector = StubConnector(.signIn)
        let definitions = Definitions()
        var vm = SourceSetupViewModel(store: try SQLiteLibraryStore(path: ":memory:"), connector: connector, secrets: Secrets(),
                                      draft: SourceDraft(kind: .oneDrive, values: [.name: "OD"]), definitions: definitions, makeID: { "o" })
        vm.oneDriveClientID = "fixture-client-id"
        await vm.connect()
        guard case .needsSignIn(let prompt) = vm.phase else { return XCTFail("\(vm.phase)") }
        XCTAssertEqual(prompt.userCode, "ABCD-EFGH")
        XCTAssertTrue(prompt.message.contains("ABCD-EFGH"))
        XCTAssertEqual(definitions.all.count, 0)
        await vm.continueAfterSignIn()
        guard case .saved = vm.phase else { return XCTFail("\(vm.phase)") }
        XCTAssertEqual(connector.signInFinished, 1)
        XCTAssertEqual(definitions.all.first?.auth, "oauth")
    }

    func testOneDriveWithoutAClientIDNeverReachesTheConnector() async throws {
        let connector = StubConnector(.ok)
        var vm = SourceSetupViewModel(store: try SQLiteLibraryStore(path: ":memory:"), connector: connector, secrets: Secrets(),
                                      draft: SourceDraft(kind: .oneDrive, values: [.name: "OD"]), definitions: Definitions(), makeID: { "o" })
        await vm.connect()
        XCTAssertEqual(connector.trusted.count, 0)
        XCTAssertEqual(vm.phase, .editing)
        XCTAssertFalse(vm.canSave)
    }

    // MARK: Changed certificate: the state the screens show

    func testAChangedCertificateGivesAnHonestStateAndNeverATrustedOne() {
        let refusal = TrustRefusal(kind: .tlsCertificate, host: "nas.local", expected: "ab12cd34", presented: "ffee0011")
        let issue = TrustIssue(sourceID: "s", sourceName: "My NAS", refusal: refusal)
        XCTAssertEqual(issue.title, "The Server’s Certificate Changed")
        XCTAssertTrue(issue.message.contains("not the one you approved"))
        XCTAssertTrue(issue.message.contains("Nothing was trusted automatically"))
        XCTAssertEqual(issue.approvedFingerprint, "AB:12:CD:34")
        XCTAssertEqual(issue.presentedFingerprint, "FF:EE:00:11")
        XCTAssertEqual(issue.savedValueIfTrusted, "FFEE0011")
        XCTAssertEqual(issue.acceptTitle, "Trust the New Certificate")
        let key = TrustIssue(sourceID: "s", sourceName: "Box", refusal: TrustRefusal(kind: .sshHostKey, host: "box", expected: "SHA256:old", presented: "SHA256:new"))
        XCTAssertEqual(key.title, "The Server’s Host Key Changed")
        XCTAssertEqual(key.savedValueIfTrusted, "SHA256:new")
        XCTAssertEqual(key.acceptTitle, "Trust the New Host Key")
    }

    func testAnErrorFromAGuardedSourceBecomesTheChangedState() {
        let error = TrustRefusedError(TrustRefusal(kind: .sshHostKey, host: "box", expected: "SHA256:old", presented: "SHA256:new"))
        let state = SourceErrorText.state(for: error, doing: "scan")
        XCTAssertEqual(state.title, "The Server’s Host Key Changed")
    }

    func testSourceErrorWording() {
        XCTAssertEqual(SourceErrorText.state(for: SourceError.unauthorized, doing: "x").title, "Could Not Sign In")
        XCTAssertEqual(SourceErrorText.state(for: SourceError.notFound, doing: "x").title, "Not Found")
        XCTAssertTrue(SourceErrorText.state(for: SourceError.transport("timed out"), doing: "connect").message.contains("timed out"))
        XCTAssertEqual(SourceErrorText.state(for: SourceError.unsupported("Nope."), doing: "x").message, "Nope.")
        XCTAssertEqual(SourceErrorText.state(for: SourceError.httpStatus(503), doing: "x").message, "The server answered with an error (503).")
    }

    // MARK: Bonjour

    func testBonjourResolvedAddressIsUsedAndTheLocalNameIsOnlyTheFallback() throws {
        let resolved = try XCTUnwrap(BonjourMapping.discovered(BonjourService(type: "_smb._tcp", name: "Living Room NAS", resolvedHost: "192.168.1.30", resolvedPort: 445)))
        XCTAssertEqual(resolved, DiscoveredSource(kind: .smb, name: "Living Room NAS", host: "192.168.1.30", port: nil))
        let fallback = try XCTUnwrap(BonjourMapping.discovered(BonjourService(type: "_smb._tcp", name: "Living Room NAS")))
        XCTAssertEqual(fallback.host, "living-room-nas.local")
        XCTAssertTrue(BonjourMapping.isResolved(BonjourService(type: "_smb._tcp", name: "n", resolvedHost: "192.168.1.30")))
        XCTAssertFalse(BonjourMapping.isResolved(BonjourService(type: "_smb._tcp", name: "n")))
    }

    func testBonjourKindsPortsAndSecureWebDAV() throws {
        XCTAssertEqual(BonjourMapping.kind(forType: "_ftp._tcp"), .ftp)
        XCTAssertEqual(BonjourMapping.kind(forType: "_sftp-ssh._tcp."), .sftp)
        XCTAssertNil(BonjourMapping.kind(forType: "_ipp._tcp"))
        XCTAssertNil(BonjourMapping.discovered(BonjourService(type: "_ipp._tcp", name: "Printer")))
        let sftp = try XCTUnwrap(BonjourMapping.discovered(BonjourService(type: "_sftp-ssh._tcp", name: "Box", resolvedHost: "10.0.0.5", resolvedPort: 2222)))
        XCTAssertEqual(sftp.port, 2222, "a non-default port is kept")
        let dav = try XCTUnwrap(BonjourMapping.discovered(BonjourService(type: "_webdavs._tcp", name: "Dav", resolvedHost: "10.0.0.6", resolvedPort: 5006)))
        XCTAssertEqual(dav.address, "https://10.0.0.6:5006")
        let plainDav = try XCTUnwrap(BonjourMapping.discovered(BonjourService(type: "_webdav._tcp", name: "Dav", resolvedHost: "10.0.0.6", resolvedPort: 80)))
        XCTAssertEqual(plainDav.address, "http://10.0.0.6:80")
    }

    func testAScopedIPv6ResultCountsAsUnresolvedBecauseItCannotBeTyped() throws {
        let s = BonjourService(type: "_smb._tcp", name: "Box", resolvedHost: "fe80::1%en0", resolvedPort: 445)
        XCTAssertFalse(BonjourMapping.isResolved(s))
        XCTAssertEqual(BonjourMapping.discovered(s)?.host, "box.local")
        XCTAssertEqual(BonjourMapping.discovered(BonjourService(type: "_smb._tcp", name: "Box", resolvedHost: "box.local.", resolvedPort: 445))?.host, "box.local")
    }

    func testTheBonjourTypesMatchTheTypesWeDeclare() {
        XCTAssertEqual(BonjourMapping.serviceTypes.map(\.type), ["_webdav._tcp", "_webdavs._tcp", "_smb._tcp", "_nfs._tcp", "_sftp-ssh._tcp", "_ftp._tcp"])
    }

    // MARK: Subfolder

    func testASubfolderPresentsItsFolderAsTheRootAndCannotEscape() async throws {
        let inner = ScriptedSource()
        let sub = SubfolderSource(inner, root: "/Videos")
        let list = try await sub.list("/")
        XCTAssertEqual(list.map(\.path), ["/a.mkv", "/Season 1"])
        XCTAssertEqual(inner.seen.last, "/Videos")
        _ = try await sub.list("/Season 1")
        XCTAssertEqual(inner.seen.last, "/Videos/Season 1")
        _ = try await sub.read("/a.mkv", range: ByteRange(offset: 0, length: 1))
        XCTAssertEqual(inner.seen.last, "/Videos/a.mkv")
        _ = try await sub.list("/../../etc")
        XCTAssertEqual(inner.seen.last, "/Videos/etc", ".. cannot climb out of the chosen folder")
        let whole = SubfolderSource(inner, root: "/")
        _ = try await whole.list("/x")
        XCTAssertEqual(inner.seen.last, "/x")
    }
}

private final class ScriptedSource: MediaSource, @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []
    var seen: [String] { lock.withLock { paths } }
    private func note(_ p: String) { lock.withLock { paths.append(p) } }
    var kind: SourceKind { .smb }
    var capabilities: SourceCapabilities { SourceCapabilities(authMethods: [.none], byteRanges: true, changeSignals: []) }
    func authenticate() async throws {}
    func list(_ path: String) async throws -> [SourceEntry] {
        note(path)
        return [SourceEntry(path: "/Videos/a.mkv", name: "a.mkv", isDirectory: false),
                SourceEntry(path: "/Videos/Season 1", name: "Season 1", isDirectory: true)]
    }
    func info(_ path: String) async throws -> SourceEntry { note(path); return SourceEntry(path: path, name: "x", isDirectory: false) }
    func read(_ path: String, range: ByteRange) async throws -> Data { note(path); return Data([0]) }
    func playbackAccess(for path: String) async throws -> PlaybackAccess { note(path); return .byteReader }
}
