import XCTest
@testable import UserData

// Ledger persistence, the essentials copy in UserDefaults (with the 200 KB budget), export/import, credentials.

final class LedgerPersistenceTests: XCTestCase {
    func testALedgerSurvivesAFileRoundTripIncludingDirtyFlagsAndTheToken() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("ledger.json")
        let a = makeLedger()
        LedgerRecorder(ledger: a).recordProgress(key: "m", UDWatchValue(position: 5, duration: 100, lastPlayed: at(9)), at: at(9))
        a.changeToken = UDChangeToken(data: Data("12".utf8))
        XCTAssertTrue(a.needsSave)
        try a.save(to: url)
        XCTAssertFalse(a.needsSave)
        let b = makeLedger()
        XCTAssertEqual(b.load(from: url), .loaded(records: 1))
        XCTAssertEqual(b.allRecords(), a.allRecords())
        XCTAssertEqual(b.dirtyCount, 1, "an edit that was never uploaded is still queued after a restart")
        XCTAssertEqual(b.changeToken, a.changeToken)
    }

    func testMissingEmptyDamagedAndForeignFilesLeaveTheLedgerEmptyAndSayWhy() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("ledger.json")
        XCTAssertEqual(makeLedger().load(from: url), .missing)
        try Data().write(to: url)
        XCTAssertEqual(makeLedger().load(from: url), .corrupt("empty or unreadable file"))
        try Data("{ not json".utf8).write(to: url)
        XCTAssertEqual(makeLedger().load(from: url), .corrupt("not valid ledger JSON"))
        try Data(#"{"format":"something-else","version":1,"entries":[]}"#.utf8).write(to: url)
        XCTAssertEqual(makeLedger().load(from: url), .corrupt("wrong format"))
        try Data(#"{"format":"video-player-ledger","version":9,"entries":[]}"#.utf8).write(to: url)
        XCTAssertEqual(makeLedger().load(from: url), .corrupt("unsupported version 9"))
        let l = makeLedger()
        _ = l.load(from: url)
        XCTAssertTrue(l.isEmpty)
    }

    func testApplyingTheSameEditTwiceDoesNotMarkItChangedTheSecondTime() {
        let l = makeLedger()
        let patch = UDWatch.favoritePatch(key: "m", favorite: true, at: stamp(1))
        XCTAssertTrue(l.apply(patch))
        XCTAssertFalse(l.apply(patch))
        XCTAssertFalse(l.apply(UDWatch.favoritePatch(key: "m", favorite: false, at: stamp(0))), "an older edit changes nothing")
        XCTAssertEqual(UDWatch.value(of: l.record(key: "watch/m")!)?.favorite, true)
    }
}

final class EssentialsTests: XCTestCase {
    private func source(_ i: Int) -> UDSourceDefinition {
        UDSourceDefinition(id: "src\(i)", kind: "smb", name: "Server number \(i) in the living room", host: "nas\(i).local", port: 445, path: "/Movies/Collections/Everything", username: "family", auth: "password", addedAt: at(Double(i)))
    }

    func testSourcesAndSettingsComeBackFromUserDefaultsWithTheirStamps() throws {
        let kv = InMemoryKeyValueStore()
        let l = makeLedger()
        l.upsertSource(source(1), at: at(1))
        l.setSetting("nextEpisode", .string("credits"), at: at(2))
        LedgerRecorder(ledger: l).recordFavorite(key: "m", favorite: true, at: at(3))   // watch data is NOT in the essentials
        try UDEssentialsStore(store: kv).save(from: l)
        let fresh = makeLedger("B")
        XCTAssertEqual(UDEssentialsStore(store: kv).restore(into: fresh), 2)
        XCTAssertEqual(fresh.sourceDefinitions(), [source(1)])
        XCTAssertEqual(fresh.settingValues()["nextEpisode"], .string("credits"))
        XCTAssertTrue(fresh.watchEntries().isEmpty)
    }

