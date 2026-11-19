import XCTest
import VideoPlayerCore
import PlaybackLogic
import MetadataOnline
import UserData
@testable import AppLogic

// #26 item 9. FIXTURE: every key below is placeholder text, not a key; fake stores, fake clouds and a fake transport are
// used, nothing is contacted.

/// Never touches the network: answers from a handler and counts requests.
private final class FakeTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: @Sendable (HTTPRequest) throws -> HTTPResponse
    private(set) var count = 0
    init(_ handler: @escaping @Sendable (HTTPRequest) throws -> HTTPResponse) { self.handler = handler }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let h = lock.withLock { count += 1; return handler }
        return try h(request)
    }
}

private final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ v: T) { value = v }
    func with<R>(_ body: (inout T) -> R) -> R { lock.withLock { body(&value) } }
    var get: T { lock.withLock { value } }
}

private let noWait = QueueConfiguration(minInterval: 0, maxRetries: 0, baseBackoff: 0, maxBackoff: 0, jitter: 0)

final class AppWideKeyStoreTests: XCTestCase {
    static let key = "placeholderKEY0123456789abcdef"

    func testStoreReadAndDeleteAKey() async throws {
        let store = OnlineKeyStore(secrets: MirroredSecrets(local: InMemoryCredentialStore(), cloud: InMemorySecretCloud()))
        try await store.save(Self.key, for: .tmdb)
        XCTAssertEqual(store.key(.tmdb), Self.key)
        try await store.remove(.tmdb)
        XCTAssertNil(store.key(.tmdb))
    }

    /// One key, read by every feature and every source: there is one item per service, never one per source or library.
    func testOneKeyIsSharedByTwoSourcesAndEveryFeature() async throws {
        let local = InMemoryCredentialStore(), cloud = InMemorySecretCloud()
        let settings = OnlineKeyStore(secrets: MirroredSecrets(local: local, cloud: cloud))
        try await settings.save(Self.key, for: .tmdb)
        // Two readers built independently (as the artwork of source A and the details of source B would be) see the same key.
        let readerA = OnlineKeyStore(secrets: MirroredSecrets(local: local, cloud: cloud))
        let readerB = OnlineKeyStore(secrets: MirroredSecrets(local: local, cloud: cloud))
        XCTAssertEqual(readerA.key(.tmdb), Self.key)
        XCTAssertEqual(readerB.key(.tmdb), Self.key)
        // The secret ids are per service, never per source (a source id is a UUID).
        XCTAssertEqual(OnlineKeyKind.allCases.map(\.secretID), ["online-key.tmdb", "online-key.omdb"])
    }

    func testNoSourceFormHasAKeyField() {
        for info in SourceCatalog.catalog(oneDriveClientID: "placeholder-client") {
            for field in info.fields {
                let text = (field.title + " " + field.prompt).lowercased()
                XCTAssertFalse(text.contains("api key") || text.contains("token") || text.contains(" key"),
                               "\(info.kind.rawValue) has a key-like field: \(field.title)")
            }
        }
    }

    func testKeySurvivesARelaunchAndComesBackOnAnotherDevice() async throws {
        let local = InMemoryCredentialStore(), cloud = InMemorySecretCloud()
        try await OnlineKeyStore(secrets: MirroredSecrets(local: local, cloud: cloud)).save(Self.key, for: .tmdb)
        // Relaunch: a new store over the same protected storage.
        XCTAssertEqual(OnlineKeyStore(secrets: MirroredSecrets(local: local, cloud: cloud)).key(.tmdb), Self.key)
        // Another Apple TV on the same iCloud account, or a reinstall: empty local storage, the encrypted iCloud copy.
        let other = OnlineKeyStore(secrets: MirroredSecrets(local: InMemoryCredentialStore(), cloud: cloud))
        XCTAssertNil(other.key(.tmdb))
        await other.reconcile()
        XCTAssertEqual(other.key(.tmdb), Self.key)
    }

