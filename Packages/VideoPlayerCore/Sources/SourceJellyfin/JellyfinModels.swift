import Foundation

/// What the user gives the client. The app reads these from the Keychain; the client never stores them.
public enum JellyfinCredentials: Equatable, Sendable {
    /// A user access token (or API key) the user pasted or got from an earlier sign-in.
    case token(String)
    case password(username: String, password: String)
}

/// How long to wait for the server's library scan. A scan fills the item list gradually, so the
/// client asks for the item count until it stops changing.
public struct JellyfinScanPolicy: Equatable, Sendable {
    /// Seconds between two counts.
    public var pollInterval: TimeInterval
    /// How many counts in a row must be equal before the scan counts as finished.
    public var stableChecks: Int
    /// Give up waiting after this many seconds and use what the server has so far.
    public var timeout: TimeInterval

    public init(pollInterval: TimeInterval = 1, stableChecks: Int = 3, timeout: TimeInterval = 120) {
        self.pollInterval = pollInterval
        self.stableChecks = max(2, stableChecks)
        self.timeout = timeout
    }

    /// For tests with a mock server that never changes.
    public static let immediate = JellyfinScanPolicy(pollInterval: 0, stableChecks: 2, timeout: 5)
}

// MARK: Server responses (only the fields we use; everything else is ignored)

struct JFAuthResult: Decodable {
    var accessToken: String?
    enum CodingKeys: String, CodingKey { case accessToken = "AccessToken" }
}

struct JFItemsPage: Decodable {
    var items: [JFItem]
    var totalRecordCount: Int
    enum CodingKeys: String, CodingKey { case items = "Items", totalRecordCount = "TotalRecordCount" }
}

struct JFItem: Decodable {
    var id: String
    var path: String?
    var etag: String?
    var mediaSources: [JFMediaSource]?
    /// "Movie", "Episode", "Video"...: what the server\'s own library calls the item (docs/SORTING.md).
    var type: String?
    /// R374: the item's official content rating ("PG-13", "TV-MA"), the API's `OfficialRating` field (https://api.jellyfin.org/openapi/jellyfin-openapi-stable.json, BaseItemDto, read
    /// 21 Nov 2026: "The official rating", a string). It is not one of the `Fields` values, so it is not asked for by
    /// name; whether the server sends it with the items list without being asked is UNVERIFIED (no server here).
    var officialRating: String?
    enum CodingKeys: String, CodingKey {
        case id = "Id", path = "Path", etag = "Etag", mediaSources = "MediaSources", type = "Type"
        case officialRating = "OfficialRating"
    }
}

struct JFMediaSource: Decodable {
    var id: String?
    var path: String?
    var size: Int64?
    var container: String?
    var protocolName: String?
    var etag: String?
    enum CodingKeys: String, CodingKey {
        case id = "Id", path = "Path", size = "Size", container = "Container", protocolName = "Protocol", etag = "ETag"
    }
}

struct JFVirtualFolder: Decodable {
    var name: String
    var locations: [String]
    enum CodingKeys: String, CodingKey { case name = "Name", locations = "Locations" }
}
