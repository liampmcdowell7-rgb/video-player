import Foundation
import VideoPlayerCore

/// Settings for OneDrive. The client ID comes from the app's settings: this project has NOT
/// registered a Microsoft app, so it is nil until the owner decides to (docs/SOURCES.md).
public struct OneDriveConfiguration: Sendable, Equatable {
    public static let blockedStatus = "blocked: needs an app registration"

    public var clientID: String?
    /// `consumers` for personal Microsoft accounts (default), `common` or `organizations` otherwise.
    public var tenant: String
    public var scopes: [String]
    public var loginBaseURL: URL
    public var graphBaseURL: URL
    /// A token that expires within this many seconds is refreshed before use.
    public var tokenExpirySkew: TimeInterval
    /// How many times a 429/503 answer is retried (honouring Retry-After).
    public var maxRetries: Int

    public init(
        clientID: String?,
        tenant: String = "consumers",
        scopes: [String] = ["Files.Read", "offline_access"],
        loginBaseURL: URL = URL(string: "https://login.microsoftonline.com")!,
        graphBaseURL: URL = URL(string: "https://graph.microsoft.com/v1.0")!,
        tokenExpirySkew: TimeInterval = 120,
        maxRetries: Int = 3
    ) {
        self.clientID = clientID
        self.tenant = tenant
        self.scopes = scopes
        self.loginBaseURL = loginBaseURL
        self.graphBaseURL = graphBaseURL
        self.tokenExpirySkew = tokenExpirySkew
        self.maxRetries = maxRetries
    }

    public var isRegistered: Bool { !(clientID ?? "").isEmpty }
}

public enum OneDriveError: Error, Equatable, Sendable {
    /// No client ID configured: the OneDrive app has not been registered.
    case needsAppRegistration
    /// No usable tokens (never signed in, or the refresh token was rejected).
    case notSignedIn
    case authorizationDeclined
    case deviceCodeExpired
    case badVerificationCode
    case authorizationFailed(String)
    /// Still throttled (429/503) after the allowed retries.
    case throttled(retryAfter: Int?)
}

public struct DeviceCodeChallenge: Equatable, Sendable {
    public var deviceCode: String
    public var userCode: String
    public var verificationURI: String
    public var expiresIn: Int
    public var interval: Int
    public var message: String?
}

public struct OneDriveTokens: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date
    public init(accessToken: String, refreshToken: String?, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

/// Where tokens are kept. The app supplies a Keychain implementation; tests use the in-memory one.
public protocol OneDriveTokenStore: Sendable {
    func load() async -> OneDriveTokens?
    func save(_ tokens: OneDriveTokens) async
    func clear() async
}

public actor InMemoryTokenStore: OneDriveTokenStore {
    private var tokens: OneDriveTokens?
    public init(_ tokens: OneDriveTokens? = nil) { self.tokens = tokens }
    public func load() -> OneDriveTokens? { tokens }
    public func save(_ tokens: OneDriveTokens) { self.tokens = tokens }
    public func clear() { tokens = nil }
}

public typealias OneDriveSleeper = @Sendable (TimeInterval) async -> Void
public typealias OneDriveClock = @Sendable () -> Date

public let defaultOneDriveSleeper: OneDriveSleeper = { seconds in
    try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
}

enum Form {
    private static let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    static func encode(_ pairs: [(String, String)]) -> Data {
        Data(pairs.map { key, value in
            (key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key) + "="
                + (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)
        }.joined(separator: "&").utf8)
    }
}
