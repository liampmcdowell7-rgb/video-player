import XCTest
import Foundation
import UserData
import VideoPlayerCore
@testable import AppLogic

/// R471 (65), PROVISIONAL (owner 25 Nov 2026 round 7, Part B item 2, finding P1): one live Plex client per saved source,
/// so its library listing (R305, kept 300 s) serves every start of playback, browse and scan instead of each start walking
/// the whole library twice (the server check, then the converter's reader). Other kinds are built each time, as before.
final class LiveSourceCacheR471Tests: XCTestCase {
    final class Built { let n: Int; init(_ n: Int) { self.n = n } }

    private func plex(_ id: String = "plex-1", host: String = "server-a") -> UDSourceDefinition {
        UDSourceDefinition(id: id, kind: SourceKind.plex.rawValue, name: "Server", host: host)
    }

    func testAPlexSourceIsBuiltOnceAndKept() throws {
        let cache = LiveSourceCache<Built>()
        var builds = 0
        let make = { () -> Built in builds += 1; return Built(builds) }
        let a = cache.source(for: plex(), secret: "s1", build: make)
        let b = cache.source(for: plex(), secret: "s1", build: make)
        XCTAssertTrue(a === b, "the same client for the server check and the reader")
        XCTAssertEqual(builds, 1)
    }

    func testAChangedDefinitionOrSecretBuildsANewOne() throws {
        let cache = LiveSourceCache<Built>()
        var builds = 0
        let make = { () -> Built in builds += 1; return Built(builds) }
        let a = cache.source(for: plex(), secret: "s1", build: make)
        let b = cache.source(for: plex(), secret: "s2", build: make)
        let c = cache.source(for: plex(host: "server-b"), secret: "s2", build: make)
        XCTAssertFalse(a === b, "a new token")
        XCTAssertFalse(b === c, "a new address")
        XCTAssertEqual(builds, 3)
        cache.forget(id: "plex-1")
        _ = cache.source(for: plex(host: "server-b"), secret: "s2", build: make)
        XCTAssertEqual(builds, 4, "a removed source is built again")
    }

    func testOtherKindsAreBuiltEachTime() throws {
        let cache = LiveSourceCache<Built>()
        var builds = 0
        let make = { () -> Built in builds += 1; return Built(builds) }
        let smb = UDSourceDefinition(id: "smb-1", kind: SourceKind.smb.rawValue, name: "Share", host: "nas")
        _ = cache.source(for: smb, secret: nil, build: make)
        _ = cache.source(for: smb, secret: nil, build: make)
        XCTAssertEqual(builds, 2)
        XCTAssertFalse(LiveSourceCache<Built>.keeps(smb))
        XCTAssertTrue(LiveSourceCache<Built>.keeps(plex()))
    }

    func testABuildThatThrowsKeepsNothing() throws {
        let cache = LiveSourceCache<Built>()
        struct Refused: Error {}
        XCTAssertThrowsError(try cache.source(for: plex(), secret: "s1") { throw Refused() })
        var builds = 0
        _ = cache.source(for: plex(), secret: "s1") { builds += 1; return Built(builds) }
        XCTAssertEqual(builds, 1)
    }
}
