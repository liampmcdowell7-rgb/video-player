import Foundation
import VideoPlayerCore
import UserData

// Pure logic behind the source screens: error wording, the "certificate changed" state, Bonjour result mapping, the
// kind of definition -> what the screens show. Everything here runs in the Linux test run; the app target only displays it.

// MARK: Error wording

public enum SourceErrorText {
    /// One calm, honest message for anything a source can throw. Never a type name, never a secret.
    public static func state(for error: Error, doing what: String) -> ErrorState {
        if let trust = error as? TrustRefusedError {
            return TrustIssue(sourceID: "", sourceName: trust.refusal.host, refusal: trust.refusal).errorState
        }
        if let source = error as? SourceError {
            switch source {
            case .unauthorized:
                return ErrorState(title: "Could Not Sign In", message: "The server did not accept this user name and password.")
            case .forbidden:
                return ErrorState(title: "Not Allowed", message: "The server did not allow this account to open that folder or file.")
            case .notFound:
                return ErrorState(title: "Not Found", message: "That folder or file is no longer on the server.")
            case .invalidURL:
                return ErrorState(title: "Check the Address", message: "That address could not be understood.")
            case .httpStatus(let code):
                return ErrorState(title: "Couldn’t \(what)", message: "The server answered with an error (\(code)).")
            case .unsupportedAuthentication:
                return ErrorState(title: "Sign-In Method Not Supported", message: "The server asks for a sign-in method this app does not support.")
            case .insecureBasicAuthentication:
                return ErrorState(title: "Not Sent Without Encryption", message: "The server asks for the password over an unencrypted address. Use an https:// address.")
            case .unsupported(let message):
                return ErrorState(title: "Couldn’t \(what)", message: message)
            case .rangesNotSupported:
                return ErrorState(title: "Can’t Play From Here", message: "The server does not let the app jump around in the file.")
            case .rangeNotSatisfiable, .malformedResponse:
                return ErrorState(title: "Couldn’t \(what)", message: "The server sent an answer the app could not read.")
            case .transport(let text):
                let detail = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return ErrorState(title: "Couldn’t \(what)", message: detail.isEmpty ? "The connection failed. Check that the server is on and reachable." : "The connection failed: \(detail)")
            }
        }
        return ErrorState.from(error, doing: what)
    }
}

// MARK: Changed certificate or host key

/// The honest state shown when a pinned server presents something else (or, on first use, something not approved yet).
/// Nothing in here ever trusts anything by itself: `acceptTitle` is a button the user must press, after reading both fingerprints.
public struct TrustIssue: Equatable, Sendable, Identifiable {
    public var sourceID: String
    public var sourceName: String
    public var refusal: TrustRefusal
    public var id: String { sourceID }

    public init(sourceID: String, sourceName: String, refusal: TrustRefusal) {
        self.sourceID = sourceID; self.sourceName = sourceName; self.refusal = refusal
    }

    private var what: String { refusal.kind == .sshHostKey ? "Host Key" : "Certificate" }
    public var title: String { refusal.isChange ? "The Server’s \(what) Changed" : "This Server Is Not Approved Yet" }
    public var message: String {
        let lower = what.lowercased()
        if refusal.isChange {
            return "“\(sourceName)” now shows a \(lower) that is not the one you approved. This happens when the server was reinstalled or its \(lower) was renewed, but it can also mean someone else is answering instead of your server. Nothing was trusted automatically, and this source stays off until you decide."
        }
        return "“\(sourceName)” shows a \(lower) that you have not approved yet."
    }
    public var approvedFingerprint: String? { refusal.expected.map { TrustPrompt.display($0, kind: refusal.kind) } }
    public var presentedFingerprint: String { TrustPrompt.display(refusal.presented, kind: refusal.kind) }
    /// The value that would be saved if the user chooses to trust the new one (hex without colons, or the SHA256: text).
    public var savedValueIfTrusted: String { refusal.kind == .sshHostKey ? refusal.presented : TrustPrompt.grouped(refusal.presented).replacingOccurrences(of: ":", with: "") }
    public var acceptTitle: String { "Trust the New \(what)" }
    public var keepTitle: String { "Keep Blocking" }

    public var errorState: ErrorState {
        ErrorState(title: title, message: message, retryTitle: "Try Again")
    }
}

// MARK: Bonjour results

/// One service the system's browser found, after the app tried to resolve it to an address.
public struct BonjourService: Equatable, Sendable {
    public var type: String
    public var name: String
    /// The address or host name the connection actually used, when it could be resolved. Nil when resolution failed.
    public var resolvedHost: String?
    public var resolvedPort: Int?

    public init(type: String, name: String, resolvedHost: String? = nil, resolvedPort: Int? = nil) {
        self.type = type; self.name = name; self.resolvedHost = resolvedHost; self.resolvedPort = resolvedPort
    }
}

public enum BonjourMapping {
    /// The service types browsed (also listed in Info.plist `NSBonjourServices`; keep both in step).
    public static let serviceTypes: [(type: String, kind: SourceKind)] = [
        ("_webdav._tcp", .webdav), ("_webdavs._tcp", .webdav), ("_smb._tcp", .smb),
        ("_nfs._tcp", .nfs), ("_sftp-ssh._tcp", .sftp), ("_ftp._tcp", .ftp),
    ]