    func testAKeyFromAnEarlierVersionMovesOnceIntoTheKeyStore() throws {
        let legacy = InMemoryCredentialStore()
        try legacy.setSecret(Self.key, for: OnlineKeyKind.tmdb.secretID)
        try legacy.setSecret("source-password", for: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")
        let local = InMemoryCredentialStore()
        let store = OnlineKeyStore(secrets: MirroredSecrets(local: local, cloud: InMemorySecretCloud()), legacy: legacy)
        XCTAssertEqual(store.migrateLegacy(), [.tmdb])
        XCTAssertEqual(store.key(.tmdb), Self.key)
        XCTAssertNil(try legacy.secret(for: OnlineKeyKind.tmdb.secretID), "the old item is removed")
        XCTAssertEqual(try legacy.secret(for: "3F2504E0-4F89-11D3-9A0C-0305E82C3301"), "source-password", "source passwords stay")
        XCTAssertEqual(store.migrateLegacy(), [], "a second run moves nothing")
        // A key already in the key store wins over an old one.
        try legacy.setSecret("older-placeholder", for: OnlineKeyKind.tmdb.secretID)
        XCTAssertEqual(store.migrateLegacy(), [])
        XCTAssertEqual(store.key(.tmdb), Self.key)
    }

    /// The backup export, the synced ledger records, the essentials copy and descriptions never hold the key; the backup's
    /// forbidden list holds it (also a key not yet migrated), so the backup refuses a file that does.
    func testNoKeyInTheBackupExportTheSyncedLibraryOrLogs() async throws {
        let local = InMemoryCredentialStore(), legacy = InMemoryCredentialStore(), cloud = InMemorySecretCloud()
        try legacy.setSecret("legacyplaceholderOMDB99", for: OnlineKeyKind.omdb.secretID)
        let store = OnlineKeyStore(secrets: MirroredSecrets(local: local, cloud: cloud), legacy: legacy)
        try await store.save(Self.key, for: .tmdb)

        let ledger = UserDataLedger(deviceID: "A")
        ledger.upsertSource(UDSourceDefinition(id: "a", kind: SourceKind.webdav.rawValue, name: "Disk", options: "x=1"))
        ledger.upsertSource(UDSourceDefinition(id: "b", kind: SourceKind.jellyfin.rawValue, name: "Server", options: ""))
        let export = try UDExport.export(ledger)
        let records = String(describing: ledger.allRecords())
        let kv = InMemoryKeyValueStore()
        try UDEssentialsStore(store: kv).save(from: ledger)
        let essentials = kv.data(forKey: UDEssentialsStore.storageKey).map { String(decoding: $0, as: UTF8.self) } ?? ""
        for haystack in [String(decoding: export, as: UTF8.self), records, essentials, String(describing: store),
                         String(describing: OnlineKeyStore.tmdbCredentials(Self.key))] {
            XCTAssertFalse(haystack.contains(Self.key), "the key appears in: \(haystack.prefix(80))")
        }
        XCTAssertEqual(Set(store.allValues()), [Self.key, "legacyplaceholderOMDB99"])
        XCTAssertEqual(OnlineKeyStore.masked(Self.key), "••••cdef")
    }

    func testMissingKeyMessagesAreOneShortLineThatPointsToOnlineLookup() {
        for line in [OnlineLookupText.discoverNeedsKey, OnlineLookupText.fixMatchNeedsKey, OnlineLookupText.detailsNeedKey] {
            XCTAssertTrue(line.hasSuffix("Add it in Settings > Online Lookup."), line)
            XCTAssertLessThanOrEqual(line.count, 80, line)
            XCTAssertFalse(line.contains("\n"))
        }
        XCTAssertEqual(OnlineLookupText.discoverNeedsKeyTitle, "Discover Needs a Key")
        XCTAssertEqual(DiscoverViewModel.needsKey.title, "Discover Needs a Key")
        XCTAssertFalse(OnlineLookupPrefs.freeSourcesDefault, "free data sources are off until turned on")
    }

    func testWhatIsSentNamesTheFreeSourcesAndThatNoKeyGoesToThem() {
        let text = OnlineLookupText.whatIsSent
        XCTAssertTrue(text.hasPrefix("Nothing is sent to any online service until you enter a key or turn on Free Data Sources"))
        for needle in ["Wikidata", "IntroDB", "IMDb number", "No key is sent to them", "sends nothing else"] {
            XCTAssertTrue(text.contains(needle), needle)
        }
        // TMDB never gets episode numbers; only IntroDB gets the one episode number of the video played.
        let tmdbPart = text.components(separatedBy: "With Free Data Sources on").first ?? ""
        XCTAssertFalse(tmdbPart.contains("episode number"))
    }
}

final class DetailsLayerOrderTests: XCTestCase {
    private func cast(_ names: [String], roles: [String?]? = nil) -> [TitleDetails.CastMember] {
        names.enumerated().map { TitleDetails.CastMember(id: $0.offset, name: $0.element, role: roles?[$0.offset]) }
    }

