import Foundation
import VideoPlayerCore

/// One media server of the owner's Plex account (docs/PLEX_SOURCE.md section 2; OPEN_QUESTIONS R303).
public struct PlexServer: Equatable, Sendable {
    public var name: String
    /// The server's machine identifier (the resource's `clientIdentifier`; `/identity` answers the same value).
    public var machineIdentifier: String
    /// The token for this server (the resource's `accessToken`). Kept as the source secret; never shown or logged.
    public var accessToken: String?
    public var connections: [PlexConnection]

    public init(name: String, machineIdentifier: String, accessToken: String?, connections: [PlexConnection]) {
        self.name = name; self.machineIdentifier = machineIdentifier; self.accessToken = accessToken; self.connections = connections
    }

    /// True when the server has a local connection that is not a relay ("Local" in the list, "Remote" otherwise).
    public var isLocal: Bool { connections.contains { $0.local && !$0.relay } }
    /// True when the only way to reach the server is the Plex relay.
    public var onlyRelay: Bool { !connections.isEmpty && connections.allSatisfy(\.relay) }
}

/// The account's server list from plex.tv.
///
/// Re-read 20 Nov 2026 (developer.plex.tv, "Talking to PMS"): `GET https://clients.plex.tv/api/v2/resources?includeHttps=1&
/// includeRelay=1&includeIPv6=1` with the account token; each resource carries "the `accessToken` used in communication with
/// this PMS" and its connections (`protocol`, `address`, `port`, `uri`, `local`, `relay`) (read). Telling servers from
/// other devices by `provides` is UNVERIFIED (`PlexResource.isServer`).
public struct PlexServerList: Sendable {
    private let http: PlexHTTP
    private let clients: URL

    public init(identity: PlexClientIdentity, transport: HTTPTransport, clients: URL = URL(string: "https://clients.plex.tv")!) {
        self.http = PlexHTTP(identity: identity, transport: transport)
        self.clients = clients
    }

    public func servers(accountToken: String) async throws -> [PlexServer] {
        var parts = URLComponents(url: clients.appendingPathComponent("api/v2/resources"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "includeHttps", value: "1"), URLQueryItem(name: "includeRelay", value: "1"),
                            URLQueryItem(name: "includeIPv6", value: "1")]
        let response = try await http.send(http.request("GET", parts.url!, token: accountToken))
        let resources = try PlexHTTP.decode([PlexResource].self, from: response)
        return resources.filter(\.isServer).compactMap { resource in
            guard let id = resource.clientIdentifier, !id.isEmpty else { return nil }
            return PlexServer(name: resource.name.isEmpty ? id : resource.name, machineIdentifier: id,
                              accessToken: resource.accessToken, connections: resource.connections)
        }
    }
}

/// The order in which a server's connections are tried (R268, R303).
///
/// Read 20 Nov 2026 (developer.plex.tv): "Connections labeled as `local` should be preferred over those that are not" and
/// "relay should only be used as a last resort". Plex Support, relay (read 20 Nov 2026): relayed streams are "limited to
/// 2 Mbps maximum". So: local HTTPS, then local HTTP, then remote HTTPS, then (only when the owner turned it on) the relay.
/// Remote plain HTTP is never tried: no ATS exception is added for it (docs/PLEX_SOURCE.md section 2).
public enum PlexConnectionOrder {
    public static func ordered(_ connections: [PlexConnection], allowRelay: Bool) -> [PlexConnection] {
        func rank(_ c: PlexConnection) -> Int? {
            if c.relay { return allowRelay ? 3 : nil }
            switch (c.local, c.scheme) {
            case (true, "https"): return 0
            case (true, "http"): return 1
            case (false, "https"): return 2
            default: return nil
            }
        }
        return connections.enumerated()
            .compactMap { index, c in rank(c).map { (rank: $0, index: index, c: c) } }
            .sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }
            .map(\.c)
    }
}

/// Finds the first connection of a server that answers as that server.
public struct PlexConnectionProbe: Sendable {
    private let http: PlexHTTP

    public init(identity: PlexClientIdentity, transport: HTTPTransport) {
        self.http = PlexHTTP(identity: identity, transport: transport)
    }

    /// Tries the connections in `PlexConnectionOrder` with `GET <uri>/identity` (no token; that `/identity` needs none is
    /// UNVERIFIED, from a summary of the PMS reference) and returns the first whose machine identifier matches.
    /// Throws `PlexError.onlyRelay` when the relay is the only way left and it is off, `PlexError.serverUnreachable` otherwise.
    public func firstReachable(_ server: PlexServer, allowRelay: Bool) async throws -> PlexConnection {
        for connection in PlexConnectionOrder.ordered(server.connections, allowRelay: allowRelay) {
            try Task.checkCancellation()
            guard let base = URL(string: connection.uri) else { continue }
            do {
                let response = try await http.send(http.request("GET", base.appendingPathComponent("identity"), token: nil))
                let envelope = try PlexHTTP.decode(PlexEnvelope.self, from: response)
                if envelope.container.machineIdentifier == server.machineIdentifier { return connection }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        if !allowRelay && server.connections.contains(where: \.relay) { throw PlexError.onlyRelay }
        throw PlexError.serverUnreachable
    }
}
