import XCTest
@testable import UserData

// Backward compatibility of the source definition after it gained `options` and `trustedFingerprint` (docs/SOURCES_WIRING.md).
final class SourceDefinitionTrustTests: XCTestCase {
    private func stamp(_ t: Double, _ d: String = "dev") -> UDStamp { UDStamp(time: t, device: d) }

    /// FIXTURE: a source record exactly as the version before this change wrote it (no options, no trustedFingerprint).
    private func oldRecord(id: String = "s1", at t: Double = 100) -> UDRecord {
        var r = UDRecord(type: UDSchema.source, id: id)
        let s = stamp(t)
        r.set("kind", .string("webdav"), at: s)
        r.set("name", .string("Old NAS"), at: s)
        r.set("host", .string("nas.local"), at: s)
        r.set("port", .int(8443), at: s)
        r.set("path", .string("https://nas.local:8443/dav"), at: s)
        r.set("username", .string("me"), at: s)
        r.set("auth", .string("password"), at: s)
        r.set("addedAt", .double(50), at: s)
        return r
    }

    func testAnOldRecordWithoutTheNewFieldsDecodesWithEmptyDefaults() throws {
        let value = try XCTUnwrap(UDSource.value(of: oldRecord()))
        XCTAssertEqual(value.trustedFingerprint, "")
        XCTAssertEqual(value.options, "")
        XCTAssertEqual(value.host, "nas.local")
        XCTAssertEqual(value.port, 8443)
    }

    func testAnOldEssentialsCopyOnDiskStillRestores() throws {
        // FIXTURE: the essentials JSON as an older build stored it, built by encoding the old record with the real wrapper format.
        struct Body: Codable { var format: String; var version: Int; var records: [UDRecord] }
        let data = try JSONEncoder().encode(Body(format: "video-player-essentials", version: 1, records: [oldRecord()]))
        let kv = InMemoryKeyValueStore()
        kv.set(data, forKey: UDEssentialsStore.storageKey)
        let ledger = UserDataLedger(deviceID: "new")
        XCTAssertEqual(UDEssentialsStore(store: kv).restore(into: ledger), 1)
        let restored = try XCTUnwrap(ledger.sourceDefinitions().first)
        XCTAssertEqual(restored.name, "Old NAS")
        XCTAssertEqual(restored.trustedFingerprint, "")
    }

    func testTheFingerprintAndOptionsRoundTripThroughLedgerAndEssentials() throws {
        let ledger = UserDataLedger(deviceID: "a")
        let kv = InMemoryKeyValueStore()
        let essentials = UDEssentialsStore(store: kv)
        let definition = UDSourceDefinition(id: "s2", kind: "ftp", name: "FTPS box", host: "box.local", port: 990, path: "/video",
                                            username: "u", auth: "password", addedAt: Date(timeIntervalSince1970: 10),
                                            options: "security=implicit", trustedFingerprint: "AB12CD34")
        ledger.upsertSource(definition)
        try essentials.save(from: ledger)
        let fresh = UserDataLedger(deviceID: "b")
        UDEssentialsStore(store: kv).restore(into: fresh)
        XCTAssertEqual(fresh.sourceDefinitions(), [definition])
    }

    func testANewerFingerprintWinsAndAnOlderRecordCannotBringBackAnOldOne() throws {
        let ledger = UserDataLedger(deviceID: "a")
        var trusted = UDSourceDefinition(id: "s1", kind: "webdav", name: "NAS", host: "nas.local", auth: "none", trustedFingerprint: "AA")
        ledger.upsertSource(trusted, at: Date(timeIntervalSince1970: 100))
        trusted.trustedFingerprint = "BB"
        ledger.upsertSource(trusted, at: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(ledger.sourceDefinitions().first?.trustedFingerprint, "BB")
        // A stale copy of the first approval arriving late does not undo the newer one.
        var stale = UDSource.patch(UDSourceDefinition(id: "s1", kind: "webdav", name: "NAS", host: "nas.local", auth: "none", trustedFingerprint: "AA"), at: stamp(100, "other"))
        stale.deleted = nil
        _ = ledger.apply(stale)
        XCTAssertEqual(ledger.sourceDefinitions().first?.trustedFingerprint, "BB")
    }

    func testChangingTheHostInAnOlderFormatEditDropsTheApprovalWithIt() throws {
        // The fingerprint is in the same atomic group as the host: a newer record from a build that does not know the field wins as a whole.
        let ledger = UserDataLedger(deviceID: "a")
        ledger.upsertSource(UDSourceDefinition(id: "s1", kind: "webdav", name: "NAS", host: "nas.local", auth: "none", trustedFingerprint: "AA"), at: Date(timeIntervalSince1970: 100))
        var edited = oldRecord(id: "s1", at: 300)
        edited.set("host", .string("other.local"), at: stamp(300))
        _ = ledger.apply(edited)
        let now = try XCTUnwrap(ledger.sourceDefinitions().first)
        XCTAssertEqual(now.host, "other.local")
        XCTAssertEqual(now.trustedFingerprint, "", "approval for the old host must not carry over to the new host")
    }
}
