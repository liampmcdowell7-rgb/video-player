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
    /// R381: the user-data ledger that the iCloud sync uploads; Fix Match choices are written into it (`CloudMatchStore`).
    /// Nil keeps them in matches.json only (as before R381).
    @ObservationIgnored private let ledger: UserDataLedger?
    /// R455: the user's artwork choices (the user layer), asked by the engine before every source.
    /// R456: Language > Artwork (Auto follows the Apple TV's first language): the order of language in logos, backgrounds and the gallery.
    static var artworkLanguage: String {
        LanguagePreference.resolved(UserDefaults.standard.string(forKey: AppPreference.artworkLanguage.rawValue), system: Locale.preferredLanguages)
    }

    /// R456: read at each lookup, so a change in Settings applies without rebuilding the engine.
    @Sendable private static func preferLocalArtwork() -> Bool {
        UserDefaults.standard.object(forKey: AppPreference.preferLocalArtwork.rawValue) as? Bool ?? true
    }

    private static func choices(_ ledger: UserDataLedger?, _ store: SQLiteLibraryStore) -> (any ArtworkOverriding)? {
        ledger.map { UserLayerArtworkOverrides(ledger: $0, store: store) }
    }

    init(keys: OnlineKeyStore, store: SQLiteLibraryStore, reader: any SidecarReading, server: (any ServerMetadataProviding)? = nil,
         ledger: UserDataLedger? = nil) {
        self.keys = keys
        self.ledger = ledger
        self.store = store
        self.reader = reader
        self.server = server
        self.diskCache = ArtworkDiskCache(directory: ArtworkFolders.sidecars)
        self.imageSession = ArtworkFolders.makeImageSession()
        self.resolver = EngineArtworkResolver(engine: ArtworkEngine(store: store, cache: diskCache, reader: reader, online: nil, server: server, overrides: Self.choices(ledger, store), preferLocalArtwork: Self.preferLocalArtwork))
        rebuild()
    }

    /// The two-letter region the where-to-watch lists use (Settings > Online Lookup).
    var region: String { OnlineLookupPrefs.normalizedRegion(UserDefaults.standard.string(forKey: OnlineLookupPrefs.regionKey)) }

    /// Fix Match choices are the user's own decisions, so they are kept in Application Support, not in Caches.
    /// R381 (audit #14, PROVISIONAL): this file is now the local cache; the lasting copy is the ledger's "fixmatch" records
    /// in iCloud (AppLogic `CloudMatchStore`), and the file is rebuilt from them when it is missing. Alternative: keep the
    /// choices on this device only (before R381). Also read by the iCloud backup (docs/BACKUP.md).
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
            resolver = EngineArtworkResolver(engine: ArtworkEngine(store: store, cache: diskCache, reader: reader, online: nil, server: server, overrides: Self.choices(ledger, store), preferLocalArtwork: Self.preferLocalArtwork))
            searcher = UnavailableMatchSearcher()
            recorder = nil
            discoverSource = nil
            sortLookup = nil
            keyRevision += 1
            return
        }
        let client = TMDBClient(credentials: OnlineKeyStore.tmdbCredentials(key), transport: URLSessionTransport(),
                                cache: JSONFileMetadataCache(directory: ArtworkFolders.metadata), region: region)
        let matchStore: any MatchStore = ledger.map { CloudMatchStore(url: matchFile, ledger: $0) } ?? JSONFileMatchStore(url: matchFile)
        let service = FixMatchService(engine: MatchEngine(provider: client), store: matchStore)
        let provider = TMDBArtworkProvider(client: client, matcher: service, store: store)
        resolver = EngineArtworkResolver(engine: ArtworkEngine(store: store, cache: diskCache, reader: reader, online: provider, server: server, overrides: Self.choices(ledger, store), preferLocalArtwork: Self.preferLocalArtwork))
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
        // R456: Language > Metadata (Auto follows the Apple TV's first language).
        return LanguagePreference.resolved(UserDefaults.standard.string(forKey: AppPreference.metadataLanguage.rawValue), system: Locale.preferredLanguages)
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

    // MARK: Artwork choices (R455)

    /// A picture was chosen or reset: every card, hero and page that draws artwork asks again.
    func artworkChanged() { keyRevision += 1 }

    /// The candidates of one kind. Online pictures only while Online Lookup has its key (R209); the others always.
    func artworkGallery(key: String, kind: ArtworkGalleryKind) async -> ArtworkGallery {
        #if DEBUG
        if UITestMode.current == .fixtures { return UITestFixtureGallery.gallery(kind) }
        #endif
        return await resolver.gallery(key: key, kind: kind, userLanguage: Self.artworkLanguage, onlineOn: hasCatalogueKey)
    }

    func thumbnailURL(path: String, kind: ArtworkGalleryKind) async -> URL? { await resolver.thumbnailURL(path: path, kind: kind) }

    /// A candidate's small picture: an online address, or the cached file of a picture from a source or the server.
    func thumbnail(of candidate: ArtworkCandidate, key: String, kind: ArtworkGalleryKind) async -> URL? {
        switch candidate.origin {
        case let .online(path): return await resolver.thumbnailURL(path: path, kind: kind)
        default:
            if case .file(let url) = await resolver.localPicture(candidate, key: key) { return url }
            return nil
        }
    }

    /// Copies the chosen picture into the user-artwork folder (the full size is fetched only here) and returns its file name,
    /// or the reason it could not (R455 item 4: it then works offline and is in the backup).
    func storeChosenPicture(_ candidate: ArtworkCandidate, key: String, kind: ArtworkGalleryKind) async -> (name: String?, problem: String?) {
        switch candidate.origin {
        case let .online(path):
            guard let url = await resolver.fullURL(path: path, kind: kind) else { return (nil, "Online pictures need Online Lookup in Settings.") }
            return await UserArtworkFolder.download(url.absoluteString)
        default:
            guard case .file(let url) = await resolver.localPicture(candidate, key: key) else { return (nil, "The picture could not be read.") }
            return UserArtworkFolder.add(fileAt: url)
        }
    }

    /// Title-logo pictures for a movie or show page, in the device's first preferred language order (#15 9.3).
    func logoCandidates(key: String) async -> [LogoCandidate] {
        await resolver.logoCandidates(key: key, userLanguage: Self.artworkLanguage)
    }

    /// The backdrop of a movie or show page (#15 6.2): fan art next to the media, then the matched online backdrop.
    func backdrop(key: String) async -> ArtworkResult {
        await resolver.backdrop(key: key, userLanguage: Self.artworkLanguage)
    }

    /// R387: the episode page's hero picture, the episode's own still only (no show poster); `.none` without one.
    func episodeStill(key: String) async -> ArtworkResult {
        await resolver.episodeStill(key: key)
    }

    /// Synopsis and cast of a movie page ("item-N", #15 6.2) or a show page ("series-N", #22 B), layered (#26 item 6,
    /// PROVISIONAL R210): the source's own details (Plex's synopsis for Plex files, R307; none for other sources), then
    /// Wikidata while Free Data Sources is on, then TMDB with the user's key. Nil when no layer has anything.
    func details(key: String) async -> TitleDetails? {
        await layeredDetails(key: key).details
    }

    /// The same details with the layer each part came from (R380: the player needs the rating's layer to decide whether it
    /// replaces the rating set before playback started).
    func layeredDetails(key: String) async -> LayeredDetails {
        #if DEBUG
        // #21 D: the screenshot job's fake synopsis and cast (no key, no network). Not compiled into Release.
        if UITestMode.current == .fixtures {
            return LayeredDetails(details: await UITestFixtureDetails.details(key: key, store: store), used: [])
        }
        #endif
        // #29: typed steps; the closures are built in AppLogic (OnlineComposition.swift), where the package tests cover them.
        var tmdbSource: (any TitleDetailsSource)? = nil
        if hasCatalogueKey { tmdbSource = resolver }
        let service: LayeredDetailsService = LayeredDetailsService.online(store: store, wikidata: wikidata, tmdb: tmdbSource, server: server, region: region, reader: reader)
        return await service.details(key: key)
    }

    /// R380: the source's own rating for a file, only from what the source client already holds (no request).
    func heldSourceRating(for file: StoredFile) async -> String? {
        await server?.heldContentRating(for: file)
    }

    /// R383: the next episode's still for the Up Next card, only from the artwork cache (nothing read from a source, no
    /// request); nil when it is not cached or the bytes are not a usable image (`UpNextPreview`).
    func upNextStill(itemID: Int64) async -> Data? {
        guard let url = await UpNextPreview.cachedStill(itemID: itemID, store: store, cache: diskCache, server: server),
              let data = try? Data(contentsOf: url), UpNextPreview.usable(data) else { return nil }
        return data
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
        await bytes(of: await resolver.resolve(key: key))
    }

    /// R394: the bytes of an episode's own still (never the show's poster), for the system player's Info tab. Nil
    /// without one.
    func episodeStillBytes(key: String) async -> Data? {
        await bytes(of: await resolver.episodeStill(key: key))
    }

    private func bytes(of result: ArtworkResult) async -> Data? {
        switch result {
        case .file(let url): return try? Data(contentsOf: url)
        case .remote(let url):
            guard let (data, response) = try? await imageSession.data(from: url), (response as? HTTPURLResponse)?.statusCode == 200,
                  data.count <= ArtworkEngine.maxSidecarBytes else { return nil }
            return data
        case .none: return nil
        }
    }
}
