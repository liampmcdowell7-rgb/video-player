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
    /// R374: the signed-in user's id (`User.Id`), needed for the single-item endpoint. The recorded sign-in
    /// (Tests/.../Fixtures/authenticate.json) has `User` as one object; anything else is ignored, never a failed sign-in.
    var userID: String?
    enum CodingKeys: String, CodingKey { case accessToken = "AccessToken", user = "User" }
    private struct UserRef: Decodable {
        var id: String?
        enum CodingKeys: String, CodingKey { case id = "Id" }
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try c.decodeIfPresent(String.self, forKey: .accessToken)
        userID = (try? c.decodeIfPresent(UserRef.self, forKey: .user))?.id
    }
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
    /// R374: the item's official content rating ("PG-13", "TV-MA"), `BaseItemDto.OfficialRating` ("Gets or sets the official
    /// rating.", a nullable string) in the API's OpenAPI file (https://api.jellyfin.org/openapi/jellyfin-openapi-stable.json,
    /// version 12.4.0, read 21 Nov 2026). It is NOT a value of `ItemFields`, the type of the items endpoint's `Fields`
    /// parameter, so it cannot be added to `Fields`. The file names no set of properties sent without `Fields`; the client
    /// therefore asks the single-item endpoint (`GET /Items/{itemId}`, "Gets an item from a user's library.", returns
    /// `BaseItemDto`) when the list did not carry it (`JellyfinClient.requestOfficialRating(at:)`).
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