    func testTheEssentialsStayUnder200KBForAVeryLargeSetup() throws {
        // 100 sources and 400 settings is far beyond real use; it must fit with room to spare.
        let kv = InMemoryKeyValueStore(), l = makeLedger()
        for i in 0..<100 { l.upsertSource(source(i), at: at(Double(i))) }
        for i in 0..<400 { l.setSetting("setting.number.\(i)", .string("value \(i) with some text"), at: at(Double(i))) }
        let store = UDEssentialsStore(store: kv)
        try store.save(from: l)
        XCTAssertLessThan(store.storedBytes, UDEssentialsStore.budgetBytes, "stored \(store.storedBytes) bytes")
        XCTAssertLessThan(UDEssentialsStore.budgetBytes, UDEssentialsStore.ceilingBytes)
        XCTAssertLessThan(kv.totalBytes, 200_000)
    }

    func testAnOversizedSetupIsRefusedAndTheLastGoodCopyIsKept() throws {
        let kv = InMemoryKeyValueStore(), l = makeLedger()
        l.upsertSource(source(1), at: at(1))
        let store = UDEssentialsStore(store: kv)
        try store.save(from: l)
        let good = kv.data(forKey: UDEssentialsStore.storageKey)
        l.setSetting("huge", .string(String(repeating: "z", count: 250_000)), at: at(2))
        XCTAssertThrowsError(try store.save(from: l)) { error in
            guard case let UDEssentialsError.overBudget(bytes, budget) = error else { return XCTFail("\(error)") }
            XCTAssertGreaterThan(bytes, budget)
            XCTAssertEqual(budget, 200_000)
        }
        XCTAssertEqual(kv.data(forKey: UDEssentialsStore.storageKey), good)
    }

