import Foundation
import VideoPlayerCore

/// Minimal WebDAV client: PROPFIND directory listing with Basic and Digest authentication.
/// Credentials are passed in by the caller (the app reads them from the Keychain).
public actor WebDAVClient: MediaSource {
    private enum AuthState {
        case none
        case basic
        case digest(DigestChallenge, nonceCount: Int)
    }

    private let baseURL: URL
    private let basePath: String
    private let credentials: WebDAVCredentials?
    private let transport: HTTPTransport
    private let allowBasicOverHTTP: Bool
    private let makeCnonce: @Sendable () -> String
    private var auth: AuthState = .none

    /// - Parameters:
    ///   - allowBasicOverHTTP: Basic sends the password in clear text. Refused on `http://` unless true.
    public init(
        baseURL: URL,
        credentials: WebDAVCredentials?,
        transport: HTTPTransport,
        allowBasicOverHTTP: Bool = false,
        cnonce: @escaping @Sendable () -> String = WebDAVClient.randomCnonce
    ) {
        self.baseURL = baseURL
        self.credentials = credentials
        self.transport = transport
        self.allowBasicOverHTTP = allowBasicOverHTTP
        self.makeCnonce = cnonce
        self.basePath = WebDAVClient.normalize(baseURL.path)
    }

    public static let randomCnonce: @Sendable () -> String = {
        (0..<8).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    // MARK: MediaSource

    public nonisolated var kind: SourceKind { .webdav }

    public nonisolated var capabilities: SourceCapabilities {
        SourceCapabilities(
            authMethods: [.none, .basic, .digest],
            byteRanges: true,   // standard for GET; a server that ignores Range is reported as .rangesNotSupported
            changeSignals: [.etag, .modified, .size],
            discovery: false,
            directPlaybackURL: true,
            alwaysEncrypted: false   // plain http:// is allowed (Basic over http needs an explicit opt-in)
        )
    }

    /// Checks the server and the credentials with a PROPFIND on the root.
    public func authenticate() async throws {
        _ = try await propfind("/", depth: 0)
    }

    /// Lists the direct children of a directory. The directory itself is not included.
    public func list(_ path: String = "/") async throws -> [SourceEntry] {
        let requested = WebDAVClient.normalize(path)
        return try await propfind(path, depth: 1).filter { $0.path != requested }
    }

    public func info(_ path: String) async throws -> SourceEntry {
        let requested = WebDAVClient.normalize(path)
        let entries = try await propfind(path, depth: 0)
        guard let entry = entries.first(where: { $0.path == requested }) ?? entries.first else {
            throw SourceError.notFound
        }
        return entry
    }

    /// Reads part of a file with an HTTP `Range` request.
    public func read(_ path: String, range: ByteRange) async throws -> Data {
        if range.length == 0 { return Data() }
        let request = HTTPRequest(
            url: try requestURL(for: path, directory: false),
            method: "GET",
            headers: ["Range": range.httpHeaderValue]
        )
        let response = try await perform(request)
        switch response.statusCode {
        case 206: return response.body.count > Int(range.length) ? response.body.prefix(Int(range.length)) : response.body
        case 200: throw SourceError.rangesNotSupported
        case 416: throw SourceError.rangeNotSatisfiable
        case 404: throw SourceError.notFound
        case 403: throw SourceError.forbidden
        case 401: throw SourceError.unauthorized
        default: throw SourceError.httpStatus(response.statusCode)
        }
    }

    /// Basic or no authentication: a plain URL plus the Authorization header. Digest cannot be
    /// reused across the player's many requests (nonce count), so the app feeds bytes instead.
    public func playbackAccess(for path: String) async throws -> PlaybackAccess {
        if credentials != nil, case .none = auth { try await authenticate() }
        let url = try requestURL(for: path, directory: false)
        switch auth {
        case .digest:
            return .byteReader
        case .basic:
            guard let value = header(method: "GET", uri: WebDAVClient.requestURI(of: url)) else { return .url(url, headers: [:]) }
            return .url(url, headers: ["Authorization": value])
        case .none:
            return .url(url, headers: [:])
        }
    }

    // MARK: PROPFIND

    private func propfind(_ path: String, depth: Int) async throws -> [SourceEntry] {
        let url = try requestURL(for: path, directory: depth > 0)
        let body = Data("""
        <?xml version="1.0" encoding="utf-8"?>\
        <d:propfind xmlns:d="DAV:"><d:prop>\
        <d:resourcetype/><d:getcontentlength/><d:getlastmodified/><d:getcontenttype/><d:displayname/><d:getetag/>\
        </d:prop></d:propfind>
        """.utf8)
        let request = HTTPRequest(
            url: url,
            method: "PROPFIND",
            headers: ["Depth": String(depth), "Content-Type": "application/xml; charset=utf-8"],
            body: body
        )
        let response = try await perform(request)
        switch response.statusCode {
        case 207: break
        case 404: throw SourceError.notFound
        case 403: throw SourceError.forbidden
        case 401: throw SourceError.unauthorized
        default: throw SourceError.httpStatus(response.statusCode)
        }

        var entries: [SourceEntry] = []
        for item in try PropfindParser.parse(response.body) {
            let relative = relativePath(fromHref: item.href)
            let isDirectory = item.isCollection
            let lastComponent = relative.split(separator: "/").last.map(String.init) ?? ""
            let name = lastComponent.isEmpty ? (item.displayName ?? "") : lastComponent
            entries.append(SourceEntry(
                path: relative,
                name: name,
                isDirectory: isDirectory,
                size: isDirectory ? nil : item.contentLength,
                modified: item.lastModified,
                contentType: item.contentType,
                etag: item.etag
            ))
        }
        return entries
    }

    // MARK: URLs and authorization for other requests (for example ranged playback reads)

    /// Absolute URL of a file or folder path (path relative to the base URL).
    public func url(for path: String) throws -> URL {
        try requestURL(for: path, directory: false)
    }

    /// Value for the `Authorization` header for a later request, or nil if none is needed yet.
    /// Digest values advance the nonce count, so call once per request.
    public func authorizationHeader(method: String, url: URL) -> String? {
        header(method: method, uri: WebDAVClient.requestURI(of: url))
    }

    // MARK: Internals

    private func perform(_ original: HTTPRequest) async throws -> HTTPResponse {
        var request = original
        let uri = WebDAVClient.requestURI(of: request.url)
        if let value = header(method: request.method, uri: uri) { request.headers["Authorization"] = value }

        var response = try await send(request)
        if response.statusCode == 401 {
            guard credentials != nil else { throw SourceError.unauthorized }
            try updateAuth(from: response)
            guard let value = header(method: request.method, uri: uri) else { throw SourceError.unauthorized }
            request.headers["Authorization"] = value
            response = try await send(request)
            if response.statusCode == 401 { throw SourceError.unauthorized }
        }
        return response
    }

    private func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        do {
            return try await transport.send(request)
        } catch let error as SourceError {
            throw error
        } catch {
            throw SourceError.transport(String(describing: error))
        }
    }

    private func updateAuth(from response: HTTPResponse) throws {
        let challenges = AuthChallengeParser.parse(response.header("www-authenticate") ?? "")
        if let digest = challenges.compactMap(DigestChallenge.init).first {
            auth = .digest(digest, nonceCount: 0)
            return
        }
        if challenges.contains(where: { $0.scheme == "basic" }) {
            if baseURL.scheme?.lowercased() == "http", !allowBasicOverHTTP {
                throw SourceError.insecureBasicAuthentication
            }
            auth = .basic
            return
        }
        throw SourceError.unsupportedAuthentication
    }

    private func header(method: String, uri: String) -> String? {
        guard let credentials else { return nil }
        switch auth {
        case .none:
            return nil
        case .basic:
            return BasicAuth.authorization(username: credentials.username, password: credentials.password)
        case .digest(let challenge, let count):
            let next = count + 1
            auth = .digest(challenge, nonceCount: next)
            return DigestAuth.authorization(
                challenge: challenge,
                username: credentials.username,
                password: credentials.password,
                method: method,
                uri: uri,
                nonceCount: next,
                cnonce: makeCnonce()
            )
        }
    }

    private func requestURL(for path: String, directory: Bool) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw SourceError.invalidURL
        }
        let relative = WebDAVClient.normalize(path)
        var full = basePath == "/" ? relative : basePath + (relative == "/" ? "" : relative)
        if full.isEmpty { full = "/" }
        if directory, !full.hasSuffix("/") { full += "/" }
        guard let encoded = full.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw SourceError.invalidURL
        }
        components.percentEncodedPath = encoded
        components.query = nil
        guard let url = components.url else { throw SourceError.invalidURL }
        return url
    }

    private func relativePath(fromHref href: String) -> String {
        var path: String
        if let url = URL(string: href), url.scheme != nil {
            path = url.path
        } else {
            let withoutQuery = href.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? href
            path = withoutQuery.removingPercentEncoding ?? withoutQuery
        }
        path = WebDAVClient.normalize(path)
        if basePath != "/" {
            if path == basePath { return "/" }
            if path.hasPrefix(basePath + "/") { path = String(path.dropFirst(basePath.count)) }
        }
        return path
    }

    /// Leading "/", no trailing "/", no empty components (except the root, which is "/").
    static func normalize(_ path: String) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        return "/" + parts.joined(separator: "/")
    }

    static func requestURI(of url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.path }
        var uri = components.percentEncodedPath
        if uri.isEmpty { uri = "/" }
        if let query = components.percentEncodedQuery { uri += "?" + query }
        return uri
    }
}
