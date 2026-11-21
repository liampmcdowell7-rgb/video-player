import Foundation
import VideoPlayerCore

/// One Plex Media Server as a source (docs/PLEX_SOURCE.md sections 4 and 5; OPEN_QUESTIONS R304, R305).
///
/// Read only: every request is a GET (a test fails on any other method, R306). The tree comes from each Part's file path
/// (`PlexTree`); files are read with ranged GETs of the Part's key with the server token in a header. The server's own
/// titles never name files: the app's scanner and matcher work on the file names, as for every other source.
///
/// Re-read 20 Nov 2026 (developer.plex.tv/pms): paging with `X-Plex-Container-Start` and `X-Plex-Container-Size`, "Both
/// headers should be sent in order to request paginated content" (read); without them a list "should only return the
/// first 20 Metadata objects" (read). `allLeaves`: "Get the leaves for a metadata item such as the episodes in a show"
/// (read). `/library/sections` with `Directory` and `Location` (field names UNVERIFIED; only the path was in the text).
public actor PlexClient: MediaSource {
    private let baseURL: URL
    private let token: String
    private let http: PlexHTTP
    private let pageSize: Int
    private var treeTask: Task<PlexTree, Error>?
    private var treeStarted: Date?
    /// How long a listing of the server is reused before it is read again (R305): browsing, scanning and starting
    /// playback within this time cost no new library requests; a file added on the server shows up after it.
    private let treeLifetime: TimeInterval
    private let now: @Sendable () -> Date
    /// Writes watch state to this server (R308, R309); same address, token and transport as the client.
    private let writer: PlexWatchWriter

    /// Parts skipped because their file is outside every section folder (shown nowhere; counted for the status line).
    public private(set) var skippedParts = 0

    /// - Parameters:
    ///   - baseURL: the connection that answered (R303), for example `https://192-168-1-20.<id>.plex.direct:32400`.
    ///   - token: the server's access token (the source secret).
    public init(baseURL: URL, token: String, identity: PlexClientIdentity, transport: HTTPTransport = URLSessionTransport(),
                pageSize: Int = 200, treeLifetime: TimeInterval = 300, now: @escaping @Sendable () -> Date = { Date() }) {
        self.baseURL = baseURL
        self.token = token
        self.http = PlexHTTP(identity: identity, transport: transport)
        self.writer = PlexWatchWriter(baseURL: baseURL, token: token, identity: identity, transport: transport)
        self.pageSize = max(1, pageSize)
        self.treeLifetime = treeLifetime
        self.now = now
    }

    private static let sharedLock = NSLock()
    nonisolated(unsafe) private static var shared: [String: PlexClient] = [:]

    /// One client per server address and token for the whole app (R305). The app builds a new source object for every
    /// scan, browse and play; sharing the client keeps one listing of the server instead of reading the whole library
    /// again each time. Kept in memory only.
    public static func shared(baseURL: URL, token: String, identity: PlexClientIdentity) -> PlexClient {
        let key = [baseURL.absoluteString, identity.clientIdentifier, token].joined(separator: " ")
        return sharedLock.withLock {
            if let client = shared[key] { return client }
            let client = PlexClient(baseURL: baseURL, token: token, identity: identity)
            shared[key] = client
            return client
        }
    }

    // MARK: MediaSource

    public nonisolated var kind: SourceKind { .plex }

    public nonisolated var capabilities: SourceCapabilities {
        SourceCapabilities(authMethods: [.pinLink, .token], byteRanges: true, changeSignals: [.serverToken, .size],
                           discovery: false, directPlaybackURL: true,
                           alwaysEncrypted: false)   // local HTTP is allowed (R303)
    }

    /// Checks the token: the section list needs it.
    public func authenticate() async throws {
        _ = try await sections()
    }

    public func list(_ path: String) async throws -> [SourceEntry] {
        let tree = try await currentTree()
        guard let node = tree.node(at: path) else { throw SourceError.notFound }
        return node.entry.isDirectory ? tree.children(of: path) : []
    }

    public func info(_ path: String) async throws -> SourceEntry {
        let tree = try await currentTree()
        guard let node = tree.node(at: path) else { throw SourceError.notFound }
        return node.entry
    }

    public func read(_ path: String, range: ByteRange) async throws -> Data {
        if range.length == 0 { return Data() }
        let url = try await partURL(path)
        let last = range.offset + range.length - 1
        let response = try await http.send(http.request("GET", url, token: token, extra: ["Range": "bytes=\(range.offset)-\(last)"]))
        switch response.statusCode {
        case 206: return response.body.count > Int(range.length) ? response.body.prefix(Int(range.length)) : response.body
        case 200: throw SourceError.rangesNotSupported
        case 416: throw SourceError.rangeNotSatisfiable
        default: try PlexHTTP.check(response); throw SourceError.httpStatus(response.statusCode)
        }
    }

    public func playbackAccess(for path: String) async throws -> PlaybackAccess {
        let url = try await partURL(path)
        return .url(url, headers: http.identity.headers(token: token))
    }

    /// Reads the sections again (after the server added or removed files).
    public func refresh() async throws {
        treeTask = nil
        _ = try await currentTree()
    }

    // MARK: Playback (stage 5)

    /// The name of the video format when the Apple TV cannot play this file without the server converting it, else nil
    /// (R305). The app shows "cannot play this file" for it instead of starting the player; the server's transcoder is
    /// never asked.
    public func conversionNeeded(at path: String) async throws -> String? {
        guard let node = try await currentTree().node(at: path), !node.entry.isDirectory else { throw SourceError.notFound }
        return PlexPlayability.refusal(for: node.media)
    }

    // MARK: Server watch state and metadata (stages 6 and 7)

    /// What the server knew about a file when the tree was read: the item, its Media and Part, its watch state.
    public func serverItem(at path: String) async throws -> PlexServerItem? {
        guard let node = try await currentTree().node(at: path), let metadata = node.metadata else { return nil }
        return PlexServerItem(metadata: metadata, media: node.media, viewOffsetSeconds: node.viewOffsetSeconds,
                              viewCount: node.viewCount, lastViewedAt: node.lastViewedAt)
    }

    /// Every file with the server's view of it (for the one-time watch-state seed, R306).
    public func serverItems() async throws -> [String: PlexServerItem] {
        let tree = try await currentTree()
        var out: [String: PlexServerItem] = [:]
        for node in tree.files {
            guard let metadata = node.metadata else { continue }
            out[node.entry.path] = PlexServerItem(metadata: metadata, media: node.media, viewOffsetSeconds: node.viewOffsetSeconds,
                                                  viewCount: node.viewCount, lastViewedAt: node.lastViewedAt)
        }
        return out
    }

    /// An image path from the server (`thumb`, `art`) as a full URL. The token goes in the header list returned with it,
    /// never into the URL (R300).
    public nonisolated func imageRequest(_ serverPath: String) -> (url: URL, headers: [String: String])? {
        guard serverPath.hasPrefix("/"), let url = URL(string: serverPath, relativeTo: baseURL)?.absoluteURL else { return nil }
        return (url, http.identity.headers(token: token))
    }

    /// The bytes of a picture the server keeps (`thumb`, `art`), with the token in a header (R307). Larger than `maxBytes`:
    /// refused, so one oversized picture cannot fill memory.
    public func imageData(_ serverPath: String, maxBytes: Int) async throws -> Data {
        guard let (url, _) = imageRequest(serverPath) else { throw SourceError.notFound }
        let response = try await http.send(http.request("GET", url, token: token))
        try PlexHTTP.check(response)
        guard response.statusCode == 200 else { throw SourceError.httpStatus(response.statusCode) }
        guard response.body.count <= maxBytes else { throw SourceError.malformedResponse }
        return response.body
    }

    // MARK: Tree

    private func currentTree() async throws -> PlexTree {
        if let running = treeTask, let started = treeStarted, now().timeIntervalSince(started) < treeLifetime {
            return try await running.value
        }
        let task = Task { try await self.buildTree() }
        treeTask = task
        treeStarted = now()
        do {
            let tree = try await task.value
            skippedParts = tree.skippedParts
            return tree
        } catch {
            treeTask = nil
            throw error
        }
    }

    private func buildTree() async throws -> PlexTree {
        let sections = try await sections().filter { ["movie", "show"].contains(($0.type ?? "").lowercased()) }
        var items: [PlexMetadata] = []
        for section in sections {
            for item in try await pagedList("/library/sections/\(section.key)/all") {
                if (item.type ?? "").lowercased() == "show" {
                    items += try await pagedList("/library/metadata/\(item.ratingKey)/allLeaves")
                } else {
                    items.append(item)
                }
            }
        }
        let libraries = sections.map { PlexLibrary(title: $0.title, roots: $0.locations.map(PlexTree.components(of:))) }
        return PlexTree.make(libraries: libraries, items: items)
    }

    private func sections() async throws -> [PlexDirectory] {
        let response = try await http.send(http.request("GET", baseURL.appendingPathComponent("library/sections"), token: token))
        return try PlexHTTP.decode(PlexEnvelope.self, from: response).container.directories
    }

    /// Every item of a list, page by page, always sending both paging headers.
    private func pagedList(_ path: String) async throws -> [PlexMetadata] {
        var all: [PlexMetadata] = []
        var start = 0
        while true {
            try Task.checkCancellation()
            let request = http.request("GET", baseURL.appendingPathComponent(String(path.dropFirst())), token: token,
                                       extra: ["X-Plex-Container-Start": String(start), "X-Plex-Container-Size": String(pageSize)])
            let container = try PlexHTTP.decode(PlexEnvelope.self, from: try await http.send(request)).container
            all += container.metadata
            let received = container.size ?? container.metadata.count
            start += received
            if received == 0 || container.metadata.isEmpty { break }
            if let total = container.totalSize, start >= total { break }
            if container.totalSize == nil && received < pageSize { break }
        }
        return all
    }

    private func partURL(_ path: String) async throws -> URL {
        guard let node = try await currentTree().node(at: path), let key = node.part?.key, !node.entry.isDirectory else {
            throw SourceError.notFound
        }
        guard let url = URL(string: key, relativeTo: baseURL)?.absoluteURL else { throw SourceError.notFound }
        return url
    }
}

// R309: the app's watch sync asks a Plex source for its writer and for the ratingKey of a file.
extension PlexClient: ServerWatchSource {
    public nonisolated var watchWriter: any ServerWatchWriting { writer }

    public func serverItemKey(at path: String) async throws -> String? {
        try await serverItem(at: path)?.metadata.ratingKey
    }

    public func serverWatchState(at path: String) async throws -> ServerWatchState? {
        try await serverItem(at: path).map(Self.watchState)
    }

    public func serverWatchStates() async throws -> [String: ServerWatchState] {
        try await serverItems().mapValues(Self.watchState)
    }

    static func watchState(_ item: PlexServerItem) -> ServerWatchState {
        ServerWatchState(itemKey: item.metadata.ratingKey, played: (item.viewCount ?? 0) > 0, position: item.viewOffsetSeconds,
                         lastViewedAt: item.lastViewedAt, duration: item.metadata.runtimeSeconds.map(Double.init))
    }
}

/// The server's view of one file (read once; never written back, R306).
public struct PlexServerItem: Equatable, Sendable {
    public var metadata: PlexMetadata
    public var media: PlexMedia?
    public var viewOffsetSeconds: Double?
    public var viewCount: Int?
    public var lastViewedAt: Date?
}
