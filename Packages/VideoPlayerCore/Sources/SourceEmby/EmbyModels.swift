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
    /// "Movie", "Episode", "Video"...: what the server\'s own library calls the item (docs/SORTING.md).
    var type: String?
    /// R374: the item's official content rating ("PG-13", "TV-MA"), `BaseItemDto.OfficialRating` ("The official rating.", a
    /// string; https://dev.emby.media/reference/RestAPI/ItemsService/getItems.html, read 21 Nov 2026). It is NOT one of the
    /// `Fields` options listed for the items endpoints, so it cannot be added to `Fields`. The docs say list queries return
    /// "only a minimal amount of information" and a single item "the entire object"
    /// (https://dev.emby.media/doc/restapi/Item-Information.html); the client therefore asks the single-item endpoint
    /// (`GET /Users/{UserId}/Items/{Id}`) when the list did not carry it (`EmbyClient.requestOfficialRating(at:)`).
    var officialRating: String?
    enum CodingKeys: String, CodingKey {
        case id = "Id", path = "Path", etag = "Etag", mediaSources = "MediaSources", type = "Type"
        case officialRating = "OfficialRating"
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