    func testADamagedCopyIsIgnoredNotFatal() {
        let kv = InMemoryKeyValueStore()
        kv.set(Data("garbage".utf8), forKey: UDEssentialsStore.storageKey)
        XCTAssertEqual(UDEssentialsStore(store: kv).load(), [])
        kv.set(Data(#"{"format":"video-player-essentials","version":7,"records":[]}"#.utf8), forKey: UDEssentialsStore.storageKey)
        XCTAssertEqual(UDEssentialsStore(store: kv).load(), [])
        XCTAssertEqual(UDEssentialsStore(store: InMemoryKeyValueStore()).load(), [])
    }

    func testRestoringNeverOverwritesNewerData() throws {
        let kv = InMemoryKeyValueStore(), old = makeLedger()
        old.setSetting("rate", .int(1), at: at(1))
        try UDEssentialsStore(store: kv).save(from: old)
        let current = makeLedger("B")
        current.setSetting("rate", .int(2), at: at(5))
        UDEssentialsStore(store: kv).restore(into: current)
        XCTAssertEqual(current.settingValues()["rate"], .int(2))
    }

    func testTheUserDefaultsAdapterRoundTripsData() throws {
        let suite = "vp.test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let kv = UserDefaultsKeyValueStore(defaults: defaults)
        XCTAssertNil(kv.data(forKey: "k"))
        kv.set(Data("abc".utf8), forKey: "k")
        XCTAssertEqual(kv.data(forKey: "k"), Data("abc".utf8))
        kv.set(nil, forKey: "k")
        XCTAssertNil(kv.data(forKey: "k"))
    }
}

final class ExportImportTests: XCTestCase {
    private func filled() -> UserDataLedger {
        let l = makeLedger()
        let r = LedgerRecorder(ledger: l)
        r.recordProgress(key: "movie:a", UDWatchValue(position: 10, duration: 100, lastPlayed: at(5)), at: at(5))
        r.recordFavorite(key: "movie:a", favorite: true, at: at(6))
        l.upsertSource(UDSourceDefinition(id: "s1", kind: "webdav", name: "NAS", host: "nas.local", auth: "password"), at: at(1))
        l.setSetting("x", .double(1.5), at: at(2))
        l.apply(UDView.tombstone(uid: "gone", at: stamp(3)))
        return l
    }

    func testTheSameDataAlwaysExportsToTheSameBytes() throws {
        let one = try UDExport.export(filled(), at: at(100)), two = try UDExport.export(filled(), at: at(100))
        XCTAssertEqual(one, two)
    }

    func testExportThenImportRestoresEverythingExactly() throws {
        let l = filled()
        let data = try UDExport.export(l)
        let fresh = makeLedger("B")
        XCTAssertEqual(try UDExport.import(data, into: fresh), l.count)
        XCTAssertEqual(fresh.allRecords(), l.allRecords())
        XCTAssertEqual(try UDExport.import(data, into: fresh), 0, "importing twice changes nothing")
    }

    func testAnOldBackupNeverOverwritesNewerData() throws {
        let l = filled()
        let backup = try UDExport.export(l)
        LedgerRecorder(ledger: l).recordFavorite(key: "movie:a", favorite: false, at: at(500))
        try UDExport.import(backup, into: l)
        XCTAssertEqual(l.watchEntries().first?.value.favorite, false)
    }

    func testTheExportContainsNoPasswordsOrTokens() throws {
        let l = filled()
        let creds = InMemoryCredentialStore()
        try creds.setSecret("hunter2-secret", for: "s1")
        let text = String(decoding: try UDExport.export(l), as: UTF8.self)
        XCTAssertFalse(text.contains("hunter2"))
        XCTAssertFalse(text.lowercased().contains("password\":"), "there is no password field; `auth` only names the method")
    }

    func testNonBackupsAndDamagedBackupsAreRefusedWithTheRightError() throws {
        XCTAssertThrowsError(try UDExport.import(Data("[1,2,3]".utf8), into: makeLedger())) { XCTAssertEqual($0 as? UDExportError, .notAnExport) }
        XCTAssertThrowsError(try UDExport.import(Data("hello".utf8), into: makeLedger())) { XCTAssertEqual($0 as? UDExportError, .notAnExport) }
        XCTAssertThrowsError(try UDExport.import(Data(#"{"format":"video-player-userdata","version":1,"records":"x"}"#.utf8), into: makeLedger())) {
            guard case .damaged = $0 as? UDExportError else { return XCTFail("\($0)") }
        }
        XCTAssertThrowsError(try UDExport.import(Data(#"{"format":"video-player-userdata","version":2,"exportedAt":1,"records":[]}"#.utf8), into: makeLedger())) {
            XCTAssertEqual($0 as? UDExportError, .unsupportedVersion(2))
        }
    }
}

final class CredentialTests: XCTestCase {
    func testSourcesThatLostTheirPasswordAreFoundAndOpenOnesAreNot() throws {
        let store = InMemoryCredentialStore()
        let sources = [
            UDSourceDefinition(id: "open", kind: "webdav", name: "Open", auth: "none"),
            UDSourceDefinition(id: "kept", kind: "smb", name: "Kept", auth: "password"),
            UDSourceDefinition(id: "lost", kind: "sftp", name: "Lost", auth: "password"),
        ]
        try store.setSecret("pw", for: "kept")
        XCTAssertEqual(CredentialGap.sourcesNeedingPassword(sources, store: store).map(\.id), ["lost"])
        store.clear()
        XCTAssertEqual(CredentialGap.sourcesNeedingPassword(sources, store: store).map(\.id), ["kept", "lost"])
    }

    func testStatusTextsAreHonest() {
        XCTAssertTrue(UDStatusText.text(for: .signedOut).contains("will not survive"))
        XCTAssertTrue(UDStatusText.text(for: .iCloudFull).contains("full"))
        XCTAssertTrue(UDStatusText.text(for: .synced).contains("backed up"))
    }
}
