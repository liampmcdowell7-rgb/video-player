import Foundation
import VideoPlayerCore

/// Jellyfin as a source. Direct play only: files are always requested with `static=true`, so the
/// server never transcodes. The file tree comes from each item's path (see `JFTree`).
public actor JellyfinClient: MediaSource {
    private let baseURL: URL
    private let credentials: JellyfinCredentials
    private let transport: HTTPTransport
    private let clientName: String
    private let deviceName: String
    private let deviceID: String
    private let clientVersion: String
    private let pageSize: Int
    private let scanPolicy: JellyfinScanPolicy

    private var token: String?
    private var treeTask: Task<JFTree, Error>?
    private var knownSizes: [String: Int64] = [:]

    /// False when the last library scan wait ran into its timeout (the listing may be incomplete).
    public private(set) var scanSettled = false
    /// False when the server did not allow reading the library folders and the tree uses one
    /// library named "Library" instead (for a user that is not an administrator).
    public private(set) var usedLibraryFolders = true

    /// - Parameters:
    ///   - baseURL: for example `http://192.168.1.20:8096` (a path prefix is kept).
    ///   - deviceID: stays the same for one installation. A new sign-in with a device ID that
    ///     is already known to the server signs the older session of that device out.
    public init(
        baseURL: URL,
        credentials: JellyfinCredentials,
        transport: HTTPTransport = URLSessionTransport(),
        deviceID: String = "VideoPlayerCore",
        deviceName: String = "Apple TV",
        clientName: String = "Video Player",
        clientVersion: String = "1.0",
        pageSize: Int = 500,
        scanPolicy: JellyfinScanPolicy = JellyfinScanPolicy()
    ) {
        self.baseURL = baseURL
        self.credentials = credentials
        self.transport = transport
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.pageSize = max(1, pageSize)
        self.scanPolicy = scanPolicy
        if case .token(let value) = credentials { self.token = value }
    }

    // MARK: MediaSource

    public nonisolated var kind: SourceKind { .jellyfin }

    public nonisolated var capabilities: SourceCapabilities {
        SourceCapabilities(
            authMethods: [.usernamePassword, .token],
            byteRanges: true,
            changeSignals: [.serverToken, .size],
            discovery: false,
            directPlaybackURL: true,
            alwaysEncrypted: false   // http:// on a home network is normal for Jellyfin
        )
    }

    /// Signs in (username and password) or checks the token. Safe to call again to reconnect.
    public func authenticate() async throws {
        switch credentials {
        case .password(let username, let password):
            token = nil
            token = try await login(username: username, password: password)
        case .token(let value):
            token = value
            let response = try await perform { [self] token in
                try request("GET", "/Items", query: [("Recursive", "true"), ("Limit", "0")], token: token)
            }
            try check(response)
        }
    }

    public func list(_ path: String) async throws -> [SourceEntry] {
        let tree = try await currentTree()
        guard let node = tree.node(at: path) else { throw SourceError.notFound }
        return node.entry.isDirectory ? tree.children(of: path).map(withKnownSize) : []
    }

    /// For a file whose size the server has not measured (it lists 0), the size is read once
    /// from a one-byte ranged request and remembered until `refresh()`.
    public func info(_ path: String) async throws -> SourceEntry {
        let tree = try await currentTree()
        guard let node = tree.node(at: path) else { throw SourceError.notFound }
        var entry = withKnownSize(node.entry)
        if !entry.isDirectory, entry.size == nil, node.itemID != nil, let size = try await probeSize(node) {
            knownSizes[entry.path] = size
            entry.size = size
        }
        return entry
    }

    private func withKnownSize(_ entry: SourceEntry) -> SourceEntry {
        guard entry.size == nil, let size = knownSizes[entry.path] else { return entry }
        var copy = entry
        copy.size = size
        return copy
    }

    /// The file size from `Content-Range: bytes 0-0/<size>`.
    private func probeSize(_ node: JFTree.Node) async throws -> Int64? {
        let response = try await perform { [self] token in
            try streamRequest(node, token: token, range: ByteRange(offset: 0, length: 1))
        }
        switch response.statusCode {
        case 206:
            guard let total = response.header("content-range")?.split(separator: "/").last else { return nil }
            return Int64(total)
        case 416: return 0
        default: try check(response); return nil
        }
    }

    public func read(_ path: String, range: ByteRange) async throws -> Data {
        if range.length == 0 { return Data() }
        let node = try await file(at: path)
        let response = try await perform { [self] token in
            try streamRequest(node, token: token, range: range)
        }
        switch response.statusCode {
        case 206: return response.body.count > Int(range.length) ? response.body.prefix(Int(range.length)) : response.body
        case 200: throw SourceError.rangesNotSupported
        case 416: throw SourceError.rangeNotSatisfiable
        default: try check(response); throw SourceError.httpStatus(response.statusCode)
        }
    }

    /// The direct-play URL (`static=true`) plus the token header the player must send.
    public func playbackAccess(for path: String) async throws -> PlaybackAccess {
        let node = try await file(at: path)
        let value = try await currentToken()
        let built = try streamRequest(node, token: value, range: nil)
        return .url(built.url, headers: built.headers)
    }

    /// Reads the libraries again (after the server added or removed files).
    public func refresh() async throws {
        treeTask = nil
        knownSizes = [:]
        _ = try await currentTree()
    }

    // MARK: Tree

    private func currentTree() async throws -> JFTree {
        if let running = treeTask { return try await running.value }
        let task = Task { try await self.buildTree() }
        treeTask = task
        do {
            return try await task.value
        } catch {
            treeTask = nil
            throw error
        }
    }

    /// R374: the server's official content rating of the item this file belongs to (its `OfficialRating`), from the item
    /// list the client already holds; nil when the server gave none. No extra request.
    public func officialRating(at path: String) async throws -> String? {
        try await file(at: path).officialRating
    }

    private func file(at path: String) async throws -> JFTree.Node {
        let tree = try await currentTree()
        guard let node = tree.node(at: path) else { throw SourceError.notFound }
        guard !node.entry.isDirectory, node.itemID != nil else { throw SourceError.unsupported("not a file") }
        return node
    }

    private func buildTree() async throws -> JFTree {
        try await waitForScan()
        let items = try await loadItems()
        let libraries = try await loadLibraries(items: items)
        return JFTree.make(libraries: libraries, items: items)
    }

    private static let videoTypes = "Movie,Episode,Video,MusicVideo"

    private func itemQuery(extra: [(String, String)]) -> [(String, String)] {
        [("Recursive", "true"), ("IncludeItemTypes", JellyfinClient.videoTypes)] + extra
    }

    /// A scan fills the list gradually: ask for the count until it stops changing.
    private func waitForScan() async throws {
        let started = Date()
        var previous: Int?
        var equalInARow = 0
        scanSettled = false
        while true {
            let page: JFItemsPage = try await getJSON("/Items", query: itemQuery(extra: [("Limit", "0")]))
            equalInARow = (page.totalRecordCount == previous) ? equalInARow + 1 : 1
            previous = page.totalRecordCount
            if equalInARow >= scanPolicy.stableChecks { scanSettled = true; return }
            if Date().timeIntervalSince(started) >= scanPolicy.timeout { return }
            if scanPolicy.pollInterval > 0 {
                try await Task.sleep(nanoseconds: UInt64(scanPolicy.pollInterval * 1_000_000_000))
            }
        }
    }

    private func loadItems() async throws -> [JFItem] {
        var result: [JFItem] = []
        var start = 0
        while true {
            let page: JFItemsPage = try await getJSON("/Items", query: itemQuery(extra: [
                ("Fields", "Path,MediaSources,Etag"), ("Limit", String(pageSize)), ("StartIndex", String(start)),
            ]))
            result += page.items
            start += page.items.count
            if page.items.isEmpty || start >= page.totalRecordCount { return result }
        }
    }

    private func loadLibraries(items: [JFItem]) async throws -> [JFLibrary] {
        do {
            let folders: [JFVirtualFolder] = try await getJSON("/Library/VirtualFolders")
            usedLibraryFolders = true
            return folders.map { JFLibrary(name: $0.name, roots: $0.locations.map(JFTree.components(of:))) }
        } catch SourceError.forbidden {
            // Only administrators may read the library folders. Without them, use the one folder
            // that contains every file as a single library.
            usedLibraryFolders = false
            let paths = items.flatMap { item -> [String] in
                let sources = (item.mediaSources ?? []).compactMap(\.path)
                return sources.isEmpty ? (item.path.map { [$0] } ?? []) : sources
            }
            return [JFLibrary(name: "Library", roots: [JFTree.commonFolder(of: paths)])]
        }
    }

    // MARK: Requests

    private func authorizationValue(token: String?) -> String {
        func clean(_ text: String) -> String { text.replacingOccurrences(of: "\"", with: "'") }
        var parts = [
            "Client=\"\(clean(clientName))\"", "Device=\"\(clean(deviceName))\"",
            "DeviceId=\"\(clean(deviceID))\"", "Version=\"\(clean(clientVersion))\"",
        ]
        if let token { parts.append("Token=\"\(token)\"") }
        return "MediaBrowser " + parts.joined(separator: ", ")
    }

    private func authHeaders(token: String?) -> [String: String] {
        ["Authorization": authorizationValue(token: token)]
    }

    private func url(_ endpoint: String, query: [(String, String)] = []) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw SourceError.invalidURL
        }
        var base = components.percentEncodedPath
        while base.hasSuffix("/") { base.removeLast() }
        components.percentEncodedPath = base + apiPrefix + endpoint
        components.percentEncodedQuery = query.isEmpty ? nil : query.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&")
        guard let url = components.url else { throw SourceError.invalidURL }
        return url
    }

    private nonisolated var apiPrefix: String { "" }

    private func encode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    private func request(_ method: String, _ endpoint: String, query: [(String, String)] = [], token: String?) throws -> HTTPRequest {
        HTTPRequest(url: try url(endpoint, query: query), method: method, headers: authHeaders(token: token))
    }

    /// `static=true` means "send the file as it is": direct play, never a transcode.
    private func streamRequest(_ node: JFTree.Node, token: String?, range: ByteRange?) throws -> HTTPRequest {
        guard let itemID = node.itemID else { throw SourceError.unsupported("not a file") }
        var query = [("static", "true")]
        if let source = node.mediaSourceID { query.append(("mediaSourceId", source)) }
        var built = try request("GET", "/Videos/\(encode(itemID))/stream", query: query, token: token)
        if let range { built.headers["Range"] = range.httpHeaderValue }
        return built
    }

    private func login(username: String, password: String) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: ["Username": username, "Pw": password])
        var built = HTTPRequest(url: try url("/Users/AuthenticateByName"), method: "POST", headers: loginHeaders(), body: body)
        built.headers["Content-Type"] = "application/json"
        let response = try await send(built)
        switch response.statusCode {
        case 200: break
        case 400, 401: throw SourceError.unauthorized
        case 403: throw SourceError.forbidden
        default: throw SourceError.httpStatus(response.statusCode)
        }
        guard let result = try? JSONDecoder().decode(JFAuthResult.self, from: response.body),
              let value = result.accessToken, !value.isEmpty else { throw SourceError.malformedResponse }
        return value
    }

    private func loginHeaders() -> [String: String] { authHeaders(token: nil) }

    private func currentToken() async throws -> String {
        if let token { return token }
        guard case .password(let username, let password) = credentials else { throw SourceError.unauthorized }
        let value = try await login(username: username, password: password)
        token = value
        return value
    }

    /// Sends a request with the current token. On 401 with a password, signs in again once.
    private func perform(_ build: (String?) throws -> HTTPRequest) async throws -> HTTPResponse {
        var response = try await send(try build(try await currentToken()))
        if response.statusCode == 401 {
            guard case .password(let username, let password) = credentials else { throw SourceError.unauthorized }
            token = nil
            let fresh = try await login(username: username, password: password)
            token = fresh
            response = try await send(try build(fresh))
            if response.statusCode == 401 { throw SourceError.unauthorized }
        }
        return response
    }

    private func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        do {
            return try await transport.send(request)
        } catch let error as SourceError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SourceError.transport(String(describing: error))
        }
    }

    private func check(_ response: HTTPResponse) throws {
        switch response.statusCode {
        case 200...299: return
        case 401: throw SourceError.unauthorized
        case 403: throw SourceError.forbidden
        case 404: throw SourceError.notFound
        default: throw SourceError.httpStatus(response.statusCode)
        }
    }

    private func getJSON<T: Decodable>(_ endpoint: String, query: [(String, String)] = []) async throws -> T {
        let response = try await perform { [self] token in try request("GET", endpoint, query: query, token: token) }
        try check(response)
        do {
            return try JSONDecoder().decode(T.self, from: response.body)
        } catch {
            throw SourceError.malformedResponse
        }
    }
}
