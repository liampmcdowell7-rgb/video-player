import Foundation
import VideoPlayerCore
import LibraryIndex
import UserData

// The add-a-source flow, as data and a small state machine. The SwiftUI screens only show these types.

public enum SourceFieldKind: String, Equatable, Sendable { case name, address, host, port, share, folder, username, password, security }

/// One answer a picker field offers (a field with choices is shown as a picker, not a text field).
public struct SourceFieldChoice: Equatable, Sendable, Identifiable {
    public var value: String
    public var title: String
    public var id: String { value }
    public init(value: String, title: String) { self.value = value; self.title = title }
}

public struct SourceFieldSpec: Equatable, Sendable, Identifiable {
    public var kind: SourceFieldKind
    public var title: String
    public var prompt: String
    public var required: Bool
    public var isSecret: Bool
    /// Not empty: the field is a picker over these answers; `prompt` then holds the default answer's value.
    public var choices: [SourceFieldChoice] = []
    public var id: String { kind.rawValue }
}

public struct SourceKindInfo: Equatable, Sendable, Identifiable {
    public var kind: SourceKind
    public var title: String
    public var summary: String
    public var fields: [SourceFieldSpec]
    /// Honest status line: "Tested against a real server", "Not yet verified against a real server", ...
    public var statusLine: String
    /// A second honest sentence for what the status line does not cover (for example encrypted FTP). Nil when there is none.
    public var caveat: String?
    /// Why it cannot be set up here, with the alternative; nil when setup is possible.
    public var unavailableNote: String?
    /// True when the system can find servers of this kind by itself.
    public var canDiscover: Bool
    public var id: String { kind.rawValue }
    public var isAvailable: Bool { unavailableNote == nil }
}

public enum SourceCatalog {
    private static func f(_ k: SourceFieldKind, _ t: String, _ p: String, required: Bool = true, secret: Bool = false) -> SourceFieldSpec {
        SourceFieldSpec(kind: k, title: t, prompt: p, required: required, isSecret: secret)
    }
    private static let name = f(.name, "Name", "Living Room Server", required: false)
    private static let user = f(.username, "User Name", "Optional", required: false)
    private static let pass = f(.password, "Password", "Optional", required: false, secret: true)

    public static func statusLine(_ kind: SourceKind) -> String {
        switch kind.verification {
        case .notVerified: return "Not yet verified against a real server"
        case .contractTestsOnly: return "Tested with recorded replies only; not yet verified against a real server"
        case .realServer: return "Tested against a real server"
        case .onDevice: return "Tested on this kind of device"
        }
    }

    private static let ftpSecurity = SourceFieldSpec(
        kind: .security, title: "Encryption", prompt: "none", required: false, isSecret: false,
        choices: [SourceFieldChoice(value: "none", title: "None (plain FTP)"),
                  SourceFieldChoice(value: "explicit", title: "Explicit TLS (FTPS)"),
                  SourceFieldChoice(value: "implicit", title: "Implicit TLS (FTPS)")])

    /// The exact wording the Settings and setup screens show for OneDrive until an app registration exists.
    public static let oneDriveBlockedNote = "blocked: needs an app registration. No app has been registered with Microsoft yet, so there is nothing to sign in to. Share a OneDrive link and add it as a Web Link, or use a WebDAV bridge."

    /// What the status line does not cover. Honest and short; nil when nothing needs adding.
    public static func caveat(_ kind: SourceKind) -> String? {
        switch kind {
        case .webdav, .jellyfin, .emby:
            return "Approving a server’s own certificate (https) has not been tested against a real server."
        case .ftp:
            return "Plain FTP was tested against a real server. Encrypted FTP (FTPS), explicit and implicit, has not been."
        case .upnp:
            return "Finding servers by themselves has not been tested on a device. If none appears, type the device address."
        case .sftp:
            return "Only password sign-in is offered here. The server’s host key is shown once for you to approve and is checked on every connection."
        default:
            return nil
        }
    }

