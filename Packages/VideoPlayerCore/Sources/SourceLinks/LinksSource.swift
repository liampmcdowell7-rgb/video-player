import Foundation
import VideoPlayerCore

/// What a probe learned about the address behind a link.
public struct LinkProbe: Equatable, Sendable {
    public var size: Int64?
    public var contentType: String?
    public var acceptsRanges: Bool
    public var etag: String?
    public var modified: Date?
}

/// A `MediaSource` over the user's pasted links. One flat list: every link is a file at `/<title>`.
/// Shared links are turned into direct byte addresses (`LinkClassifier`); anything that answers with a web page
/// is reported with a typed `LinkError` instead of being played.
public actor LinksSource: MediaSource {
    private var store: LinkStore
    private let transport: HTTPTransport
    private var probes: [UUID: LinkProbe] = [:]

    public init(store: LinkStore = LinkStore(), transport: HTTPTransport) {
        self.store = store
        self.transport = transport
    }

    // MARK: The list the user edits

    public var currentStore: LinkStore { store }

    @discardableResult
    public func add(_ text: String, title: String? = nil) throws -> SavedLink {
        try store.add(text, title: title)
    }

    public func remove(id: UUID) {
        store.remove(id: id)
        probes[id] = nil
    }

    public func rename(id: UUID, to title: String) throws {
        try store.rename(id: id, to: title)
    }

    // MARK: MediaSource

    public nonisolated var kind: SourceKind { .directLink }

    public nonisolated var capabilities: SourceCapabilities {
        SourceCapabilities(
            authMethods: [.none],
            byteRanges: true,             // probed per link; a server that ignores Range is reported as .rangesNotSupported
            changeSignals: [.etag, .modified, .size],
            discovery: false,
            directPlaybackURL: true,
            alwaysEncrypted: false        // http:// links are allowed
        )
    }

    /// Nothing to sign in to. Succeeds without touching the network.
    public func authenticate() async throws {}

    /// The links, as files in one folder. Sizes appear once a link has been probed (`info` or `probeAll`).
    public func list(_ path: String = "/") async throws -> [SourceEntry] {
        guard Self.normalize(path) == "/" else {
            if store.links.contains(where: { Self.path(of: $0) == Self.normalize(path) }) { throw SourceError.unsupported("A link is a file, not a folder") }
            throw SourceError.notFound
        }
        return store.links.map { entry(for: $0) }
    }

    /// Checks the link over the network and fills in size, type and change signals.
    public func info(_ path: String) async throws -> SourceEntry {
        let normalized = Self.normalize(path)
        if normalized == "/" { return SourceEntry(path: "/", name: "", isDirectory: true) }
        let link = try savedLink(at: normalized)
        let target = try resolve(link)
        probes[link.id] = try await probe(target.url, provider: target.provider)
        return entry(for: link)
    }

    /// Probes every link. Returns only the links that failed, with the reason (`LinkError` or `SourceError`),
    /// so one bad link does not stop the rest.
    public func probeAll() async -> [UUID: Error] {
        var failures: [UUID: Error] = [:]
        for link in store.links {
            do {
                let target = try resolve(link)
                probes[link.id] = try await probe(target.url, provider: target.provider)
            } catch {
                failures[link.id] = error
            }
        }
        return failures
    }

    public func read(_ path: String, range: ByteRange) async throws -> Data {
        if range.length == 0 { return Data() }
        let link = try savedLink(at: Self.normalize(path))
        let target = try resolve(link)
        let response = try await send(HTTPRequest(url: target.url, method: "GET", headers: ["Range": range.httpHeaderValue]))
        switch response.statusCode {
        case 206:
            try Self.rejectWebPage(response, host: target.url.host)
            return response.body.count > Int(range.length) ? response.body.prefix(Int(range.length)) : response.body
        case 200:
            try Self.rejectWebPage(response, host: target.url.host)
            throw SourceError.rangesNotSupported
        case 416: throw SourceError.rangeNotSatisfiable
        case 404: throw SourceError.notFound
        case 401, 403: throw LinkError.needsSignIn(provider: target.provider)
        default: throw SourceError.httpStatus(response.statusCode)
        }
    }

    /// The (converted) address itself. Checks first that it really serves bytes, so a share page never reaches the player.
    public func playbackAccess(for path: String) async throws -> PlaybackAccess {
        let link = try savedLink(at: Self.normalize(path))
        let target = try resolve(link)
        probes[link.id] = try await probe(target.url, provider: target.provider)
        return .url(target.url, headers: [:])
    }

    // MARK: Probing

    private struct Target { var url: URL; var provider: String }

    private func savedLink(at path: String) throws -> SavedLink {
        guard let link = store.links.first(where: { Self.path(of: $0) == path }) else { throw SourceError.notFound }
        return link
    }

    /// Classifies a saved link and returns the address to fetch, or throws the reason there is none.
    private func resolve(_ link: SavedLink) throws -> Target {
        guard let url = link.url else { throw LinkError.invalidLink }
        let classification = LinkClassifier.classify(url)
        if let problem = classification.problem { throw problem }
        guard let direct = classification.directURL else { throw LinkError.invalidLink }
        return Target(url: direct, provider: Self.providerName(classification.kind, host: url.host))
    }

    /// HEAD first (no body). Servers that refuse HEAD get a one-byte ranged GET instead.
    func probe(_ url: URL, provider: String) async throws -> LinkProbe {
        var response = try await send(HTTPRequest(url: url, method: "HEAD"))
        var sawContentRange: Int64?
        if [400, 405, 501].contains(response.statusCode) {
            response = try await send(HTTPRequest(url: url, method: "GET", headers: ["Range": "bytes=0-0"]))
            sawContentRange = Self.totalFromContentRange(response.header("content-range"))
        }
        switch response.statusCode {
        case 200..<300: break
        case 401, 403: throw LinkError.needsSignIn(provider: provider)
        case 404, 410: throw SourceError.notFound
        default: throw SourceError.httpStatus(response.statusCode)
        }
        try Self.rejectWebPage(response, host: url.host)

        var acceptsRanges = response.header("accept-ranges")?.lowercased().contains("bytes") ?? false
        if response.statusCode == 206 { acceptsRanges = true }
        var size = sawContentRange ?? Self.totalFromContentRange(response.header("content-range"))
        if size == nil, response.statusCode != 206 { size = response.header("content-length").flatMap { Int64($0) } }

        if !acceptsRanges, response.header("accept-ranges") == nil {
            // Many servers support ranges without saying so; ask for one byte to find out.
            let check = try await send(HTTPRequest(url: url, method: "GET", headers: ["Range": "bytes=0-0"]))
            if check.statusCode == 206 {
                acceptsRanges = true
                size = size ?? Self.totalFromContentRange(check.header("content-range"))
            }
        }
        return LinkProbe(
            size: size,
            contentType: response.header("content-type"),
            acceptsRanges: acceptsRanges,
            etag: response.header("etag"),
            modified: response.header("last-modified").flatMap(Self.httpDate)
        )
    }

    private static func rejectWebPage(_ response: HTTPResponse, host: String?) throws {
        let type = response.header("content-type")?.lowercased() ?? ""
        if type.hasPrefix("text/html") || type.hasPrefix("application/xhtml") {
            throw LinkError.webPage(host: host ?? "The server")
        }
    }

    // MARK: Entries and helpers

    private func entry(for link: SavedLink) -> SourceEntry {
        let known = probes[link.id]
        return SourceEntry(
            path: Self.path(of: link), name: link.title, isDirectory: false,
            size: known?.size, modified: known?.modified, contentType: known?.contentType, etag: known?.etag
        )
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

    static func path(of link: SavedLink) -> String { "/" + link.title }

    static func normalize(_ path: String) -> String {
        "/" + path.split(separator: "/", omittingEmptySubsequences: true).joined(separator: "/")
    }

    static func totalFromContentRange(_ value: String?) -> Int64? {
        // "bytes 0-0/12345"; "*" for an unknown total
        guard let value, let slash = value.lastIndex(of: "/") else { return nil }
        return Int64(value[value.index(after: slash)...].trimmingCharacters(in: .whitespaces))
    }

    static func httpDate(_ text: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f.date(from: text)
    }

    static func providerName(_ kind: LinkKind, host: String?) -> String {
        switch kind {
        case .dropboxShare: return "Dropbox"
        case .googleDriveFile, .googleDriveFolder: return "Google Drive"
        case .oneDriveShare: return "OneDrive"
        case .iCloudDriveShare: return "iCloud Drive"
        default: return host ?? "The server"
        }
    }
}
