import Foundation
import VideoPlayerCore
import UserData
import AppLogic
import SourceWebDAV
import SourceJellyfin
import SourceEmby
import SourceUPnP
import SourceLinks
import SourceSMB
import SourceNFS
import SourceSFTP
import SourceSFTPCitadel
import SourceFTP
import SourceOneDrive

/// Turns one saved definition (plus its secret and the approved fingerprint) into the object that talks to the server.
/// The setup flow and the saved-source code both go through here, so a source behaves the same while it is being added and afterwards.
/// Nothing in here logs a secret.
struct SourceBuilder {
    let deviceID: String
    /// Where the OneDrive sign-in tokens are kept (nil when no Microsoft app registration exists, which keeps OneDrive blocked).
    let tokenStore: (@Sendable (String) -> any OneDriveTokenStore)?

    /// What kind of fingerprint this definition is held to, or nil when nothing is pinned (plain connections, address-only kinds).
    static func trustKind(for definition: UDSourceDefinition) -> TrustKind? {
        guard let kind = definition.sourceKind else { return nil }
        let options = definition.optionValues
        switch kind {
        case .sftp: return .sshHostKey
        case .webdav, .jellyfin, .emby:
            return URL(string: definition.path)?.scheme?.lowercased() == "https" ? .tlsCertificate : nil
        case .ftp:
            let security = options["security"] ?? "none"
            return security == "explicit" || security == "implicit" ? .tlsCertificate : nil
        default: return nil
        }
    }