    /// `oneDriveClientID` is the app registration's client ID. Nil or empty (the case today: nothing is registered, and no ID is
    /// invented anywhere) keeps OneDrive visible but blocked.
    public static func info(for kind: SourceKind, oneDriveClientID: String? = nil) -> SourceKindInfo {
        var title = "", summary = "", fields: [SourceFieldSpec] = [], discover = false, note: String?
        switch kind {
        case .webdav:
            title = "WebDAV"; summary = "A web folder, for example on a NAS."; discover = true
            fields = [name, f(.address, "Address", "https://nas.local/videos"), user, pass]
        case .smb:
            title = "SMB"; summary = "A shared folder on a computer or NAS."; discover = true
            fields = [name, f(.host, "Server", "nas.local"), f(.port, "Port", "445", required: false), f(.share, "Shared Folder", "Videos"), user, pass]
        case .nfs:
            title = "NFS"; summary = "An exported folder on a NAS or Linux server."; discover = true
            fields = [name, f(.host, "Server", "nas.local"), f(.folder, "Exported Folder", "/volume1/videos")]
        case .sftp:
            title = "SFTP"; summary = "A folder reached over SSH (SFTP)."; discover = true
            fields = [name, f(.host, "Server", "nas.local"), f(.port, "Port", "22", required: false),
                      f(.folder, "Start Folder", "/", required: false), f(.username, "User Name", "Required"),
                      f(.password, "Password", "Required", secret: true)]
        case .ftp:
            title = "FTP"; summary = "A folder on an FTP server."; discover = true
            fields = [name, f(.host, "Server", "nas.local"), f(.port, "Port", "21", required: false), ftpSecurity,
                      f(.folder, "Start Folder", "/", required: false), user, pass]
        case .upnp:
            title = "UPnP/DLNA"; summary = "A UPnP/DLNA media server on your network, found automatically or by its address."; discover = true
            fields = [name, f(.address, "Device Address", "http://nas.local:8200/rootDesc.xml")]
        case .jellyfin:
            title = "Jellyfin"; summary = "A Jellyfin media server."
            fields = [name, f(.address, "Address", "http://server.local:8096"), f(.username, "User Name", "Required"), pass]
        case .emby:
            title = "Emby"; summary = "An Emby media server."
            fields = [name, f(.address, "Address", "http://server.local:8096"), f(.username, "User Name", "Required"), pass]
        case .directLink:
            title = "Web Link"; summary = "A direct link to one video file, including Dropbox, Google Drive and OneDrive file links. An iCloud Drive sharing page cannot be played."
            fields = [name, f(.address, "Link", "https://example.com/video.mkv")]
        case .plex:
            title = "Plex"; summary = "A Plex media server."
            note = "blocked: Plex needs a Plex account sign-in, which this app does not offer yet. Use the Plex server’s media folder through SMB or WebDAV instead."
        case .oneDrive:
            title = "OneDrive"; summary = "A OneDrive folder."
            if (oneDriveClientID ?? "").isEmpty { note = oneDriveBlockedNote } else { fields = [name] }
        case .dropbox:
            title = "Dropbox"; summary = "A Dropbox folder."
            note = "blocked: Dropbox has no sign-in for TVs. Add a Dropbox shared link as a Web Link, or use a WebDAV bridge."
        case .googleDrive:
            title = "Google Drive"; summary = "A Google Drive folder."
            note = "blocked: a TV sign-in cannot browse a whole Google Drive. Add a Google Drive shared link as a Web Link."
        }
        return SourceKindInfo(kind: kind, title: title, summary: summary, fields: fields, statusLine: statusLine(kind),
                              caveat: caveat(kind), unavailableNote: note, canDiscover: discover)
    }

    /// Every kind exactly once, available ones first (nothing is hidden: unavailable kinds explain themselves).
    public static func catalog(oneDriveClientID: String? = nil) -> [SourceKindInfo] {
        let infos = SourceKind.allCases.map { info(for: $0, oneDriveClientID: oneDriveClientID) }
        return infos.filter(\.isAvailable) + infos.filter { !$0.isAvailable }
    }

    public static var all: [SourceKindInfo] { catalog() }
}

public struct SourceDraft: Equatable, Sendable {
    public var kind: SourceKind
    public var values: [SourceFieldKind: String] = [:]
    public init(kind: SourceKind, values: [SourceFieldKind: String] = [:]) { self.kind = kind; self.values = values }

    public subscript(_ field: SourceFieldKind) -> String {
        get { values[field] ?? "" }
        set { values[field] = newValue }
    }

    /// Fills the fields from a server the system found.
    public init(discovered: DiscoveredSource) {
        self.kind = discovered.kind
        values[.name] = discovered.name
        values[.host] = discovered.host
        if let address = discovered.address, !address.isEmpty {
            values[.address] = address
        } else if discovered.kind == .webdav {
            values[.address] = "http://\(discovered.host)" + (discovered.port.map { ":\($0)" } ?? "")
        }
        if let port = discovered.port { values[.port] = String(port) }
    }

    public var displayName: String {
        let typed = self[.name].trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        let host = !self[.host].isEmpty ? self[.host] : (URL(string: self[.address])?.host ?? "")
        return host.isEmpty ? SourceCatalog.info(for: kind).title : host
    }
}