    func testServerFirstThenWikidataThenTMDBFillsTheGaps() {
        let server = TitleDetails(overview: nil, cast: cast(["Sample Actor A"]))
        let wikidata = TitleDetails(overview: nil, cast: cast(["Sample Actor B", "Sample Actor C"]))
        let tmdb = TitleDetails(overview: "A synopsis.", cast: cast(["sample actor a", "Sample Actor D"], roles: ["Role A", "Role D"]))
        let merged = LayeredDetails.merge([(.source, server), (.wikidata, wikidata), (.tmdb, tmdb)])
        XCTAssertEqual(merged.details?.overview, "A synopsis.")
        XCTAssertEqual(merged.details?.cast.map(\.name), ["Sample Actor A"], "the first layer's cast list wins")
        XCTAssertEqual(merged.details?.cast.first?.role, "Role A", "a later layer fills the role by name")
        XCTAssertEqual(merged.used, [.source, .tmdb], "Wikidata gave nothing that was used")
    }

    func testWithoutAServerLayerWikidataGivesTheCast() {
        let merged = LayeredDetails.merge([(.source, nil), (.wikidata, TitleDetails(overview: nil, cast: cast(["Sample Actor B"]))), (.tmdb, nil)])
        XCTAssertEqual(merged.details?.cast.map(\.name), ["Sample Actor B"])
        XCTAssertNil(merged.details?.overview)
        XCTAssertEqual(merged.used, [.wikidata])
        XCTAssertNil(LayeredDetails.merge([(.source, nil), (.tmdb, nil)]).details)
    }

    func testTheServiceAsksInOrderAndSkipsLayersThatAreOff() async {
        let asked = Locked<[String]>([])
        let service = LayeredDetailsService(
            source: { _ in asked.with { $0.append("source") }; return nil },
            wikidata: nil,
            tmdb: { _ in asked.with { $0.append("tmdb") }; return TitleDetails(overview: "S", cast: [.init(id: 1, name: "N", role: "R")]) })
        let result = await service.details(key: "item-1")
        XCTAssertEqual(asked.get, ["source", "tmdb"])
        XCTAssertEqual(result.used, [.tmdb])
    }

    func testWikidataFactsBecomeNamesOnly() {
        let title = WikidataTitle(qid: "Q1", label: "Sample", year: 2001, imdbID: "tt0000001", cast: ["Sample Actor A", "Sample Actor B"])
        let details = LayeredDetails.details(from: title)
        XCTAssertEqual(details?.cast.map(\.name), ["Sample Actor A", "Sample Actor B"])
        XCTAssertNil(details?.cast.first?.photo, "no Commons pictures")
        XCTAssertNil(LayeredDetails.details(from: WikidataTitle(qid: "Q2")))
    }
}

final class IntroDBSegmentTests: XCTestCase {
    static let body = #"{"intro":{"start_sec":30,"end_sec":90,"confidence":0.9},"recap":{"start_sec":0,"end_sec":25,"confidence":0.4},"outro":{"start_sec":1300,"end_sec":1400,"confidence":0.95}}"#
    let file = PlaybackLogic.FileIdentity(path: "/tv/Sample/S01E02.mkv", size: 1, duration: 1400)
    let episode = OnlineTitleRef(isEpisode: true, title: "Episode 2", seriesTitle: "Sample Show", season: 1, episode: 2, tmdbID: 77)

    private func lookup(_ transport: FakeTransport, imdb: String? = "tt0000077") -> OnlineSegmentLookup {
        let client = IntroDBClient(transport: transport, queueConfiguration: noWait, userAgent: "Tests")
        let resolver = IMDbIDResolver(tmdbExternal: { _, _ in imdb }, wikidata: nil)
        return OnlineSegmentLookup(resolver: resolver, client: client)
    }