    private static let defaultPorts: [SourceKind: Int] = [.smb: 445, .nfs: 2049, .sftp: 22, .ftp: 21]

    public static func kind(forType type: String) -> SourceKind? {
        let clean = type.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return serviceTypes.first { $0.type == clean }?.kind
    }

    /// What the app used before addresses were resolved: the service name plus ".local". Still the fallback (editable in the form).
    public static func fallbackHost(forName name: String) -> String {
        let cleaned = name.lowercased().replacingOccurrences(of: " ", with: "-")
        return cleaned.hasSuffix(".local") ? cleaned : cleaned + ".local"
    }

    /// Text of a resolved IPv6 address with its scope ("fe80::1%en0") cannot be typed into a URL or a share address, so
    /// such a result counts as unresolved and the .local name is used instead.
    static func usableHost(_ host: String?) -> String? {
        guard var h = host?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty else { return nil }
        if h.hasSuffix(".") { h.removeLast() }
        if h.contains("%") || h.contains(":") { return nil }
        return h
    }

    public static func discovered(_ service: BonjourService) -> DiscoveredSource? {
        guard let kind = kind(forType: service.type) else { return nil }
        let resolved = usableHost(service.resolvedHost)
        let host = resolved ?? fallbackHost(forName: service.name)
        var port = service.resolvedPort
        if let p = port, p == defaultPorts[kind] { port = nil }
        var address: String?
        if kind == .webdav {
            let secure = service.type.lowercased().hasPrefix("_webdavs")
            address = (secure ? "https://" : "http://") + host + (port.map { ":\($0)" } ?? "")
        }
        return DiscoveredSource(kind: kind, name: service.name, host: host, port: port, address: address)
    }

    /// True when the host in `discovered` came from resolution (an address or the server's own name), false for the fallback.
    public static func isResolved(_ service: BonjourService) -> Bool { usableHost(service.resolvedHost) != nil }
}

// MARK: A folder of a source as the whole source

/// Presents one folder of a source as if it were the source's root: SMB with a chosen share, FTP with a start folder.
/// Paths the caller sees start at "/" and never reveal the folder in front; nothing can reach above the root folder.
public struct SubfolderSource: MediaSource {
    public let inner: any MediaSource
    /// "/Videos" or "/media/films"; "/" means no change.
    public let root: String

    public init(_ inner: any MediaSource, root: String) {
        self.inner = inner
        self.root = SubfolderSource.clean(root)
    }

    static func clean(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." { _ = parts.popLast(); continue }
            parts.append(part)
        }
        return "/" + parts.joined(separator: "/")
    }

    private func outer(_ path: String) -> String {
        let p = Self.clean(path)
        if root == "/" { return p }
        return p == "/" ? root : root + p
    }

    private func inward(_ path: String) -> String {
        if root == "/" { return path }
        if path == root { return "/" }
        if path.hasPrefix(root + "/") { return String(path.dropFirst(root.count)) }
        return path
    }

    private func map(_ entry: SourceEntry) -> SourceEntry {
        var e = entry
        e.path = inward(entry.path)
        if e.path == "/" { e.name = "" }
        return e
    }

    public var kind: SourceKind { inner.kind }
    public var capabilities: SourceCapabilities { inner.capabilities }
    public func authenticate() async throws { try await inner.authenticate() }
    public func list(_ path: String) async throws -> [SourceEntry] { try await inner.list(outer(path)).map(map) }
    public func info(_ path: String) async throws -> SourceEntry { map(try await inner.info(outer(path))) }
    public func read(_ path: String, range: ByteRange) async throws -> Data { try await inner.read(outer(path), range: range) }
    public func playbackAccess(for path: String) async throws -> PlaybackAccess { try await inner.playbackAccess(for: outer(path)) }
}

// MARK: What a saved source shows

public extension UDSourceDefinition {
    var sourceKind: SourceKind? { SourceKind(rawValue: kind) }

    /// The friendly type name ("SMB"), or the stored text when this version does not know the kind.
    var kindTitle: String { sourceKind.map { SourceCatalog.info(for: $0).title } ?? kind }

    /// The verification label for this source's type, exactly as the setup screen shows it.
    var verificationLabel: String? { sourceKind.map { SourceCatalog.statusLine($0) } }

    var caveat: String? { sourceKind.flatMap { SourceCatalog.caveat($0) } }

    var optionValues: [String: String] { SourceOptions.parse(options) }

    var hasApprovedFingerprint: Bool { !trustedFingerprint.isEmpty }

    /// The approved fingerprint as the user compares it, or nil when none is saved.
    var approvedFingerprintDisplay: String? {
        guard hasApprovedFingerprint else { return nil }
        let isSSH = trustedFingerprint.uppercased().hasPrefix("SHA256:")
        return TrustPrompt.display(trustedFingerprint, kind: isSSH ? .sshHostKey : .tlsCertificate)
    }
}
