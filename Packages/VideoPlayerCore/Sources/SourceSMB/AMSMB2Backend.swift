#if canImport(AMSMB2)
import AMSMB2
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // URLCredential lives here on Linux
#endif

/// The real SMB backend, built on AMSMB2 (libsmb2). Only compiled when the AMSMB2 package is a
/// dependency of this target; see docs/SOURCES.md for the pinned version and the local patch.
public actor AMSMB2Backend: SMBBackend {
    private let configuration: SMBConfiguration
    private var manager: SMB2Manager?
    private var currentShare: String?

    public init(configuration: SMBConfiguration) {
        self.configuration = configuration
    }

    public func connect(share: String?) async throws {
        manager = nil
        currentShare = nil
        let manager = try makeManager()
        self.manager = manager
        do {
            if let share {
                try await manager.connectShare(name: share, encrypted: configuration.encrypted)
                currentShare = share
            } else {
                _ = try await manager.listShares()
            }
        } catch {
            self.manager = nil
            throw Self.map(error, connecting: true)
        }
    }

    public func listShares() async throws -> [String] {
        let manager = try requireManager()
        do {
            return try await manager.listShares().map { $0.name }
        } catch { throw Self.map(error, connecting: false) }
    }

    public func listDirectory(share: String, path: String) async throws -> [SMBItem] {
        let manager = try await onShare(share)
        do {
            return try await manager.contentsOfDirectory(atPath: path).compactMap(Self.item)
        } catch { throw Self.map(error, connecting: false) }
    }

    public func stat(share: String, path: String) async throws -> SMBItem {
        let manager = try await onShare(share)
        do {
            let attributes = try await manager.attributesOfItem(atPath: path)
            guard var item = Self.item(attributes) else { throw SMBBackendError.other("No attributes returned.") }
            if item.name.isEmpty { item.name = path.split(separator: "/").last.map(String.init) ?? path }
            return item
        } catch { throw Self.map(error, connecting: false) }
    }

    public func read(share: String, path: String, offset: Int64, length: Int64) async throws -> Data {
        let manager = try await onShare(share)
        guard length > 0 else { return Data() }
        let upper = offset.addingReportingOverflow(length)
        let end = upper.overflow ? Int64.max : upper.partialValue
        do {
            return try await manager.contents(atPath: path, range: offset..<end)
        } catch { throw Self.map(error, connecting: false) }
    }

    public func disconnect() async {
        let manager = self.manager
        self.manager = nil
        currentShare = nil
        try? await manager?.disconnectShare(gracefully: false)
    }

    // MARK: Helpers

    private func makeManager() throws -> SMB2Manager {
        var text = "smb://" + configuration.host
        if let port = configuration.port { text += ":\(port)" }
        guard let url = URL(string: text) else { throw SMBBackendError.other("The server address is not valid.") }
        var credential: URLCredential?
        if let user = configuration.username {
            credential = URLCredential(user: user, password: configuration.password ?? "", persistence: .forSession)
        }
        guard let manager = SMB2Manager(url: url, domain: configuration.domain, credential: credential) else {
            throw SMBBackendError.other("The server address is not valid.")
        }
        manager.timeout = configuration.timeout
        return manager
    }

    private func requireManager() throws -> SMB2Manager {
        guard let manager else { throw SMBBackendError.connectionLost("Not connected.") }
        return manager
    }

    /// Makes sure the connection is on `share`, switching when needed.
    private func onShare(_ share: String) async throws -> SMB2Manager {
        let manager = try requireManager()
        if currentShare != share {
            do {
                try await manager.connectShare(name: share, encrypted: configuration.encrypted)
                currentShare = share
            } catch {
                currentShare = nil
                throw Self.map(error, connecting: false)
            }
        }
        return manager
    }

    private static func item(_ attributes: [URLResourceKey: any Sendable]) -> SMBItem? {
        let name = (attributes[.nameKey] as? String) ?? ""
        let isDirectory = (attributes[.isDirectoryKey] as? Bool) ?? false
        let size = (attributes[.fileSizeKey] as? Int64) ?? (attributes[.fileSizeKey] as? Int).map(Int64.init)
        let modified = attributes[.contentModificationDateKey] as? Date
        return SMBItem(name: name, isDirectory: isDirectory, size: size, modified: modified)
    }

    static func map(_ error: Error, connecting: Bool) -> SMBBackendError {
        if let known = error as? SMBBackendError { return known }
        let code = (error as? POSIXError)?.code ?? POSIXErrorCode(rawValue: Int32((error as NSError).code))
        switch code {
        case .some(.ENOENT), .some(.ENOTDIR): return .notFound
        case .some(.EACCES), .some(.EPERM): return connecting ? .authenticationFailed : .accessDenied
        case .some(.ECONNREFUSED):
            // libsmb2 reports a failed login (STATUS_LOGON_FAILURE) as ECONNREFUSED. A closed port also is.
            let text = String(describing: error).lowercased()
            if text.contains("logon_failure") || text.contains("0xc000006d") || text.contains("logon failure") {
                return .authenticationFailed
            }
            return .other(String(describing: error))
        case .some(.ENOTCONN), .some(.ECONNRESET), .some(.ECONNABORTED), .some(.EPIPE), .some(.ETIMEDOUT),
             .some(.ENETDOWN), .some(.ENETUNREACH), .some(.EHOSTUNREACH), .some(.EIO):
            return .connectionLost(String(describing: error))
        default: return .other(String(describing: error))
        }
    }
}

public extension SMBClient {
    /// A client that talks to a real server through AMSMB2.
    static func amsmb2(_ configuration: SMBConfiguration) -> SMBClient {
        SMBClient(configuration: configuration, backend: AMSMB2Backend(configuration: configuration))
    }
}
#endif