public struct FieldProblem: Equatable, Sendable {
    public var field: SourceFieldKind
    public var message: String
}

public enum SourceDraftValidator {
    public static func problems(_ draft: SourceDraft) -> [FieldProblem] {
        let info = SourceCatalog.info(for: draft.kind)
        var out: [FieldProblem] = []
        for spec in info.fields {
            let value = draft[spec.kind].trimmingCharacters(in: .whitespacesAndNewlines)
            if spec.required && value.isEmpty { out.append(FieldProblem(field: spec.kind, message: "Enter the \(spec.title.lowercased()).")); continue }
            if value.isEmpty { continue }
            switch spec.kind {
            case .address:
                guard let url = URL(string: value), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                      let host = url.host, !host.isEmpty else {
                    out.append(FieldProblem(field: .address, message: "Enter a full address that starts with http:// or https://.")); continue
                }
            case .host:
                if value.contains(" ") || value.contains("/") || value.contains("://") {
                    out.append(FieldProblem(field: .host, message: "Enter only the server’s name or number, without spaces or slashes."))
                }
            case .security:
                if !spec.choices.contains(where: { $0.value == value }) {
                    out.append(FieldProblem(field: .security, message: "Choose one of the listed answers."))
                }
            case .port:
                if Int(value).map({ !(1...65535).contains($0) }) ?? true {
                    out.append(FieldProblem(field: .port, message: "A port is a number from 1 to 65535."))
                }
            default: break
            }
        }
        return out
    }
}

/// Shown when a secure server presents a certificate or host key the user has not approved yet (a home server with its own
/// certificate, or an SSH server seen for the first time).
public struct TrustPrompt: Equatable, Sendable {
    public var host: String
    /// What the user compares, in groups ("AB:CD:..." for a certificate, "SHA256:..." for a host key).
    public var fingerprint: String
    /// What gets saved when the user approves: hex without colons (upper case) for a certificate, the "SHA256:..." text for a host key.
    public var savedValue: String
    public var kind: TrustKind

    public init(host: String, fingerprint: String, savedValue: String? = nil, kind: TrustKind = .tlsCertificate) {
        self.host = host
        self.fingerprint = fingerprint
        self.savedValue = savedValue ?? fingerprint.replacingOccurrences(of: ":", with: "")
        self.kind = kind
    }

    public var title: String { "Trust “\(host)”?" }
    public var message: String {
        switch kind {
        case .tlsCertificate:
            return "This server’s certificate is not signed by an authority the system knows. If you set the server up yourself, check that this fingerprint matches the one shown in the server’s own settings, then choose Trust."
        case .sshHostKey:
            return "This is the first time this app connects to this server, so it cannot know the server is the one you mean. If you set the server up yourself, check that this fingerprint matches the one the server shows (for example with ssh-keygen -l), then choose Trust."
        }
    }
    public var trustTitle: String { "Trust This Server" }
    public var cancelTitle: String { "Cancel" }
    /// "AB:CD:..." in groups, easier to compare than one long string.
    public static func grouped(_ hex: String) -> String {
        let clean = hex.uppercased().filter { $0.isHexDigit }
        return stride(from: 0, to: clean.count, by: 2).map { i in
            let s = clean.index(clean.startIndex, offsetBy: i), e = clean.index(s, offsetBy: min(2, clean.count - i))
            return String(clean[s..<e])
        }.joined(separator: ":")
    }
    /// Display form of a saved or presented fingerprint of either kind.
    public static func display(_ value: String, kind: TrustKind) -> String {
        kind == .sshHostKey ? value : grouped(value)
    }
}

/// What a device sign-in asks the user to do on another device (OneDrive's TV sign-in). Only shown once an app registration exists.
public struct DeviceSignIn: Equatable, Sendable {
    public var userCode: String
    public var verificationAddress: String
    public var expiresInSeconds: Int
    public init(userCode: String, verificationAddress: String, expiresInSeconds: Int) {
        self.userCode = userCode; self.verificationAddress = verificationAddress; self.expiresInSeconds = expiresInSeconds
    }
    public var title: String { "Sign In on Another Device" }
    public var message: String { "On a phone or computer, open \(verificationAddress) and enter the code \(userCode). Then come back here and choose Continue." }
}

public enum ConnectionOutcome: Equatable, Sendable {
    case connected
    /// The server presented a certificate (hex) that the system does not trust and the user has not approved.
    case untrustedCertificate(host: String, fingerprintHex: String)
    /// An SSH server's host key ("SHA256:...") that the user has not approved.
    case unapprovedHostKey(host: String, fingerprint: String)
    case needsSignIn(DeviceSignIn)
}

