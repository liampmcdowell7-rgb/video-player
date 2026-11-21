import Foundation
import VideoPlayerCore

/// The code the TV shows while the owner signs in on another device (docs/PLEX_SOURCE.md section 1; OPEN_QUESTIONS R302).
public struct PlexSignInCode: Equatable, Sendable {
    /// The PIN's id on plex.tv (not secret; used to ask whether the code was entered).
    public var id: String
    /// The short code the owner types on plex.tv/link.
    public var code: String
    /// Shown as plain text, never as a link or a logo.
    public var linkText: String
    /// When this app stops waiting and offers Get a New Code.
    public var expiresAt: Date

    public init(id: String, code: String, linkText: String = PlexPinSignIn.linkText, expiresAt: Date) {
        self.id = id; self.code = code; self.linkText = linkText; self.expiresAt = expiresAt
    }
}

/// The classic plex.tv PIN sign-in (R267 chosen flow, R302; JWT variant kept as the follow-up).
///
/// Re-read 20 Nov 2026 (https://developer.plex.tv/pms/#section/API-Info/Authenticating-with-Plex and the developer home):
/// - create: `POST https://plex.tv/api/v2/pins` with X-Plex-Product and X-Plex-Client-Identifier; "the two important
///   properties are id and code" (read). Without `strong=true` "a shorter pin is created but will have a much shorter
///   lifetime" (read 20 Nov on the developer home); short codes go with the link page `https://plex.tv/link/?pin=<code>`
///   (read). The TV asks WITHOUT `strong`, so the code is short enough to type on a phone.
/// - poll: `GET https://plex.tv/api/v2/pins/<id>` "once per second" until `authToken` is set (read on the developer home on
///   20 Nov; the re-read returned only the JWT form of the poll URL, so the classic poll URL is UNVERIFIED this time).
/// - expiry: no lifetime number is stated. This client stops at the PIN's `expiresIn` when the answer has one (field name
///   UNVERIFIED), otherwise after `fallbackLifetime` (PROVISIONAL 10 minutes, R302), and treats a 404 on the poll as an
///   expired code (UNVERIFIED).
/// The token is returned once to the caller, which stores it in the Keychain at once; it is never logged, never put in an
/// error, never shown.
public struct PlexPinSignIn: Sendable {
    public static let linkText = "plex.tv/link"
    public static let defaultFallbackLifetime: TimeInterval = 600

    private let http: PlexHTTP
    private let plexTV: URL
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let now: @Sendable () -> Date
    private let fallbackLifetime: TimeInterval
    /// Once per second, as the reference says.
    public let pollInterval: TimeInterval = 1

    public init(identity: PlexClientIdentity, transport: HTTPTransport, plexTV: URL = URL(string: "https://plex.tv")!,
                fallbackLifetime: TimeInterval = PlexPinSignIn.defaultFallbackLifetime,
                sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.http = PlexHTTP(identity: identity, transport: transport)
        self.plexTV = plexTV
        self.fallbackLifetime = fallbackLifetime
        self.sleep = sleep
        self.now = now
    }

    /// Asks plex.tv for a new short code.
    public func start() async throws -> PlexSignInCode {
        // design-lint:allow an HTTP method, code only, never shown
        let response = try await http.send(http.request("POST", plexTV.appendingPathComponent("api/v2/pins"), token: nil))
        let pin = try PlexHTTP.decode(PlexPinResponse.self, from: response)
        let lifetime = pin.expiresIn.map(TimeInterval.init) ?? fallbackLifetime
        return PlexSignInCode(id: pin.id, code: pin.code, expiresAt: now().addingTimeInterval(lifetime))
    }

    /// One look at the PIN: the account token when the code was entered, nil while it was not. A 404 means the code is gone.
    public func check(_ code: PlexSignInCode) async throws -> String? {
        if now() >= code.expiresAt { throw PlexError.codeExpired }
        let response = try await http.send(http.request("GET", plexTV.appendingPathComponent("api/v2/pins/\(code.id)"), token: nil))
        if response.statusCode == 404 { throw PlexError.codeExpired }
        return try PlexHTTP.decode(PlexPinResponse.self, from: response).authToken
    }

    /// Polls once per second until the owner entered the code (returns the account token) or the code expired.
    public func waitForToken(_ code: PlexSignInCode) async throws -> String {
        while true {
            try Task.checkCancellation()
            if let token = try await check(code) { return token }
            await sleep(pollInterval)
        }
    }
}
