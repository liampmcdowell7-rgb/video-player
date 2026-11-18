import Foundation
import Observation
import VideoPlayerCore
import LibraryIndex
import UserData
import MetadataOnline
import AppLogic

/// Everything that talks to the online lookup services, built only from the keys the user entered. With no key nothing here
/// can send anything: the pieces that would are simply not created, and the screens say what is needed (docs/ARTWORK_DISCOVER.md).
@MainActor
@Observable
final class OnlineServices {
    let keys: OnlineKeyStore
    /// Bumped whenever a key is saved or removed; screens that depend on the lookups reload on it.
    private(set) var keyRevision = 0
    private(set) var hasCatalogueKey = false
    private(set) var hasRatingsKey = false
    private(set) var resolver: any ArtworkResolving
    private(set) var searcher: any MatchSearching = UnavailableMatchSearcher()
    private(set) var recorder: (any MatchChoiceRecording)?
    private(set) var discoverSource: (any DiscoverDataSource)?
    let imageSession: URLSession

    @ObservationIgnored private let store: SQLiteLibraryStore
    @ObservationIgnored private let reader: any SidecarReading
    @ObservationIgnored private let diskCache: ArtworkDiskCache

    init(keys: OnlineKeyStore, store: SQLiteLibraryStore, reader: any SidecarReading) {
        self.keys = keys
        self.store = store
        self.reader = reader
        self.diskCache = ArtworkDiskCache(directory: ArtworkFolders.sidecars)
        self.imageSession = ArtworkFolders.makeImageSession()
        self.resolver = EngineArtworkResolver(engine: ArtworkEngine(store: store, cache: diskCache, reader: reader, online: nil))
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
        hasRatingsKey = keys.has(.omdb)
        guard let key = keys.key(.tmdb) else {
            resolver = EngineArtworkResolver(engine: ArtworkEngine(store: store, cache: diskCache, reader: reader, online: nil))
            searcher = UnavailableMatchSearcher()
            recorder = nil
            discoverSource = nil
            keyRevision += 1
            return
        }
        let client = TMDBClient(credentials: OnlineKeyStore.tmdbCredentials(key), transport: URLSessionTransport(),
                                cache: JSONFileMetadataCache(directory: ArtworkFolders.metadata), region: region)
        let service = FixMatchService(engine: MatchEngine(provider: client), store: JSONFileMatchStore(url: matchFile))
        let provider = TMDBArtworkProvider(client: client, matcher: service, store: store)
        resolver = EngineArtworkResolver(engine: ArtworkEngine(store: store, cache: diskCache, reader: reader, online: provider))
        searcher = TMDBMatchSearcher(client: client)
        recorder = StoredMatchRecorder(service: service, store: store)
        discoverSource = client
        keyRevision += 1
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
