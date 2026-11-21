import XCTest
import VideoPlayerCore
@testable import SourcePlex

/// Stage 3 (docs/PLEX_SOURCE.md section 2; R303): the account's server list and the order connections are tried in.
/// Against the fake plex.tv and the fake media server; no network.
final class PlexServerTests: XCTestCase {
    let identity = PlexClientIdentity(clientIdentifier: "install-1234", version: "0.1.0")

    func testTheServerListHasOnlyServersWithTheirTokens() async throws {
        let fake = try FakePlexServer()
        let servers = try await PlexServerList(identity: identity, transport: fake).servers(accountToken: "account-token-placeholder")
        XCTAssertEqual(servers.map(\.name), ["Home PC", "Friend's Server"], "the player is not a server")
        XCTAssertEqual(servers.first?.machineIdentifier, "machine-0001")
        XCTAssertEqual(servers.first?.accessToken, "server-token-placeholder")
        XCTAssertTrue(servers[0].isLocal)
        XCTAssertFalse(servers[1].isLocal)
        let request = try XCTUnwrap(fake.requests.first)
        XCTAssertEqual(request.url.host, "clients.plex.tv")
        XCTAssertEqual(request.url.path, "/api/v2/resources")
        for item in ["includeHttps=1", "includeRelay=1", "includeIPv6=1"] { XCTAssertTrue(request.url.query?.contains(item) ?? false, item) }
        XCTAssertEqual(request.headers["X-Plex-Token"], "account-token-placeholder")
        XCTAssertFalse(request.url.absoluteString.contains("account-token-placeholder"), "the token is a header, never in the address")
    }

    func testAWrongAccountTokenIsUnauthorized() async throws {
        let fake = try FakePlexServer()
        do {
            _ = try await PlexServerList(identity: identity, transport: fake).servers(accountToken: "wrong")
            XCTFail("expected unauthorized")
        } catch SourceError.unauthorized {}
    }

    private func c(_ uri: String, local: Bool, relay: Bool = false) -> PlexConnection { PlexConnection(uri: uri, local: local, relay: relay) }

    func testLocalHTTPSThenLocalHTTPThenRemoteHTTPSAndTheRelayOnlyWhenAllowed() {
        let all = [c("https://relay.example:8443", local: false, relay: true), c("http://203.0.113.7:32400", local: false),
                   c("https://remote.example:32400", local: false), c("http://192.168.1.20:32400", local: true),
                   c("https://local.example:32400", local: true)]
        XCTAssertEqual(PlexConnectionOrder.ordered(all, allowRelay: false).map(\.uri),
                       ["https://local.example:32400", "http://192.168.1.20:32400", "https://remote.example:32400"],
                       "remote plain HTTP is never tried; the relay is off")
        XCTAssertEqual(PlexConnectionOrder.ordered(all, allowRelay: true).last?.uri, "https://relay.example:8443", "the relay is the last resort")
    }

    func testTheFirstLocalConnectionThatAnswersAsThisServerIsUsed() async throws {
        let fake = try FakePlexServer()
        let server = try await PlexServerList(identity: identity, transport: fake).servers(accountToken: "account-token-placeholder")[0]
        let found = try await PlexConnectionProbe(identity: identity, transport: fake).firstReachable(server, allowRelay: false)
        XCTAssertEqual(found.uri, "https://192-168-1-20.machine0001.plex.direct:32400")
        let probes = fake.requests.filter { $0.url.path == "/identity" }
        XCTAssertEqual(probes.count, 1)
        XCTAssertNil(probes[0].headers["X-Plex-Token"], "the probe sends no token")
    }

    func testWhenLocalHTTPSFailsLocalHTTPIsNext() async throws {
        let fake = try FakePlexServer()
        fake.reachableHosts = ["192.168.1.20"]
        let server = try await PlexServerList(identity: identity, transport: fake).servers(accountToken: "account-token-placeholder")[0]
        let found = try await PlexConnectionProbe(identity: identity, transport: fake).firstReachable(server, allowRelay: false)
        XCTAssertEqual(found.uri, "http://192.168.1.20:32400")
    }

    func testAnotherMachineAnsweringIsNotThisServer() async throws {
        let fake = try FakePlexServer()
        let impostor = PlexServer(name: "Other", machineIdentifier: "machine-9999", accessToken: "t",
                                  connections: [c("http://192.168.1.20:32400", local: true)])
        do {
            _ = try await PlexConnectionProbe(identity: identity, transport: fake).firstReachable(impostor, allowRelay: false)
            XCTFail("expected unreachable")
        } catch PlexError.serverUnreachable {}
    }

    func testAServerOffIsUnreachableAndARelayOnlyServerSaysSo() async throws {
        let fake = try FakePlexServer()
        fake.reachableHosts = []
        let server = try await PlexServerList(identity: identity, transport: fake).servers(accountToken: "account-token-placeholder")
        do {
            _ = try await PlexConnectionProbe(identity: identity, transport: fake).firstReachable(server[0], allowRelay: false)
            XCTFail("expected only relay")
        } catch PlexError.onlyRelay {}
        do {
            _ = try await PlexConnectionProbe(identity: identity, transport: fake).firstReachable(server[1], allowRelay: false)
            XCTFail("expected unreachable")
        } catch PlexError.serverUnreachable {}
    }

    /// R302, R303: the source secret is the server's own token only; a server without one cannot be added, and the account
    /// token is never offered in its place.
    func testTheSourceSecretIsTheServersOwnTokenAndNeverTheAccountToken() throws {
        let own = PlexServer(name: "Home PC", machineIdentifier: "machine-0001", accessToken: "server-token-placeholder", connections: [])
        XCTAssertEqual(try own.sourceSecret(), "server-token-placeholder")
        for missing in [nil, ""] as [String?] {
            let bare = PlexServer(name: "Home PC", machineIdentifier: "machine-0001", accessToken: missing, connections: [])
            XCTAssertThrowsError(try bare.sourceSecret()) { XCTAssertEqual($0 as? PlexError, .noServerToken) }
        }
    }
}
