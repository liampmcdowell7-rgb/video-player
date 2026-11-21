import Foundation
import Observation
import VideoPlayerCore
import LibraryIndex
import UserData
import MetadataOnline
import AppLogic

/// Everything that talks to the online lookup services, built only from the keys the user entered (one app-wide key per
/// service, #26) and the Free Data Sources switch. With no key and the switch off nothing here can send anything: the pieces
/// that would are simply not created, and the screens say what is needed (docs/ARTWORK_DISCOVER.md, docs/DATA_SOURCES.md).
@MainActor
@Observable
final class OnlineServices {
    let keys: OnlineKeyStore
    /// Bumped whenever a key is saved or removed; screens that depend on the lookups reload on it.
    private(set) var keyRevision = 0
    private(set) var hasCatalogueKey = false
    private(set) var resolver: any ArtworkResolving
    private(set) var searcher: any MatchSearching = UnavailableMatchSearcher()
    private(set) var recorder: (any MatchChoiceRecording)?
    private(set) var discoverSource: (any DiscoverDataSource)?
    /// The title search that sorts Needs Review files (signal d, docs/SORTING.md); nil without a key.
    private(set) var sortLookup: (any SortLookup)?
    /// #26: Wikidata and IntroDB, created only while Free Data Sources is on (no key needed, none sent).
    private(set) var freeSourcesOn = false
    @ObservationIgnored private(set) var wikidata: WikidataClient?
    @ObservationIgnored private(set) var segmentLookup: OnlineSegmentLookup?
    @ObservationIgnored private var tmdbClient: TMDBClient?
    let imageSession: URLSession

    @ObservationIgnored private let store: SQLiteLibraryStore
    @ObservationIgnored private let reader: any SidecarReading
    @ObservationIgnored private let diskCache: ArtworkDiskCache
    /// Plex's own synopsis and pictures, asked only for Plex files (R307).
    @ObservationIgnored private let server: (any ServerMetadataProviding)?

    init(keys: OnlineKeyStore, store: SQLiteLibraryStore, reader: any SidecarReading, server: (any ServerMetadataProviding)? = nil) {
        self.keys = keys
        self.store = store
        self.reader = reader
        self.server = server
        self.diskCache = ArtworkDiskCache(directory: ArtworkFolders.sidecars)
        self.imageSession = ArtworkFolders.makeImageSession()
        self.resolver = EngineArtworkResolver(engine: ArtworkEngine(store: store, cache: diskCache, reader: reader, online: nil, server: server))
        rebuild()
    }

    /// The two-letter region the where-to-watch lists use (Settings > Online Lookup).
    var region: String { OnlineLookupPrefs.normalizedRegion(UserDefaults.standard.string(forKey: OnlineLookupPrefs.regionKey)) }

    /// Fix Match choices are the user's own decisions, so they are kept in Application Support, not in Caches.
    /// PROVISIONAL: kept on this device only; alternative: a ledger record so they sync (needs a Schema.swift record type).
    /// Also read by the iCloud backup (docs/BACKUP.md), so a reinstall gets the choices back.
    static var matchFileURL: URL {
        let base = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
        return base.appendingPathComponent("matches.json")
    }

    private var matchFile: URL { Self.matchFileURL }

