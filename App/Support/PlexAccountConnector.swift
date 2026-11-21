import Foundation
import VideoPlayerCore
import UserData
import AppLogic
import SourcePlex

/// The live Plex account side of Add a Source > Plex (docs/PLEX_SOURCE.md sections 1 to 3; OPEN_QUESTIONS R302, R303).
///
/// It asks plex.tv for a short code, polls once per second until the owner entered it, and writes the account token to
/// this Apple TV's Keychain at once (`credentials`, the local `KeychainCredentialStore`, not synchronizable). The account
/// token is never returned to the screen, never logged and never put in an error; it is kept on this device only (R302).
/// With it, the connector lists the account's servers and finds the first connection of the chosen one that answers
/// (local HTTPS, local HTTP, remote HTTPS; the relay stays off, R303). The chosen server's own token is handed to the
/// setup model once, which saves it as the source secret (mirrored like every other source secret).
final class PlexAccountConnector: PlexAccountConnecting, @unchecked Sendable {
    /// The Keychain account under which the plex.tv account token is kept (one per Apple TV, not per source).
    static let accountKey = "plex-account"

    private let signIn: PlexPinSignIn
    private let list: PlexServerList
    private let probe: PlexConnectionProbe
    private let credentials: any CredentialStore
    private let lock = NSLock()
    /// The codes handed out, so the poll can use the PIN id the screen never sees.
    private var pending: [String: PlexSignInCode] = [:]
    /// The servers of the last list, by machine identifier (their tokens and connections stay here).
    private var known: [String: PlexServer] = [:]

    init(deviceID: String, credentials: any CredentialStore, transport: HTTPTransport = URLSessionTransport()) {
        let identity = PlexClientIdentity(clientIdentifier: deviceID)
        self.signIn = PlexPinSignIn(identity: identity, transport: transport)
        self.list = PlexServerList(identity: identity, transport: transport)
        self.probe = PlexConnectionProbe(identity: identity, transport: transport)
        self.credentials = credentials
    }

    func isSignedIn() async -> Bool {
        ((try? credentials.secret(for: Self.accountKey)) ?? nil)?.isEmpty == false
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

    func servers() async throws -> [PlexServerChoice] {
        guard let token = try credentials.secret(for: Self.accountKey), !token.isEmpty else { throw SourceError.unauthorized }
        let servers: [PlexServer]
        do {
            servers = try await list.servers(accountToken: token)
        } catch SourceError.unauthorized {
            // The account token was revoked: forget it, so the page asks for a new code next time.
            try? credentials.removeSecret(for: Self.accountKey)
            throw SourceError.unauthorized
        }
        lock.withLock { known = Dictionary(servers.map { ($0.machineIdentifier, $0) }, uniquingKeysWith: { first, _ in first }) }
        return servers.map { PlexServerChoice(id: $0.machineIdentifier, name: $0.name, isLocal: $0.isLocal) }
    }

    func connect(_ choice: PlexServerChoice) async throws -> PlexServerConnection {
        guard let server = lock.withLock({ known[choice.id] }) else { throw PlexSetupError.unreachable }
        // The resource's own token; an owned server without one falls back to the account token (UNVERIFIED which happens).
        guard let token = server.accessToken ?? (try credentials.secret(for: Self.accountKey)) else { throw SourceError.unauthorized }
        do {
            let connection = try await probe.firstReachable(server, allowRelay: false)
            return PlexServerConnection(machineIdentifier: server.machineIdentifier, name: server.name, uri: connection.uri,
                                        token: token, isRelay: connection.relay)
        } catch PlexError.onlyRelay {
            throw PlexSetupError.onlyRelay
        } catch PlexError.serverUnreachable {
            throw PlexSetupError.unreachable
        }
    }
}