    func build(_ definition: UDSourceDefinition, secret: String?, pin: CertificatePin?) throws -> any MediaSource {
        guard let kind = definition.sourceKind else {
            throw ConnectorError(kindTitle: definition.kind, reason: .notIncluded("This version does not know this source type."))
        }
        let title = SourceCatalog.info(for: kind).title
        let password = secret ?? ""
        let transport = PinnedTransport(pin: pin)

        func guarded(_ source: any MediaSource) -> any MediaSource {
            guard let pin else { return source }
            return TrustGuardedSource(source, pin: pin)
        }
        func requireURL() throws -> URL {
            guard let url = URL(string: definition.path.trimmingCharacters(in: .whitespacesAndNewlines)), url.host != nil else {
                throw ConnectorError(kindTitle: title, reason: .incomplete("its address"))
            }
            return url
        }

        switch kind {
        case .webdav:
            let url = try requireURL()
            let credentials = definition.username.isEmpty ? nil : WebDAVCredentials(username: definition.username, password: password)
            let client = WebDAVClient(baseURL: url, credentials: credentials, transport: transport,
                                      allowBasicOverHTTP: url.scheme?.lowercased() == "http")
            return guarded(client)

        case .jellyfin:
            let client = JellyfinClient(baseURL: try requireURL(),
                                        credentials: .password(username: definition.username, password: password),
                                        transport: transport, deviceID: deviceID)
            return guarded(client)

        case .emby:
            let client = EmbyClient(baseURL: try requireURL(),
                                    credentials: .password(username: definition.username, password: password),
                                    transport: transport, deviceID: deviceID)
            return guarded(client)

        case .upnp:
            return UPnPClient(deviceURL: try requireURL(), transport: URLSessionTransport())

        case .directLink:
            var store = LinkStore()
            do { _ = try store.add(definition.path, title: definition.name) }
            catch { throw ConnectorError(kindTitle: title, reason: .incomplete("a link that starts with http:// or https://")) }
            return LinksSource(store: store, transport: URLSessionTransport())

        case .smb:
            guard !definition.host.isEmpty else { throw ConnectorError(kindTitle: title, reason: .incomplete("the server name")) }
            let configuration = SMBConfiguration(host: definition.host, port: definition.port,
                                                 username: definition.username.isEmpty ? nil : definition.username,
                                                 password: definition.username.isEmpty ? nil : password,
                                                 defaultShare: definition.path.isEmpty ? nil : definition.path)
            guard let client = SMBClients.real(configuration) else {
                throw ConnectorError(kindTitle: title, reason: .notIncluded("The SMB library is not part of this build."))
            }
            // The share is the root the user sees; the client lists share names when none is given.
            return definition.path.isEmpty ? client : SubfolderSource(client, root: "/" + definition.path)

        case .nfs:
            guard !definition.host.isEmpty else { throw ConnectorError(kindTitle: title, reason: .incomplete("the server name")) }
            guard let backend = NFSBackends.libnfs() else {
                throw ConnectorError(kindTitle: title, reason: .notIncluded("The NFS library is not part of this build."))
            }
            let export = definition.path.isEmpty ? "/" : definition.path
            return NFSSource(configuration: NFSConfiguration(host: definition.host, exportPath: export, port: definition.port), backend: backend)

        case .sftp:
            guard !definition.host.isEmpty else { throw ConnectorError(kindTitle: title, reason: .incomplete("the server name")) }
            guard !definition.username.isEmpty else { throw ConnectorError(kindTitle: title, reason: .incomplete("the user name")) }
            let effectivePin = pin ?? CertificatePin(kind: .sshHostKey, host: definition.host, trusted: nil)
            let backend = PinningSFTPBackend(CitadelSFTPBackend(), pin: effectivePin)
            let source = SFTPSource(host: definition.host, port: definition.port ?? 22,
                                    credential: .password(username: definition.username, password: password),
                                    hostKeyPolicy: .pinned(definition.trustedFingerprint),
                                    rootPath: definition.path.isEmpty ? "/" : definition.path, backend: backend)
            return TrustGuardedSource(source, pin: effectivePin)

        case .ftp:
            guard !definition.host.isEmpty else { throw ConnectorError(kindTitle: title, reason: .incomplete("the server name")) }
            let security: FTPSecurity
            switch definition.optionValues["security"] ?? "none" {
            case "explicit": security = .explicitTLS
            case "implicit": security = .implicitTLS
            default: security = .none
            }
            let credentials = definition.username.isEmpty ? FTPCredentials.anonymous : FTPCredentials(username: definition.username, password: password)
            let port = definition.port ?? (security == .implicitTLS ? 990 : 21)
            let client = FTPClient(host: definition.host, port: port, credentials: credentials, security: security,
                                   connector: NetworkFTPConnector(pin: security == .none ? nil : pin))
            let rooted: any MediaSource = (definition.path.isEmpty || definition.path == "/") ? client : SubfolderSource(client, root: definition.path)
            return security == .none ? rooted : guarded(rooted)

        case .oneDrive:
            guard let tokenStore, let clientID = SourceConfiguration.oneDriveClientID, !clientID.isEmpty else {
                throw ConnectorError(kindTitle: title, reason: .notIncluded("This type is blocked until an app registration exists."))
            }
            return OneDriveSource(configuration: OneDriveConfiguration(clientID: clientID),
                                  tokenStore: tokenStore(definition.id), transport: URLSessionTransport())

        case .plex, .dropbox, .googleDrive:
            throw ConnectorError(kindTitle: title, reason: .notIncluded(SourceCatalog.info(for: kind).unavailableNote ?? "This type is not available."))
        }
    }
}

/// Keeps the sign-in tokens of a source in the same protected store as passwords (so they follow the same sync rules).
struct SecretsTokenStore: OneDriveTokenStore {
    let secrets: MirroredSecrets
    let sourceID: String

    func load() async -> OneDriveTokens? {
        guard let text = secrets.secret(for: sourceID), let data = text.data(using: .utf8) else { return nil }
        return try? Self.decoder.decode(OneDriveTokens.self, from: data)
    }
    func save(_ tokens: OneDriveTokens) async {
        guard let data = try? Self.encoder.encode(tokens), let text = String(data: data, encoding: .utf8) else { return }
        _ = try? await secrets.set(text, for: sourceID)
    }
    func clear() async { _ = try? await secrets.remove(sourceID: sourceID) }

    static var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
    static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
