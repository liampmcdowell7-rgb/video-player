import Foundation
import VideoPlayerCore
import LibraryIndex
import UserData

// Add a Source > Plex, as data and a small state machine (docs/PLEX_SOURCE.md sections 1, 2 and 10; OPEN_QUESTIONS R302,
// R303). The screen (App/Features/Sources/PlexSetupView.swift) only shows these types. The account token never reaches
// the model: the connector keeps it in the Keychain. A server's token passes through once, on its way to the source
// secrets (mirrored like every other source secret, R269 recommendation).

/// The code to show while the owner signs in on another device.
public struct PlexCode: Equatable, Sendable {
    public var code: String
    public var linkText: String
    public var expiresAt: Date
    public init(code: String, linkText: String, expiresAt: Date) {
        self.code = code; self.linkText = linkText; self.expiresAt = expiresAt
    }
}

/// One row of the server list: the name and "Local" or "Remote" (R303).
public struct PlexServerChoice: Equatable, Sendable, Identifiable {
    /// The server's machine identifier.
    public var id: String
    public var name: String
    public var isLocal: Bool
    public init(id: String, name: String, isLocal: Bool) { self.id = id; self.name = name; self.isLocal = isLocal }
    public var detail: String { isLocal ? PlexSetupText.local : PlexSetupText.remote }
}

/// What adding a server needs: where it answered and its token (saved as the source secret, never shown).
public struct PlexServerConnection: Sendable {
    public var machineIdentifier: String
    public var name: String
    /// The connection that answered first in the R303 order, for example "https://192-168-1-20.<id>.plex.direct:32400".
    public var uri: String
    public var token: String
    public var isRelay: Bool
    public init(machineIdentifier: String, name: String, uri: String, token: String, isRelay: Bool = false) {
        self.machineIdentifier = machineIdentifier; self.name = name; self.uri = uri; self.token = token; self.isRelay = isRelay
    }
}

/// Errors the Plex setup flow tells apart (the live connector maps the client's errors onto these).
public enum PlexSetupError: Error, Equatable, Sendable {
    case codeExpired
    /// The relay is the only way to the server and it is off (R268).
    case onlyRelay
    case unreachable
}

/// The Plex account side of the setup flow. The real one lives in the app target (it talks to plex.tv and the Keychain).
public protocol PlexAccountConnecting: Sendable {
    /// True when an account token from an earlier sign-in is in this Apple TV's Keychain.
    func isSignedIn() async -> Bool
    /// Asks plex.tv for a new short code.
    func newCode() async throws -> PlexCode
    /// Returns once the owner entered the code on plex.tv/link, with the account token already stored in the Keychain.
    /// Throws `PlexSetupError.codeExpired` when the code ran out first.
    func waitForSignIn(_ code: PlexCode) async throws
    /// The account's media servers.
    func servers() async throws -> [PlexServerChoice]
    /// Finds the first connection of the server that answers (R303 order). Throws `PlexSetupError.onlyRelay` or `.unreachable`.
    func connect(_ server: PlexServerChoice) async throws -> PlexServerConnection
}

public enum PlexSetupPhase: Equatable, Sendable {
    case gettingCode
    case code(PlexCode)
    case codeExpired
    case loadingServers
    case servers([PlexServerChoice])
    case noServers
    case connecting(PlexServerChoice)
    case saved(LibrarySourceRecord)
    case failed(ErrorState)
}

/// Texts of the Plex pages. HIG Managing accounts (read 20 Nov 2026), tvOS: "Prefer letting people use another device to
/// sign up or authenticate" and "Minimize data entry"; "Always identify the authentication method you offer"; "Explain the
/// benefits of creating an account ... Display this message in your sign-in view"; "Avoid using the term passcode".
public enum PlexSetupText {
    public static let signInTitle = "Sign In to Plex"
    public static func instruction(link: String) -> String {
        "On your phone or computer, go to \(link) and enter this code."
    }
    public static let why = "Signing in finds your Plex servers. Your Plex password is never entered on this Apple TV."
    public static let waiting = "Waiting for the code to be entered."
    public static let expired = "This code expired."
    public static let newCode = "Get a New Code"
    public static let gettingCode = "Getting a code."
    public static let serversTitle = "Choose a Server"
    public static let serversFooter = "Each server is added as its own source. The app plays files from the server as they are and never changes anything on it."
    public static let local = "Local"
    public static let remote = "Remote"
    public static let loadingServers = "Finding your servers."
    public static let noServersTitle = "No Servers"
    public static let noServers = "This Plex account has no server this app can use."
    public static let onlyRelay = "This server can be reached only through the Plex relay, which is off. Connect the Apple TV to the same network as the server and try again."
    public static let unreachable = "The server did not answer. Check that it is turned on and on the same network, then try again."
}

