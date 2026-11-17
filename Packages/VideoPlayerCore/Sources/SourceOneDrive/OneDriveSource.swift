import Foundation
import VideoPlayerCore

/// OneDrive through Microsoft Graph. Written from Microsoft's documentation only: it has never
/// talked to the real service (no app is registered; see OneDriveConfiguration.blockedStatus).
public actor OneDriveSource: MediaSource {
    private let configuration: OneDriveConfiguration
    private let store: OneDriveTokenStore
    private let transport: HTTPTransport
    private let flow: DeviceCodeFlow
    private let sleep: OneDriveSleeper
    private let now: OneDriveClock

    private var idCache: [String: String] = [:]
    private var downloadCache: [String: (url: URL, fetched: Date)] = [:]
    /// Graph download URLs are short-lived; re-fetch after this long (and on any 401/403/404 from them).
    private let downloadURLLifetime: TimeInterval = 600

    public init(
        configuration: OneDriveConfiguration,
        tokenStore: OneDriveTokenStore,
        transport: HTTPTransport,
        sleep: @escaping OneDriveSleeper = defaultOneDriveSleeper,
        now: @escaping OneDriveClock = { Date() }
    ) {
        self.configuration = configuration
        self.store = tokenStore
        self.transport = transport
        self.sleep = sleep
        self.now = now
        self.flow = DeviceCodeFlow(configuration: configuration, transport: transport, sleep: sleep, now: now)
    }

    public nonisolated var kind: SourceKind { .oneDrive }

    public nonisolated var capabilities: SourceCapabilities {
        SourceCapabilities(
            authMethods: [.oauthDeviceCode],
            byteRanges: true,
            changeSignals: [.etag, .modified, .size, .serverToken],
            discovery: false,
            directPlaybackURL: true,
            alwaysEncrypted: true)
    }

    // MARK: Sign-in

    /// Step 1 of TV sign-in: show `userCode` and `verificationURI`. Throws `.needsAppRegistration` without a client ID.
    public func beginSignIn() async throws -> DeviceCodeChallenge {
        try await flow.start()
    }

    /// Step 2: waits for the user, then stores the tokens.
    public func completeSignIn(_ challenge: DeviceCodeChallenge) async throws {
        let tokens = try await flow.waitForTokens(challenge)
        await store.save(tokens)
    }

    public func signOut() async {
        await store.clear()
        idCache = [:]
        downloadCache = [:]
    }

    // MARK: MediaSource

    public func authenticate() async throws {
        guard configuration.isRegistered else { throw OneDriveError.needsAppRegistration }
        _ = try await graph(url: graphURL("/me/drive"))
    }

    public func list(_ path: String) async throws -> [SourceEntry] {
        let folder = Self.normalize(path)
        let first: URL
        if folder == "/" {
            first = try graphURL("/me/drive/root/children")
        } else {
            let id = try await resolveID(folder)
            first = try graphURL("/me/drive/items/\(Self.encodeSegment(id))/children")
        }
        var entries: [SourceEntry] = []
        var next: URL? = first
        var pages = 0
        while let url = next, pages < 1000 {
            let response = try await graph(url: url)
            let page = try decode(ItemPage.self, response)
            for item in page.value {
                let childPath = folder == "/" ? "/" + item.name : folder + "/" + item.name
                if let id = item.id { idCache[childPath] = id }
                remember(item, at: childPath)
                entries.append(entry(item, path: childPath))
            }
            next = page.nextLink.flatMap { URL(string: $0) }
            pages += 1
        }
        return entries
    }

    public func info(_ path: String) async throws -> SourceEntry {
        let normalized = Self.normalize(path)
        let item = try await fetchItem(normalized)
        if let id = item.id { idCache[normalized] = id }
        remember(item, at: normalized)
        var result = entry(item, path: normalized)
        if normalized == "/" { result.name = "/" }
        return result
    }

    public func read(_ path: String, range: ByteRange) async throws -> Data {
        if range.length == 0 { return Data() }
        let normalized = Self.normalize(path)
        var url = try await downloadURL(for: normalized, forceRefresh: false)
        var refreshed = false
        while true {
            // The download URL is pre-authenticated: no Authorization header goes to it.
            let response = try await send(HTTPRequest(url: url, method: "GET", headers: ["Range": range.httpHeaderValue]))
            switch response.statusCode {
            case 206: return response.body
            case 200: throw SourceError.rangesNotSupported
            case 416: throw SourceError.rangeNotSatisfiable
            case 401, 403, 404:
                if refreshed { throw response.statusCode == 404 ? SourceError.notFound : SourceError.forbidden }
                refreshed = true
                url = try await downloadURL(for: normalized, forceRefresh: true)
            case 429, 503:
                throw OneDriveError.throttled(retryAfter: response.header("retry-after").flatMap { Int($0) })
            default: throw SourceError.httpStatus(response.statusCode)
            }
        }
    }

    /// The pre-authenticated URL for the player. It expires (about an hour); ask again for a fresh one.
    public func playbackAccess(for path: String) async throws -> PlaybackAccess {
        let url = try await downloadURL(for: Self.normalize(path), forceRefresh: true)
        return .url(url, headers: [:])
    }

    // MARK: Graph plumbing

    private func graphURL(_ suffix: String) throws -> URL {
        guard let url = URL(string: configuration.graphBaseURL.absoluteString + suffix) else { throw SourceError.invalidURL }
        return url
    }

    private func rootPathURL(_ path: String) throws -> URL {
        let encoded = path.split(separator: "/").map { Self.encodeSegment(String($0)) }.joined(separator: "/")
        return try graphURL("/me/drive/root:/" + encoded)
    }

    private func resolveID(_ path: String) async throws -> String {
        if let cached = idCache[path] { return cached }
        let item = try await fetchItem(path)
        guard let id = item.id else { throw SourceError.malformedResponse }
        idCache[path] = id
        return id
    }

    private func fetchItem(_ path: String) async throws -> Item {
        let url = path == "/" ? try graphURL("/me/drive/root") : try rootPathURL(path)
        return try decode(Item.self, try await graph(url: url))
    }

    private func downloadURL(for path: String, forceRefresh: Bool) async throws -> URL {
        if !forceRefresh, let cached = downloadCache[path], now().timeIntervalSince(cached.fetched) < downloadURLLifetime {
            return cached.url
        }
        let item = try await fetchItem(path)
        guard item.folder == nil, let text = item.downloadUrl, let url = URL(string: text) else {
            throw SourceError.unsupported("no download URL (folder or missing file)")
        }
        downloadCache[path] = (url, now())
        return url
    }

    private func remember(_ item: Item, at path: String) {
        if let text = item.downloadUrl, let url = URL(string: text), item.folder == nil {
            downloadCache[path] = (url, now())
        }
    }

    private func entry(_ item: Item, path: String) -> SourceEntry {
        let isFolder = item.folder != nil
        return SourceEntry(
            path: path, name: item.name, isDirectory: isFolder,
            size: isFolder ? nil : item.size,
            modified: item.lastModifiedDateTime.flatMap(Self.parseDate),
            contentType: item.file?.mimeType,
            etag: item.eTag,
            serverToken: item.cTag)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ response: HTTPResponse) throws -> T {
        do { return try JSONDecoder().decode(type, from: response.body) }
        catch { throw SourceError.malformedResponse }
    }

    private func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        do { return try await transport.send(request) }
        catch let error as SourceError { throw error }
        catch { throw SourceError.transport(String(describing: error)) }
    }

    /// GET on Graph with the bearer token: refreshes once on 401 and waits out 429/503 (Retry-After).
    private func graph(url: URL) async throws -> HTTPResponse {
        guard configuration.isRegistered else { throw OneDriveError.needsAppRegistration }
        var token = try await accessToken(forceRefresh: false)
        var refreshed = false
        var throttles = 0
        while true {
            let response = try await send(HTTPRequest(
                url: url, method: "GET",
                headers: ["Authorization": "Bearer " + token, "Accept": "application/json"]))
            switch response.statusCode {
            case 200...299: return response
            case 401:
                if refreshed { throw SourceError.unauthorized }
                refreshed = true
                token = try await accessToken(forceRefresh: true)
            case 429, 503:
                let retryAfter = response.header("retry-after").flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                if throttles >= configuration.maxRetries { throw OneDriveError.throttled(retryAfter: retryAfter) }
                let wait = retryAfter.map(TimeInterval.init) ?? TimeInterval(1 << min(throttles, 6))
                throttles += 1
                await sleep(wait)
            case 403: throw SourceError.forbidden
            case 404: throw SourceError.notFound
            default: throw SourceError.httpStatus(response.statusCode)
            }
        }
    }

    private func accessToken(forceRefresh: Bool) async throws -> String {
        guard var tokens = await store.load() else { throw OneDriveError.notSignedIn }
        if forceRefresh || tokens.expiresAt <= now().addingTimeInterval(configuration.tokenExpirySkew) {
            guard let refreshToken = tokens.refreshToken else { throw OneDriveError.notSignedIn }
            do { tokens = try await flow.refresh(refreshToken) }
            catch OneDriveError.notSignedIn { await store.clear(); throw OneDriveError.notSignedIn }
            await store.save(tokens)
        }
        return tokens.accessToken
    }

    // MARK: Helpers

    static func normalize(_ path: String) -> String {
        let parts = path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        return "/" + parts.joined(separator: "/")
    }

    static func encodeSegment(_ segment: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
    }

    static func parseDate(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    private struct Item: Decodable {
        struct Folder: Decodable { var childCount: Int? }
        struct File: Decodable { var mimeType: String? }
        var id: String?
        var name: String
        var size: Int64?
        var eTag: String?
        var cTag: String?
        var lastModifiedDateTime: String?
        var folder: Folder?
        var file: File?
        var downloadUrl: String?

        enum CodingKeys: String, CodingKey {
            case id, name, size, eTag, cTag, lastModifiedDateTime, folder, file
            case downloadUrl = "@microsoft.graph.downloadUrl"
        }
    }

    private struct ItemPage: Decodable {
        var value: [Item]
        var nextLink: String?
        enum CodingKeys: String, CodingKey { case value; case nextLink = "@odata.nextLink" }
    }
}
