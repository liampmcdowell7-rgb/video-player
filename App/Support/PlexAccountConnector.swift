import Foundation
import VideoPlayerCore
import UserData
import AppLogic
import SourcePlex

/// The live Plex account side of Add a Source > Plex (docs/PLEX_SOURCE.md sections 1 and 3; OPEN_QUESTIONS R302).
///
/// It asks plex.tv for a short code, polls once per second until the owner entered it, and writes the account token to
/// this Apple TV's Keychain at once (`credentials`, the local `KeychainCredentialStore`, not synchronizable). The token is
/// never returned to the screen, never logged and never put in an error. The account token is kept on this device only
/// (R302): the server tokens that playback needs are the mirrored source secrets (stage 3, R303).
final class PlexAccountConnector: PlexAccountConnecting, @unchecked Sendable {
    /// The Keychain account under which the plex.tv account token is kept (one per Apple TV, not per source).
    static let accountKey = "plex-account"

    private let signIn: PlexPinSignIn
    private let credentials: any CredentialStore
    private let lock = NSLock()
    /// The codes handed out, so the poll can use the PIN id the screen never sees.
    private var pending: [String: PlexSignInCode] = [:]

    init(deviceID: String, credentials: any CredentialStore, transport: HTTPTransport = URLSessionTransport()) {
        self.signIn = PlexPinSignIn(identity: PlexClientIdentity(clientIdentifier: deviceID), transport: transport)
        self.credentials = credentials
    }

    func newCode() async throws -> PlexCode {
        let code = try await signIn.start()
        lock.withLock { pending[code.code] = code }
        return PlexCode(code: code.code, linkText: code.linkText, expiresAt: code.expiresAt)
    }

    func waitForSignIn(_ code: PlexCode) async throws {
        guard let pin = lock.withLock({ pending[code.code] }) else { throw PlexSetupError.codeExpired }
        do {
            let token = try await signIn.waitForToken(pin)
            try credentials.setSecret(token, for: Self.accountKey)
            lock.withLock { pending[code.code] = nil }
        } catch PlexError.codeExpired {
            lock.withLock { pending[code.code] = nil }
            throw PlexSetupError.codeExpired
        }
    }
}
