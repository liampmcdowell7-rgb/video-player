import Foundation
import VideoPlayerCore
import SourceSFTP
import Citadel
import Crypto
import NIOCore
import NIOFoundationCompat
import NIOSSH

// The Citadel (pure Swift, SwiftNIO SSH) implementation of `SFTPBackend`.
//
// What tests prove (Linux, see docs/SFTP_CITADEL.md): list, attributes, ranged read including past the end, password
// authentication and a refused wrong password, and the host-key flow, all against a real rclone SFTP server.
// What only a device can prove: that Citadel and its NIO dependencies compile and run on tvOS, throughput, key auth
// against a real OpenSSH server.

/// SFTP over SSH using Citadel. One instance holds one connection; `SFTPSource` reconnects through `connect` again.
public actor CitadelSFTPBackend: SFTPBackend {
    private var ssh: SSHClient?
    private var sftp: SFTPClient?
    /// The one file kept open between reads of the same file, so a 32 KiB read does not cost an open and a close.
    private var openFile: (path: String, file: SFTPFile)?
    private let connectTimeoutSeconds: Int64

    public init(connectTimeoutSeconds: Int64 = 20) {
        self.connectTimeoutSeconds = connectTimeoutSeconds
    }

    // MARK: SFTPBackend

    public func connect(
        host: String,
        port: Int,
        credential: SFTPCredential,
        acceptHostKey: @escaping @Sendable (String) async -> Bool
    ) async throws {
        await disconnect()
        let method = try Self.authenticationMethod(for: credential)
        let rejection = HostKeyRejection()
        let timeout = TimeAmount.seconds(connectTimeoutSeconds)
        do {
            // The closure is @escaping on purpose: NIO may keep the delegate (and so the closure)
            // alive after connect returns or throws, and withoutActuallyEscaping would trap then.
            let delegate = HostKeyDelegate(accept: acceptHostKey, rejection: rejection)
            let client: SSHClient = try await SSHClient.connect(
                host: host,
                port: port,
                authenticationMethod: method,
                hostKeyValidator: .custom(delegate),
                reconnect: .never,
                connectTimeout: timeout
            )
            do {
                self.sftp = try await client.openSFTP()
                self.ssh = client
            } catch {
                try? await client.close()
                throw error
            }
        } catch {
            if let fingerprint = rejection.fingerprint {
                throw SFTPBackendError.hostKeyRejected(fingerprint: fingerprint)
            }
            throw Self.map(error)
        }
    }

    public func listDirectory(_ path: String) async throws -> [SFTPDirectoryEntry] {
        let sftp = try client()
        do {
            let names = try await sftp.listDirectory(atPath: path)
            return names.flatMap(\.components).map {
                SFTPDirectoryEntry(name: $0.filename, attributes: Self.attributes(from: $0.attributes))
            }
        } catch {
            throw Self.map(error)
        }
    }

    public func attributes(of path: String) async throws -> SFTPAttributes {
        let sftp = try client()
        do {
            return Self.attributes(from: try await sftp.getAttributes(at: path))
        } catch {
            throw Self.map(error)
        }
    }

    public func read(_ path: String, offset: UInt64, length: UInt32) async throws -> Data {
        let sftp = try client()
        do {
            let file = try await file(for: path, on: sftp)
            let buffer = try await file.read(from: offset, length: length)
            return Data(buffer: buffer)
        } catch {
            await dropOpenFile()
            throw Self.map(error)
        }
    }

    public func disconnect() async {
        await dropOpenFile()
        if let sftp { try? await sftp.close() }
        if let ssh { try? await ssh.close() }
        sftp = nil
        ssh = nil
    }

    // MARK: Connection helpers

    private func client() throws -> SFTPClient {
        guard let sftp, sftp.isActive else { throw SFTPBackendError.connectionLost("The SFTP session is not open.") }
        return sftp
    }

    private func file(for path: String, on sftp: SFTPClient) async throws -> SFTPFile {
        if let openFile, openFile.path == path, openFile.file.isActive { return openFile.file }
        await dropOpenFile()
        let file = try await sftp.openFile(filePath: path, flags: .read)
        openFile = (path, file)
        return file
    }

    private func dropOpenFile() async {
        guard let openFile else { return }
        self.openFile = nil
        try? await openFile.file.close()
    }

    // MARK: Pure helpers (unit-tested without a server)

    /// SFTP entries carry Unix permission bits; the file type is in the top bits.
    static func attributes(from raw: SFTPFileAttributes) -> SFTPAttributes {
        let kind = (raw.permissions ?? 0) & 0o170000
        return SFTPAttributes(
            size: raw.size.map { Int64(clamping: $0) },
            modified: raw.accessModificationTime?.modificationTime,
            isDirectory: kind == 0o040000,
            isSymlink: kind == 0o120000
        )
    }

    static func authenticationMethod(for credential: SFTPCredential) throws -> SSHAuthenticationMethod {
        switch credential {
        case .password(let user, let password):
            return .passwordBased(username: user, password: password)
        case .privateKey(let user, let pem, let passphrase):
            let decryption = passphrase.map { Data($0.utf8) }
            let type: SSHKeyType
            do { type = try SSHKeyDetection.detectPrivateKeyType(from: pem) }
            catch { throw SFTPBackendError.other("The private key is not in a supported OpenSSH format.") }
            do {
                switch type {
                case .ed25519:
                    return .ed25519(username: user, privateKey: try Curve25519.Signing.PrivateKey(sshEd25519: pem, decryptionKey: decryption))
                case .rsa:
                    return .rsa(username: user, privateKey: try Insecure.RSA.PrivateKey(sshRsa: pem, decryptionKey: decryption))
                default:
                    throw SFTPBackendError.other("Private keys of type \(type) are not supported yet; use ed25519 or RSA.")
                }
            } catch let error as SFTPBackendError {
                throw error
            } catch {
                throw SFTPBackendError.other("The private key could not be read (wrong passphrase or damaged key).")
            }
        }
    }

    /// Maps what Citadel, NIO and the SFTP protocol throw to the backend's own errors.
    static func map(_ error: Error) -> SFTPBackendError {
        if let known = error as? SFTPBackendError { return known }
        if let sftpError = error as? SFTPError {
            switch sftpError {
            case .errorStatus(let status):
                switch status.errorCode {
                case .noSuchFile: return .noSuchFile
                case .permissionDenied: return .permissionDenied
                case .noConnection, .connectionLost: return .connectionLost("The SFTP connection was lost.")
                default: return .other("SFTP error \(status.errorCode): \(status.message)")
                }
            case .connectionClosed, .missingResponse, .noResponseTarget, .fileHandleInvalid:
                return .connectionLost("The SFTP connection was closed.")
            default:
                return .other("SFTP protocol error: \(sftpError)")
            }
        }
        // Found by the live tests: Citadel 0.12.1 can also throw the bare status message (not wrapped in SFTPError).
        // Its description names the protocol code, so the code name is matched on that text.
        let described = String(describing: error)
        if described.contains("SSH_FX_NO_SUCH_FILE") { return .noSuchFile }
        if described.contains("SSH_FX_PERMISSION_DENIED") { return .permissionDenied }
        if let clientError = error as? SSHClientError {
            switch clientError {
            case .allAuthenticationOptionsFailed, .unsupportedPasswordAuthentication, .unsupportedPrivateKeyAuthentication:
                return .authenticationFailed
            default:
                return .other("SSH client error: \(clientError)")
            }
        }
        if error is CancellationError { return .other("Cancelled.") }
        // NIOConnectionError (all connect attempts failed) lives in NIOPosix, which this target does not import.
        if error is ChannelError || error is IOError || String(describing: type(of: error)).contains("NIOConnectionError") {
            return .connectionLost("The connection failed: \(error)")
        }
        return .other(String(describing: error))
    }
}