/// Opens a connection with a draft and its password and reports the outcome. The real one lives in the app target; a source
/// type it cannot open yet throws `SourceError.unsupported` with an honest message.
public protocol SourceConnecting: Sendable {
    /// `trustedFingerprint` is what the user approved earlier in this flow (nil before). A refused certificate or key is
    /// reported as an outcome, never accepted silently.
    func test(_ draft: SourceDraft, trustedFingerprint: String?) async throws -> ConnectionOutcome
    /// Continues a device sign-in after the user did it on the other device.
    func finishSignIn(_ draft: SourceDraft) async throws -> ConnectionOutcome
    /// The secret to keep for the new source: the password by default; a sign-in kind returns its tokens.
    func secretToSave(for draft: SourceDraft) async -> String?
}

public extension SourceConnecting {
    func finishSignIn(_ draft: SourceDraft) async throws -> ConnectionOutcome { throw SourceError.unsupported("This source type has no sign-in step.") }
    func secretToSave(for draft: SourceDraft) async -> String? { draft[.password].isEmpty ? nil : draft[.password] }
}

public protocol SecretSaving: Sendable {
    func saveSecret(_ secret: String, for sourceID: String) async throws -> CloudSecretState
}
extension MirroredSecrets: SecretSaving {
    public func saveSecret(_ secret: String, for sourceID: String) async throws -> CloudSecretState { try await set(secret, for: sourceID) }
}

/// Where the non-secret connection settings of a saved source are kept (host, port, path, user name), so the app can
/// reconnect after a relaunch. The real one writes into the user-data ledger (which syncs and is copied to the essentials).
public protocol SourceDefinitionSaving: Sendable {
    func saveDefinition(_ definition: UDSourceDefinition) async throws
}

/// "key=value" pairs joined by "&", the format of `UDSourceDefinition.options`. Keys and values never contain "&" or "=".
public enum SourceOptions {
    public static func parse(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in text.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 { out[String(parts[0])] = String(parts[1]) }
        }
        return out
    }
    public static func format(_ values: [String: String]) -> String {
        values.filter { !$0.value.isEmpty }.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
    }
}

public extension SourceDraft {
    /// PROVISIONAL mapping (docs/SOURCES_WIRING.md has the table, alternatives there): address kinds (WebDAV, UPnP, Jellyfin, Emby,
    /// Web Link) keep the full address in `path` and its host and port in `host` and `port`; SMB keeps the share in `path`; NFS the
    /// exported folder in `path`; SFTP and FTP the start folder in `path`; FTP keeps its encryption choice in `options`
    /// ("security=explicit"). The password is never part of it. `trustedFingerprint` is what the user approved ("" when none).
    func definition(id: String, addedAt: Date = Date(), trustedFingerprint: String = "") -> UDSourceDefinition {
        let address = self[.address].trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(string: address)
        var host = self[.host].trimmingCharacters(in: .whitespacesAndNewlines)
        var port = Int(self[.port].trimmingCharacters(in: .whitespacesAndNewlines))
        var path = ""
        if !address.isEmpty {
            host = url?.host ?? host
            port = url?.port ?? port
            path = address
        } else if !self[.share].isEmpty {
            path = self[.share]
        } else if !self[.folder].isEmpty {
            path = self[.folder].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var options: [String: String] = [:]
        if kind == .ftp {
            let security = self[.security]
            options["security"] = security.isEmpty ? "none" : security
        }
        let auth: String
        if kind == .oneDrive { auth = "oauth" } else { auth = self[.password].isEmpty ? "none" : "password" }
        return UDSourceDefinition(id: id, kind: kind.rawValue, name: displayName, host: host, port: port, path: path,
                                  username: self[.username], auth: auth, addedAt: addedAt,
                                  options: SourceOptions.format(options), trustedFingerprint: trustedFingerprint)
    }
}

/// Keeps definitions in a `UserDataLedger` and copies the source list and settings to the essentials store.
public final class LedgerSourceDefinitions: SourceDefinitionSaving, @unchecked Sendable {
    private let ledger: UserDataLedger
    private let essentials: UDEssentialsStore?
    public init(ledger: UserDataLedger, essentials: UDEssentialsStore?) {
        self.ledger = ledger
        self.essentials = essentials
    }
    public func saveDefinition(_ definition: UDSourceDefinition) async throws {
        ledger.upsertSource(definition)
        try essentials?.save(from: ledger)
    }
}

public enum SetupPhase: Equatable, Sendable {
    case editing
    case testing
    case needsTrust(TrustPrompt)
    case needsSignIn(DeviceSignIn)
    case failed(ErrorState)
    case saved(LibrarySourceRecord)
}

public struct SourceSetupViewModel: Sendable {
    public let store: any LibraryStore
    public let connector: any SourceConnecting
    public let secrets: any SecretSaving
    public let definitions: (any SourceDefinitionSaving)?
    public private(set) var draft: SourceDraft
    public private(set) var phase: SetupPhase = .editing
    public private(set) var showProblems = false
    /// What the user approved in this flow (saved into the definition on success).
    private var trusted: String?
    private let makeID: @Sendable () -> String

