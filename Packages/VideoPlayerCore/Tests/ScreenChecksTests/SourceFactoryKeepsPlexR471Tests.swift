import XCTest
@testable import ScreenChecks

/// R471 (65), PROVISIONAL: every live source the app builds (scan, browse, the server check and the reader of a playback
/// start) comes through `SourceFactory.source(for:)`, which now keeps a Plex client (`LiveSourceCache`). Structure only, from
/// the source: nothing is compiled or run on tvOS.
extension ScreenChecksTests {
    func testTheSourceFactoryKeepsItsPlexClients() throws {
        guard let factory = try appSource("App/Support/SourceFactory.swift") else { return }
        XCTAssertTrue(factory.contains("private let live = LiveSourceCache<any MediaSource>()"))
        XCTAssertTrue(factory.contains("return try live.source(for: definition, secret: secret) {"))
        XCTAssertFalse(factory.contains("return try builder.build(definition, secret: secret, pin: pin)"), "no client built outside the cache")
        // A scan still reads a fresh listing.
        guard let services = try appSource("App/Support/AppServices.swift") else { return }
        XCTAssertTrue(services.contains("sourceFactory.forgetLiveSource(id: definition.id)\n            guard let source = makeSource(definition) else { continue }"))
    }
}