    /// Rebuilds every piece from the keys currently stored. Call after a key is saved or removed.
    func rebuild() {
        hasCatalogueKey = keys.has(.tmdb)
        rebuildFreeSources()
        // UI-test modes never send anything: a key in the in-memory store (-UITestFakeTMDBKey) shows as set, but no client
        // that could use it is made.
        guard let key = keys.key(.tmdb), !Self.isUITestLaunch else {
            tmdbClient = nil
            rebuildSegmentLookup()
            resolver = EngineArtworkResolver(engine: ArtworkEngine(store: store, cache: diskCache, reader: reader, online: nil, server: server))
            searcher = UnavailableMatchSearcher()
            recorder = nil
            discoverSource = nil
            sortLookup = nil
            keyRevision += 1
            return
        }
        let client = TMDBClient(credentials: OnlineKeyStore.tmdbCredentials(key), transport: URLSessionTransport(),
                                cache: JSONFileMetadataCache(directory: ArtworkFolders.metadata), region: region)
        let service = FixMatchService(engine: MatchEngine(provider: client), store: JSONFileMatchStore(url: matchFile))
        let provider = TMDBArtworkProvider(client: client, matcher: service, store: store)
        resolver = EngineArtworkResolver(engine: ArtworkEngine(store: store, cache: diskCache, reader: reader, online: provider, server: server))
        searcher = TMDBMatchSearcher(client: client)
        recorder = StoredMatchRecorder(service: service, store: store)
        discoverSource = client
        sortLookup = MatchEngine(provider: client)
        tmdbClient = client
        rebuildSegmentLookup()
        keyRevision += 1
    }

    private static var isUITestLaunch: Bool {
        #if DEBUG
        return UITestMode.current != .off
        #else
        return false
        #endif
    }

    /// The User-Agent Wikidata asks for: the app's name and version and where to find it (docs/DATA_SOURCES.md).
    // design-lint:allow a protocol token sent in the User-Agent header, never shown on screen
    static var userAgent: String { "VideoPlayer/\(AppInfo.version) (\(LicenseNotices.repositoryURL); open-source tvOS player)" }

    private func rebuildFreeSources() {
        freeSourcesOn = UserDefaults.standard.object(forKey: OnlineLookupPrefs.freeSourcesKey) as? Bool ?? OnlineLookupPrefs.freeSourcesDefault
        #if DEBUG
        // UI-test modes never send anything: the switch can show On, but no client is made.
        if UITestMode.current != .off { wikidata = nil; return }
        #endif
        // #29: typed steps instead of a ternary between a client and nil.
        guard freeSourcesOn else { wikidata = nil; return }
        let cache = JSONFileMetadataCache(directory: ArtworkFolders.metadata)
        let client = WikidataClient(transport: URLSessionTransport(), cache: cache, userAgent: Self.userAgent, language: Self.wikidataLanguage)
        wikidata = client
    }

    /// The language Wikidata answers in: the device's first preferred language, two letters. The stored-only client of the
    /// person page (R341) uses the same, so it reads the same stored answers.
    static var wikidataLanguage: String {
        var language = "en"
        if let preferred: String = Locale.preferredLanguages.first { language = String(preferred.prefix(2)) }
        return language
    }

    private func rebuildSegmentLookup() {
        guard freeSourcesOn, let wikidata else { segmentLookup = nil; return }
        let external: IMDbIDResolver.TMDBExternal? = IMDbIDResolver.tmdbExternal(tmdbClient)
        let introDB = IntroDBClient(transport: URLSessionTransport(), cache: JSONFileMetadataCache(directory: ArtworkFolders.metadata),
                                    userAgent: Self.userAgent)
        segmentLookup = OnlineSegmentLookup(resolver: IMDbIDResolver(tmdbExternal: external, wikidata: wikidata), client: introDB)
    }

    func saveKey(_ text: String, for kind: OnlineKeyKind) async throws {
        try await keys.save(text, for: kind)
        rebuild()
    }

    func removeKey(_ kind: OnlineKeyKind) async throws {
        try await keys.remove(kind)
        rebuild()
    }

    /// Run at start-up: a key saved on another device arrives here, a key only on this device goes up.
    func reconcileKeys() async {
        await keys.reconcile()
        rebuild()
    }

    func resolveArtwork(key: String) async -> ArtworkResult { await resolver.resolve(key: key) }

    /// Title-logo pictures for a movie or show page, in the device's first preferred language order (#15 9.3).
    func logoCandidates(key: String) async -> [LogoCandidate] {
        await resolver.logoCandidates(key: key, userLanguage: Locale.preferredLanguages.first)
    }