    public init(store: any LibraryStore, connector: any SourceConnecting, secrets: any SecretSaving, draft: SourceDraft,
                definitions: (any SourceDefinitionSaving)? = nil, makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }) {
        self.store = store; self.connector = connector; self.secrets = secrets; self.definitions = definitions; self.draft = draft; self.makeID = makeID
    }

    public var info: SourceKindInfo { SourceCatalog.info(for: draft.kind, oneDriveClientID: oneDriveClientID) }
    /// Set by the app from its configuration; nil today (no app registration exists, none is invented).
    public var oneDriveClientID: String?
    public var problems: [FieldProblem] { showProblems ? SourceDraftValidator.problems(draft) : [] }
    public func problem(for field: SourceFieldKind) -> String? { problems.first { $0.field == field }?.message }
    public var canSave: Bool { info.isAvailable && SourceDraftValidator.problems(draft).isEmpty }

    public mutating func set(_ field: SourceFieldKind, _ value: String) {
        draft[field] = value
        // An approval belongs to the server it was given for: changing where we connect drops it.
        if [.host, .port, .address].contains(field) { trusted = nil }
        if case .failed = phase { phase = .editing }
    }

    /// Tests the connection, asks about an unapproved certificate or host key, and saves the source and its password on success.
    public mutating func connect() async {
        showProblems = true
        guard info.isAvailable else { return }
        guard SourceDraftValidator.problems(draft).isEmpty else { phase = .editing; return }
        phase = .testing
        do {
            try await handle(try await connector.test(draft, trustedFingerprint: trusted))
        } catch {
            fail(error)
        }
    }

    /// After the user did the sign-in on the other device.
    public mutating func continueAfterSignIn() async {
        guard case .needsSignIn = phase else { return }
        phase = .testing
        do {
            try await handle(try await connector.finishSignIn(draft))
        } catch {
            fail(error)
        }
    }

    public mutating func cancelSignIn() { if case .needsSignIn = phase { phase = .editing } }

    public mutating func trustAndContinue() async {
        guard case .needsTrust(let prompt) = phase else { return }
        trusted = prompt.savedValue
        await connect()
    }

    public mutating func cancelTrust() { if case .needsTrust = phase { phase = .editing } }

    /// The user closed the failure message.
    public mutating func dismissFailure() { if case .failed = phase { phase = .editing } }

    private mutating func handle(_ outcome: ConnectionOutcome) async throws {
        switch outcome {
        case .connected:
            try await save()
        case .untrustedCertificate(let host, let hex):
            phase = .needsTrust(TrustPrompt(host: host, fingerprint: TrustPrompt.grouped(hex), savedValue: TrustPrompt.grouped(hex).replacingOccurrences(of: ":", with: ""), kind: .tlsCertificate))
        case .unapprovedHostKey(let host, let fingerprint):
            phase = .needsTrust(TrustPrompt(host: host, fingerprint: fingerprint, savedValue: fingerprint, kind: .sshHostKey))
        case .needsSignIn(let signIn):
            phase = .needsSignIn(signIn)
        }
    }

    private mutating func fail(_ error: Error) {
        if let source = error as? SourceError, source == .unauthorized {
            phase = .failed(ErrorState(title: "Could Not Sign In", message: "The server did not accept this user name and password."))
        } else {
            phase = .failed(SourceErrorText.state(for: error, doing: "connect to this server"))
        }
    }

    private mutating func save() async throws {
        let id = makeID()
        let record = LibrarySourceRecord(id: id, kind: draft.kind, name: draft.displayName)
        if let secret = await connector.secretToSave(for: draft), !secret.isEmpty { _ = try await secrets.saveSecret(secret, for: id) }
        try await definitions?.saveDefinition(draft.definition(id: id, addedAt: record.addedAt, trustedFingerprint: trusted ?? ""))
        try await store.upsertSource(record)
        phase = .saved(record)
    }
}
