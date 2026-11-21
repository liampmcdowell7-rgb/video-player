import Foundation
import VideoPlayerCore

/// Writes watch state to one Plex Media Server (docs/PLEX_SOURCE.md section 6; OPEN_QUESTIONS R306 b, R308).
///
/// Read 21 Nov 2026 in the OpenAPI file of https://developer.plex.tv/pms/:
/// - `POST /:/timeline`, "Report media timeline": query `key` ("The details key for the item"), `ratingKey`, `state`
///   (`stopped`, `buffering`, `playing`, `paused`), `time` ("The current time offset of playback in ms"), `duration` (ms),
///   `continuing` (0 or 1, with `stopped`), `offline` (0 or 1) and `updated` ("holds the time at which the playback state
///   was last updated"); header `X-Plex-Client-Identifier` required, `X-Plex-Session-Identifier` optional.
/// - `PUT /:/scrobble` and `PUT /:/unscrobble`: query `identifier` (required, "Typically `com.plexapp.plugins.library`")
///   and `key` ("the `ratingKey` found in metadata items"); "applications should use PUT".
/// - `GET /media/providers`: the documented example lists the provider `com.plexapp.plugins.library` with a Feature of type
///   `timeline` whose `key` is `/:/timeline`, `scrobbleKey` `/:/scrobble` and `unscrobbleKey` `/:/unscrobble`; clients
///   should "read them from the feature keys directly". The paths are read from there, and the documented paths are used
///   when the server does not list them.
/// UNVERIFIED (not stated in the file): the unit of `updated` (seconds since 1970 is sent, like Plex's other dates);
/// whether `key` must be the item's details key (`/library/metadata/<ratingKey>` is sent, the form the library lists use).
///
/// The token travels in the `X-Plex-Token` header only, never in an address (R300).
public actor PlexWatchWriter: ServerWatchWriting {
    public static let libraryIdentifier = "com.plexapp.plugins.library"

    private let baseURL: URL
    private let token: String
    private let http: PlexHTTP
    private var known: PlexWatchEndpoints?

    public init(baseURL: URL, token: String, identity: PlexClientIdentity, transport: HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.token = token
        self.http = PlexHTTP(identity: identity, transport: transport)
    }

    // MARK: ServerWatchWriting

    public func report(_ report: ServerTimelineReport) async throws {
        let paths = try await endpoints()
        var query: [(String, String)] = [
            ("key", "/library/metadata/" + report.itemKey),
            ("ratingKey", report.itemKey),
            ("state", report.state.rawValue),
            ("time", String(Self.milliseconds(report.position))),
        ]
        if let duration = report.duration, duration > 0 { query.append(("duration", String(Self.milliseconds(duration)))) }
        if report.state == .stopped, let continuing = report.continuing { query.append(("continuing", continuing ? "1" : "0")) }
        if let updated = report.offlineUpdated {
            query.append(("offline", "1"))
            query.append(("updated", String(Int(updated.timeIntervalSince1970.rounded(.down)))))
        }
        var extra: [String: String] = [:]
        if let session = report.sessionIdentifier, !session.isEmpty { extra["X-Plex-Session-Identifier"] = session }
        try await write("POST", paths.timeline, query: query, extra: extra)
    }

    public func markPlayed(itemKey: String) async throws {
        let paths = try await endpoints()
        try await write("PUT", paths.scrobble, query: [("identifier", Self.libraryIdentifier), ("key", itemKey)])
    }

    public func markUnplayed(itemKey: String) async throws {
        let paths = try await endpoints()
        try await write("PUT", paths.unscrobble, query: [("identifier", Self.libraryIdentifier), ("key", itemKey)])
    }

    // MARK: Paths

    /// The server's own timeline, scrobble and unscrobble paths, read once from `/media/providers`. A server that answers
    /// without them (or with a path this client will not use) gets the documented paths. A server that cannot be reached
    /// throws, so the caller can keep the write for later; the list is asked for again next time.
    public func endpoints() async throws -> PlexWatchEndpoints {
        if let known { return known }
        let request = http.request("GET", baseURL.appendingPathComponent("media/providers"), token: token)
        let response = try await http.send(request)
        let found: PlexWatchEndpoints
        if let envelope = try? PlexHTTP.decode(PlexProvidersEnvelope.self, from: response) {
            found = PlexWatchEndpoints.from(envelope.container.providers)
        } else {
            found = .documented
        }
        known = found
        return found
    }

    // MARK: Requests

    private func write(_ method: String, _ path: String, query: [(String, String)], extra: [String: String] = [:]) async throws {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw SourceError.invalidURL }
        components.path = path
        components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = components.url else { throw SourceError.invalidURL }
        let response = try await http.send(http.request(method, url, token: token, extra: extra))
        try PlexHTTP.check(response)
    }

    static func milliseconds(_ seconds: Double) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int((seconds * 1000).rounded())
    }
}

/// The three paths of the timeline feature.
public struct PlexWatchEndpoints: Equatable, Sendable {
    public var timeline: String
    public var scrobble: String
    public var unscrobble: String

    /// The paths in the PMS reference (read 21 Nov 2026).
    public static let documented = PlexWatchEndpoints(timeline: "/:/timeline", scrobble: "/:/scrobble", unscrobble: "/:/unscrobble")

    public init(timeline: String, scrobble: String, unscrobble: String) {
        self.timeline = timeline
        self.scrobble = scrobble
        self.unscrobble = unscrobble
    }

    /// The library provider's timeline feature; each path that is missing or not a plain path on this server falls back to
    /// the documented one.
    static func from(_ providers: [PlexMediaProvider]) -> PlexWatchEndpoints {
        let library = providers.first { $0.identifier == PlexWatchWriter.libraryIdentifier }
        guard let feature = library?.features.first(where: { $0.type == "timeline" }) else { return .documented }
        return PlexWatchEndpoints(timeline: usable(feature.key) ?? documented.timeline,
                                  scrobble: usable(feature.scrobbleKey) ?? documented.scrobble,
                                  unscrobble: usable(feature.unscrobbleKey) ?? documented.unscrobble)
    }

    /// Only a path on the same server: starts with one "/", no scheme, host, query or fragment.
    static func usable(_ path: String?) -> String? {
        guard let path, path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains("://"),
              !path.contains("?"), !path.contains("#"), !path.contains(" ") else { return nil }
        return path
    }
}

// `GET /media/providers` (documented example, read 21 Nov 2026): MediaContainer > MediaProvider[] (identifier, Feature[]
// with type, key, scrobbleKey, unscrobbleKey).
struct PlexProvidersEnvelope: Decodable {
    var container: Container
    enum CodingKeys: String, CodingKey { case container = "MediaContainer" }

    struct Container: Decodable {
        var providers: [PlexMediaProvider]
        enum CodingKeys: String, CodingKey { case providers = "MediaProvider" }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            providers = (try? c.decodeIfPresent([PlexMediaProvider].self, forKey: .providers)) ?? []
        }
    }
}

struct PlexMediaProvider: Decodable {
    var identifier: String?
    var features: [Feature]

    struct Feature: Decodable {
        var type: String?
        var key: String?
        var scrobbleKey: String?
        var unscrobbleKey: String?
    }

    enum CodingKeys: String, CodingKey { case identifier, features = "Feature" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try? c.decodeIfPresent(String.self, forKey: .identifier)
        features = (try? c.decodeIfPresent([Feature].self, forKey: .features)) ?? []
    }
}