    func testMockedAnswerGivesAnIntroOnlyAfterTheChecks() async {
        let transport = FakeTransport { _ in HTTPResponse(statusCode: 200, body: Data(Self.body.utf8)) }
        let result = await lookup(transport).segments(for: episode, file: file)
        XCTAssertEqual(result.segments.count, 3, "all three are candidates")
        let resolved = SegmentResolver.resolve(file: file, candidates: result.segments)
        XCTAssertEqual(resolved.segments.map(\.type), [.intro], "recap below 0.7 confidence; credits need a reference duration")
        XCTAssertEqual(resolved.segments.first?.start, 30)
    }

    func testFailureGivesNoSegmentNoCrashAndANote() async {
        let offline = FakeTransport { _ in throw URLError(.notConnectedToInternet) }
        let result = await lookup(offline).segments(for: episode, file: file)
        XCTAssertTrue(result.segments.isEmpty, "no segment, so no Skip button")
        XCTAssertTrue(result.note.contains("offline or no answer"), result.note)

        let server = FakeTransport { _ in HTTPResponse(statusCode: 503) }
        let fromServerError = await lookup(server).segments(for: episode, file: file)
        XCTAssertTrue(fromServerError.segments.isEmpty)
        let garbage = FakeTransport { _ in HTTPResponse(statusCode: 200, body: Data("<html>".utf8)) }
        let fromGarbage = await lookup(garbage).segments(for: episode, file: file)
        XCTAssertTrue(fromGarbage.segments.isEmpty)
    }

    func testNoIMDbIDMeansNothingIsAsked() async {
        let transport = FakeTransport { _ in HTTPResponse(statusCode: 200, body: Data(Self.body.utf8)) }
        let result = await lookup(transport, imdb: nil).segments(for: episode, file: file)
        XCTAssertTrue(result.segments.isEmpty)
        XCTAssertEqual(transport.count, 0)
    }

    func testOfflineWikidataGivesNoIMDbIDAndNoCrash() async {
        let offline = FakeTransport { _ in throw URLError(.notConnectedToInternet) }
        let wikidata = WikidataClient(transport: offline, queueConfiguration: noWait, userAgent: "Tests")
        let resolver = IMDbIDResolver(tmdbExternal: nil, wikidata: wikidata)
        let id = await resolver.imdbID(for: OnlineTitleRef(isEpisode: false, title: "Sample Film", year: 2001, tmdbID: 5))
        XCTAssertNil(id)
    }

    /// The collector asks the online lookup only when the file has no markers, and merges what it gives.
    func testTheCollectorAsksOnlineOnlyWithoutLocalMarkers() async {
        let asked = Locked(0)
        let online: @Sendable (PlaybackLogic.FileIdentity) async -> OnlineSegmentResult = { file in
            asked.with { $0 += 1 }
            return OnlineSegmentResult(segments: [SkipSegment(type: .intro, start: 30, end: 90, source: .onlineDatabase, confidence: 0.9, file: file)],
                                       note: "Online timings (IntroDB): 1 found")
        }
        let info = SegmentFileInfo(path: "/tv/Sample/S01E02.mp4", size: 1, duration: 1400)
        let none = await SegmentCollector().collect(file: info, source: nil, marks: [], online: online)
        XCTAssertEqual(none.segments.map(\.type), [.intro])
        XCTAssertTrue(none.notes.contains("Online timings (IntroDB): 1 found"))
        XCTAssertEqual(asked.get, 1)

        let mark = UDSegmentMark(itemKey: "k", kind: "intro", start: 20, end: 70, fileDuration: 1400)
        let marked = await SegmentCollector().collect(file: info, source: nil, marks: [mark], online: online)
        XCTAssertEqual(marked.segments.first?.source, .userMarked)
        XCTAssertEqual(asked.get, 1, "a user mark means the online lookup is not asked")

        let off = await SegmentCollector().collect(file: info, source: nil, marks: [], online: nil)
        XCTAssertTrue(off.segments.isEmpty, "Free Data Sources off: nothing online, no Skip button")
    }
}
