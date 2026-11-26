import XCTest
@testable import ScreenChecks

/// R471 (69), PROVISIONAL (owner 25 Nov 2026 round 8, Part B item 3, finding C): the app's builder makes its own Plex
/// client for each build, and the factory's `LiveSourceCache` is the one place a client is kept (one per saved source).
/// With the process-wide `PlexClient.shared` store, a forgotten client came back on the next build with its old listing:
/// a scan never read the server afresh, and a removed source's client lived until the app quit. Structure only, from the
/// source: nothing is compiled or run on tvOS.
extension ScreenChecksTests {
    func testTheBuilderMakesItsOwnPlexClientSoForgettingItWorks() throws {
        guard let builder = try appSource("App/Support/SourceBuilder.swift") else { return }
        XCTAssertFalse(builder.contains("PlexClient.shared("), "a forgotten client must not come back from a process-wide store")
        XCTAssertTrue(builder.contains("return PlexClient(baseURL: url, token: password, identity: PlexClientIdentity(clientIdentifier: deviceID))"))
    }
}
