import Foundation

/// What the user gives the client. The app reads these from the Keychain; the client never stores them.
public enum EmbyCredentials: Equatable, Sendable {
    /// A user access token (or API key) the user pasted or got from an earlier sign-in.
    case token(String)
    case password(username: String, password: String)
}

/// How long to wait for the server's library scan. A scan fills the item list gradually, so the
/// client asks for the item count until it stops changing.
public struct EmbyScanPolicy: Equatable, Sendable {
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
    public static let immediate = EmbyScanPolicy(pollInterval: 0, stableChecks: 2, timeout: 5)
}

// MARK: Server responses (only the fields we use; everything else is ignored)

struct EMAuthResult: Decodable {
    var accessToken: String?
    enum CodingKeys: String, CodingKey { case accessToken = "AccessToken" }
}

struct EMItemsPage: Decodable {
    var items: [EMItem]
    var totalRecordCount: Int
    enum CodingKeys: String, CodingKey { case items = "Items", totalRecordCount = "TotalRecordCount" }
}

struct EMItem: Decodable {
    var id: String
    var path: String?
    var etag: String?
    var mediaSources: [EMMediaSource]?
    enum CodingKeys: String, CodingKey {
        case id = "Id", path = "Path", etag = "Etag", mediaSources = "MediaSources"
    }
}

struct EMMediaSource: Decodable {
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

struct EMVirtualFolder: Decodable {
    var name: String
    var locations: [String]
    enum CodingKeys: String, CodingKey { case name = "Name", locations = "Locations" }
}