public struct PlexSetupModel: Sendable {
    public let account: any PlexAccountConnecting
    public let store: any LibraryStore
    public let secrets: any SecretSaving
    public let definitions: (any SourceDefinitionSaving)?
    public private(set) var phase: PlexSetupPhase = .gettingCode
    private let makeID: @Sendable () -> String

    public init(account: any PlexAccountConnecting, store: any LibraryStore, secrets: any SecretSaving,
                definitions: (any SourceDefinitionSaving)? = nil, makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }) {
        self.account = account; self.store = store; self.secrets = secrets; self.definitions = definitions; self.makeID = makeID
    }

    /// Opens the page: straight to the server list when this Apple TV is already signed in, otherwise a code.
    public mutating func start() async {
        if await account.isSignedIn() { await loadServers() } else { await requestCode() }
    }

    /// Gets a code; the screen calls `waitForSignIn()` next. Also the Get a New Code action.
    public mutating func requestCode() async {
        phase = .gettingCode
        do { phase = .code(try await account.newCode()) }
        catch { fail(error, doing: "get a sign-in code") }
    }

    /// Waits until the owner entered the code (polling is the connector's job) or the code ran out; then lists the servers.
    public mutating func waitForSignIn() async {
        guard case .code(let code) = phase else { return }
        do {
            try await account.waitForSignIn(code)
        } catch PlexSetupError.codeExpired {
            phase = .codeExpired
            return
        } catch is CancellationError {
            return
        } catch {
            fail(error, doing: "sign in to Plex")
            return
        }
        await loadServers()
    }

    public mutating func loadServers() async {
        phase = .loadingServers
        do {
            let servers = try await account.servers()
            phase = servers.isEmpty ? .noServers : .servers(servers)
        } catch is CancellationError {
            return
        } catch {
            fail(error, doing: "find your Plex servers")
        }
    }

    /// Connects to the chosen server and saves it as a source: the definition (no secret in it) and the server token as the
    /// source secret.
    public mutating func add(_ server: PlexServerChoice) async {
        phase = .connecting(server)
        do {
            let connection = try await account.connect(server)
            let id = makeID()
            let record = LibrarySourceRecord(id: id, kind: .plex, name: connection.name)
            _ = try await secrets.saveSecret(connection.token, for: id)
            try await definitions?.saveDefinition(Self.definition(connection, id: id, addedAt: record.addedAt))
            try await store.upsertSource(record)
            phase = .saved(record)
        } catch PlexSetupError.onlyRelay {
            phase = .failed(ErrorState(title: "Cannot Reach the Server", message: PlexSetupText.onlyRelay))
        } catch PlexSetupError.unreachable {
            phase = .failed(ErrorState(title: "Cannot Reach the Server", message: PlexSetupText.unreachable))
        } catch is CancellationError {
            return
        } catch {
            fail(error, doing: "add this server")
        }
    }

    /// The non-secret settings of a Plex source (R303): the address that answered in `path` (its host and port in `host` and
    /// `port`), the server's machine identifier and the relay choice in `options`, `auth` "token". The token is never in it.
    public static func definition(_ connection: PlexServerConnection, id: String, addedAt: Date) -> UDSourceDefinition {
        let url = URL(string: connection.uri)
        return UDSourceDefinition(id: id, kind: SourceKind.plex.rawValue, name: connection.name, host: url?.host ?? "", port: url?.port,
                                  path: connection.uri, auth: "token", addedAt: addedAt,
                                  options: SourceOptions.format(["machine": connection.machineIdentifier, "relay": connection.isRelay ? "on" : "off"]))
    }

    private mutating func fail(_ error: Error, doing what: String) {
        phase = .failed(SourceErrorText.state(for: error, doing: what))
    }
}