    /// The backdrop of a movie or show page (#15 6.2): fan art next to the media, then the matched online backdrop.
    func backdrop(key: String) async -> ArtworkResult {
        await resolver.backdrop(key: key, userLanguage: Locale.preferredLanguages.first)
    }

    /// Synopsis and cast of a movie page ("item-N", #15 6.2) or a show page ("series-N", #22 B), layered (#26 item 6,
    /// PROVISIONAL R210): the source's own details (Plex's synopsis for Plex files, R307; none for other sources), then
    /// Wikidata while Free Data Sources is on, then TMDB with the user's key. Nil when no layer has anything.
    func details(key: String) async -> TitleDetails? {
        #if DEBUG
        // #21 D: the screenshot job's fake synopsis and cast (no key, no network). Not compiled into Release.
        if UITestMode.current == .fixtures { return await UITestFixtureDetails.details(key: key, store: store) }
        #endif
        // #29: typed steps; the closures are built in AppLogic (OnlineComposition.swift), where the package tests cover them.
        var tmdbSource: (any TitleDetailsSource)? = nil
        if hasCatalogueKey { tmdbSource = resolver }
        let service: LayeredDetailsService = LayeredDetailsService.online(store: store, wikidata: wikidata, tmdb: tmdbSource, server: server, region: region, reader: reader)
        let layered: LayeredDetails = await service.details(key: key)
        return layered.details
    }

    /// R341 (Decided by the owner, 21 Nov 2026): a title's synopsis and cast from what is already stored on this Apple TV,
    /// for the person page. The same layers as `details(key:)`, Wikidata while Free Data Sources is on and TMDB while a key
    /// is set, but built on `NoNetworkTransport`: an answer that is not stored is missing, and nothing is sent. The media
    /// server's layer is left out, since asking it would be a request.
    func storedDetails() -> PersonTitles.Details {
        #if DEBUG
        // #21 D: the screenshot job's fake cast, as on the movie and show pages.
        if UITestMode.current == .fixtures {
            let fixtureStore: SQLiteLibraryStore = store
            let fixtures: PersonTitles.Details = { @Sendable (key: String) async -> TitleDetails? in
                await UITestFixtureDetails.details(key: key, store: fixtureStore)
            }
            return fixtures
        }
        #endif
        // #29: typed steps, no ternaries between a client and nil.
        let cache = JSONFileMetadataCache(directory: ArtworkFolders.metadata)
        var tmdb: (any TitleDetailsSource)? = nil
        if let key = keys.key(.tmdb), !Self.isUITestLaunch {
            let client: TMDBClient = PersonTitles.storedClient(credentials: OnlineKeyStore.tmdbCredentials(key), cache: cache, region: region)
            tmdb = StoredTMDBDetails(store: store, client: client)
        }
        var wikidata: WikidataClient? = nil
        if freeSourcesOn, !Self.isUITestLaunch {
            wikidata = PersonTitles.storedWikidata(cache: cache, userAgent: Self.userAgent, language: Self.wikidataLanguage)
        }
        let service: LayeredDetailsService = LayeredDetailsService.online(store: store, wikidata: wikidata, tmdb: tmdb, server: nil, region: region)
        let details: PersonTitles.Details = { @Sendable (key: String) async -> TitleDetails? in
            let layered: LayeredDetails = await service.details(key: key)
            return layered.details
        }
        return details
    }

    /// Bytes of one picture for the Top Shelf folder (a cached file, or a download of the matched poster). Nil when there is none.
    func artworkBytes(key: String) async -> Data? {
        switch await resolver.resolve(key: key) {
        case .file(let url): return try? Data(contentsOf: url)
        case .remote(let url):
            guard let (data, response) = try? await imageSession.data(from: url), (response as? HTTPURLResponse)?.statusCode == 200,
                  data.count <= ArtworkEngine.maxSidecarBytes else { return nil }
            return data
        case .none: return nil
        }
    }
}
