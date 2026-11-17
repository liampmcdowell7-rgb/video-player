import Foundation
import VideoPlayerCore

/// Enforces the host key the user approved. The app wraps the real backend in this and hands `SFTPSource` any host key policy:
/// the decision is taken here, by the `CertificatePin`, so there is exactly one rule in the app.
///   - nothing approved yet (`pin.trusted == nil`): every key is refused and remembered in the pin, so the setup screen can
///     show its fingerprint and ask the user (trust on first use needs the user's yes, never an automatic one);
///   - a fingerprint approved: only a key with that fingerprint is accepted; a different key is refused and remembered as a change.
/// The inner backend's own accept call is ignored on purpose.
public struct PinningSFTPBackend: SFTPBackend {
    public let inner: any SFTPBackend
    public let pin: CertificatePin

    public init(_ inner: any SFTPBackend, pin: CertificatePin) { self.inner = inner; self.pin = pin }

    public func connect(host: String, port: Int, credential: SFTPCredential,
                        acceptHostKey: @escaping @Sendable (String) async -> Bool) async throws {
        let pin = self.pin
        try await inner.connect(host: host, port: port, credential: credential) { fingerprint in
            pin.accepts(presented: fingerprint)
        }
    }

    public func listDirectory(_ path: String) async throws -> [SFTPDirectoryEntry] { try await inner.listDirectory(path) }
    public func attributes(of path: String) async throws -> SFTPAttributes { try await inner.attributes(of: path) }
    public func read(_ path: String, offset: UInt64, length: UInt32) async throws -> Data {
        try await inner.read(path, offset: offset, length: length)
    }
    public func disconnect() async { await inner.disconnect() }
}