// MARK: Host key

/// Remembers which fingerprint the policy refused, so `connect` can report it instead of a generic NIO error.
final class HostKeyRejection: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    var fingerprint: String? { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ fingerprint: String) { lock.lock(); value = fingerprint; lock.unlock() }
}

struct HostKeyRefused: Error {}

/// Called by NIOSSH during the key exchange, before any credential is sent. It hands the SHA-256 fingerprint to
/// `SFTPSource`'s policy and fails the handshake when the policy says no.
struct HostKeyDelegate: NIOSSHClientServerAuthenticationDelegate, Sendable {
    let accept: @Sendable (String) async -> Bool
    let rejection: HostKeyRejection

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        guard let fingerprint = HostKeyFingerprint.sha256(of: hostKey) else {
            validationCompletePromise.fail(HostKeyRefused())
            return
        }
        let accept = self.accept, rejection = self.rejection
        Task {
            if await accept(fingerprint) {
                validationCompletePromise.succeed(())
            } else {
                rejection.set(fingerprint)
                validationCompletePromise.fail(HostKeyRefused())
            }
        }
    }
}

/// `SHA256:` plus the unpadded base64 of the SHA-256 of the key blob, the same text `ssh-keygen -lf` prints.
public enum HostKeyFingerprint {
    public static func sha256(of key: NIOSSHPublicKey) -> String? {
        sha256(openSSHPublicKeyLine: String(openSSHPublicKey: key))
    }

    /// `line` is "ssh-ed25519 AAAA... comment", the format of a .pub file or `authorized_keys`.
    public static func sha256(openSSHPublicKeyLine line: String) -> String? {
        let fields = line.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 2, let blob = Data(base64Encoded: String(fields[1])), !blob.isEmpty else { return nil }
        let digest = Data(SHA256.hash(data: blob))
        var text = digest.base64EncodedString()
        while text.hasSuffix("=") { text.removeLast() }
        return "SHA256:" + text
    }
}
