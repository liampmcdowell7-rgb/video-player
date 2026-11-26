import XCTest
import Foundation
import UserData
import VideoPlayerCore
@testable import AppLogic

/// R471 (68), PROVISIONAL (owner 25 Nov 2026 round 8, Part B item 2): a kept Plex client is let go when its source is
/// removed or edited, instead of living until the app quits.
final class ForgetLiveSourceR471Tests: XCTestCase {
    final class Client {}

    final class Saver: SourceDefinitionSaving, @unchecked Sendable {
        var saved: [UDSourceDefinition] = []
        var refuse = false
        struct Refused: Error {}
        func saveDefinition(_ definition: UDSourceDefinition) async throws {
            if refuse { throw Refused() }
            saved.append(definition)
        }
    }

    private func plex(host: String = "server-a") -> UDSourceDefinition {
        UDSourceDefinition(id: "plex-1", kind: SourceKind.plex.rawValue, name: "Server", host: host)
    }

    func testAForgottenClientIsReleased() {
        let cache = LiveSourceCache<Client>()
        weak var kept: Client?
        do {
            let made = cache.source(for: plex(), secret: "s") { Client() }
            kept = made
        }
        XCTAssertNotNil(kept, "kept while the source is saved")
        XCTAssertTrue(cache.isHolding(id: "plex-1"))
        cache.forget(id: "plex-1")
        XCTAssertNil(kept, "a removed source's client is let go, not kept until the app quits")
        XCTAssertFalse(cache.isHolding(id: "plex-1"))
    }

    func testSavingAnEditedDefinitionDropsTheKeptClient() async throws {
        let cache = LiveSourceCache<Client>()
        let inner = Saver()
        let saver = ForgettingDefinitionSaver(inner: inner, forget: { [cache] id in cache.forget(id: id) })
        _ = cache.source(for: plex(), secret: "s") { Client() }
        try await saver.saveDefinition(plex(host: "server-b"))
        XCTAssertEqual(inner.saved.map(\.host), ["server-b"], "the save is passed on")
        XCTAssertFalse(cache.isHolding(id: "plex-1"), "the client built from the old definition is let go")
    }

    func testAFailedSaveKeepsTheClient() async {
        let cache = LiveSourceCache<Client>()
        let inner = Saver()
        inner.refuse = true
        let saver = ForgettingDefinitionSaver(inner: inner, forget: { [cache] id in cache.forget(id: id) })
        _ = cache.source(for: plex(), secret: "s") { Client() }
        do { try await saver.saveDefinition(plex(host: "server-b")); XCTFail("the save was refused") } catch {}
        XCTAssertTrue(cache.isHolding(id: "plex-1"), "nothing changed, so the client stays")
    }
}
