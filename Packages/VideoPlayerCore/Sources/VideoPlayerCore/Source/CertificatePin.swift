import Foundation

// The decision logic for "trust this server's certificate or host key, once the user approved it, and refuse a different
// one later". Pure Swift (no TLS, no sockets): the app's transports (HTTP, FTPS, SFTP) compute the fingerprint of what the
// server presented and ask a `CertificatePin` whether to accept it. Every refusal is remembered here so the layer above
// can show an honest "the server's certificate changed" state instead of a vague network error. Nothing is ever
// auto-trusted: a pin is only ever set from a fingerprint the user approved (docs/SOURCES_WIRING.md).

public enum TrustKind: String, Sendable, Equatable, Codable {
    /// A TLS certificate (WebDAV, Jellyfin, Emby, UPnP over https, FTPS). Fingerprint: SHA-256 of the leaf certificate, hex.
    case tlsCertificate
    /// An SSH host key (SFTP). Fingerprint: "SHA256:<base64>" exactly as `ssh-keygen -l` prints it.
    case sshHostKey
}

public enum TrustFingerprint {
    /// Comparable form. Hex fingerprints: upper or lower case, with or without colons or spaces, all compare equal.
    /// SSH fingerprints ("SHA256:..." base64) are case-sensitive and kept as they are.
    public static func normalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.uppercased().hasPrefix("SHA256:") { return trimmed }
        return trimmed.filter { $0.isHexDigit }.lowercased()
    }

    public static func matches(_ a: String, _ b: String) -> Bool {
        let x = normalize(a), y = normalize(b)
        return !x.isEmpty && x == y
    }
}

/// What a pin refused: `expected` is nil when the user has not approved any fingerprint yet (first connection), and set
/// when the server now presents something different from what the user approved (it changed).
public struct TrustRefusal: Equatable, Sendable {
    public var kind: TrustKind
    public var host: String
    public var expected: String?
    public var presented: String
    public var isChange: Bool { expected != nil }

    public init(kind: TrustKind, host: String, expected: String?, presented: String) {
        self.kind = kind; self.host = host; self.expected = expected; self.presented = presented
    }
}

/// Thrown instead of a vague transport error when a pin refused a server (see `TrustGuardedSource`).
public struct TrustRefusedError: Error, Equatable, Sendable, LocalizedError {
    public var refusal: TrustRefusal
    public init(_ refusal: TrustRefusal) { self.refusal = refusal }

    public var errorDescription: String? {
        let what = refusal.kind == .sshHostKey ? "host key" : "certificate"
        if refusal.isChange {
            return "The server’s \(what) is not the one you approved. It may have been replaced, or someone may be pretending to be this server. Nothing was trusted automatically."
        }
        return "This server’s \(what) has not been approved yet."
    }
}

/// Asked by a transport with the fingerprint the server presented. Thread safe (transports call it from their own queues).
public final class CertificatePin: @unchecked Sendable {
    public let kind: TrustKind
    public let host: String
    public let trusted: String?
    private let lock = NSLock()
    private var refusal: TrustRefusal?
    private let onRefusal: (@Sendable (TrustRefusal) -> Void)?

    public init(kind: TrustKind, host: String, trusted: String?, onRefusal: (@Sendable (TrustRefusal) -> Void)? = nil) {
        self.kind = kind
        self.host = host
        let clean = trusted?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.trusted = (clean?.isEmpty ?? true) ? nil : clean
        self.onRefusal = onRefusal
    }

    /// True only when a fingerprint was approved and the presented one equals it. Otherwise the refusal is remembered.
    public func accepts(presented: String) -> Bool {
        if let trusted, TrustFingerprint.matches(trusted, presented) {
            return true
        }
        let r = TrustRefusal(kind: kind, host: host, expected: trusted, presented: presented)
        lock.withLock { refusal = r }
        onRefusal?(r)
        return false
    }

    /// The most recent refusal, without clearing it.
    public var lastRefusal: TrustRefusal? { lock.withLock { refusal } }

    /// The most recent refusal; clears it.
    public func takeRefusal() -> TrustRefusal? { lock.withLock { let r = refusal; refusal = nil; return r } }
}

/// Wraps a source so that a refusal by its pin surfaces as `TrustRefusedError` from every call (scan, browse, play), not as
/// whatever vague error the transport raised when it cancelled the connection.
public struct TrustGuardedSource: MediaSource {
    public let inner: any MediaSource
    public let pin: CertificatePin

    public init(_ inner: any MediaSource, pin: CertificatePin) { self.inner = inner; self.pin = pin }

    public var kind: SourceKind { inner.kind }
    public var capabilities: SourceCapabilities { inner.capabilities }

    private func guarded<T>(_ body: () async throws -> T) async throws -> T {
        do {
            let value = try await body()
            _ = pin.takeRefusal()   // the call worked, so an earlier refusal (a retry that then succeeded) is stale
            return value
        } catch {
            if let refusal = pin.takeRefusal() { throw TrustRefusedError(refusal) }
            throw error
        }
    }

    public func authenticate() async throws { try await guarded { try await inner.authenticate() } }
    public func list(_ path: String) async throws -> [SourceEntry] { try await guarded { try await inner.list(path) } }
    public func info(_ path: String) async throws -> SourceEntry { try await guarded { try await inner.info(path) } }
    public func read(_ path: String, range: ByteRange) async throws -> Data { try await guarded { try await inner.read(path, range: range) } }
    public func playbackAccess(for path: String) async throws -> PlaybackAccess { try await guarded { try await inner.playbackAccess(for: path) } }
}
