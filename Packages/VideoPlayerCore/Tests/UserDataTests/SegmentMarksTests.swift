import XCTest
@testable import UserData

/// User-marked segments in the ledger (Sources/UserData/SegmentMarks.swift). All data is made up (fixture).
final class SegmentMarksTests: XCTestCase {
    private func mark(key: String = "show-s01e01", kind: String = "intro", start: Double = 30, end: Double = 90, duration: Double? = 1500) -> UDSegmentMark {
        UDSegmentMark(itemKey: key, kind: kind, start: start, end: end, fileDuration: duration, createdAt: at(1))
    }

    func testSM1_aSavedMarkReadsBackWithAllItsFields() throws {
        let ledger = makeLedger()
        XCTAssertTrue(ledger.saveSegmentMark(mark(), at: at(10)))
        let got = try XCTUnwrap(ledger.segmentMarks(forItemKey: "show-s01e01").first)
        XCTAssertEqual(got, mark())
        XCTAssertEqual(ledger.record(type: UDSchema.segment, id: "show-s01e01|intro")?["v"]?.asInt, 1)
        XCTAssertEqual(ledger.dirtyCount, 1, "waiting for upload like any other user data")
    }

    func testSM2_oneMarkPerItemAndKindAndOtherItemsDoNotMix() {
        let ledger = makeLedger()
        ledger.saveSegmentMark(mark(key: "a", kind: "intro"), at: at(1))
        ledger.saveSegmentMark(mark(key: "a", kind: "credits", start: 1300, end: 1500), at: at(2))
        ledger.saveSegmentMark(mark(key: "b", kind: "intro", start: 10, end: 70), at: at(3))
        ledger.saveSegmentMark(mark(key: "a", kind: "intro", start: 40, end: 100), at: at(4))      // replaces a's intro
        XCTAssertEqual(ledger.segmentMarks(forItemKey: "a").map { $0.kind }, ["credits", "intro"])
        XCTAssertEqual(ledger.segmentMarks(forItemKey: "a").first { $0.kind == "intro" }?.start, 40)
        XCTAssertEqual(ledger.segmentMarks(forItemKey: "b").count, 1)
        XCTAssertEqual(ledger.segmentMarks(forItemKey: "c").count, 0)
        XCTAssertEqual(ledger.segmentMarks(forItemKey: "a|b").count, 0, "a key that contains the separator does not match a prefix")
    }

    func testSM3_itemKeysWithTheSeparatorWork() {
        let ledger = makeLedger()
        ledger.saveSegmentMark(mark(key: "odd|key", kind: "recap", start: 0, end: 40), at: at(1))
        XCTAssertEqual(ledger.segmentMarks(forItemKey: "odd|key").first?.kind, "recap")
        XCTAssertTrue(ledger.segmentMarks(forItemKey: "odd").isEmpty)
    }

    func testSM4_deleteIsATombstoneAndASaveBringsItBack() {
        let ledger = makeLedger()
        ledger.saveSegmentMark(mark(), at: at(1))
        ledger.deleteSegmentMark(itemKey: "show-s01e01", kind: "intro", at: at(2))
        XCTAssertTrue(ledger.segmentMarks(forItemKey: "show-s01e01").isEmpty)
        XCTAssertNotNil(ledger.record(type: UDSchema.segment, id: "show-s01e01|intro")?.deleted, "the deletion is stored so it can sync")
        ledger.saveSegmentMark(mark(start: 35, end: 95), at: at(3))
        XCTAssertEqual(ledger.segmentMarks(forItemKey: "show-s01e01").first?.start, 35)
        // A save older than the deletion does not bring it back.
        ledger.deleteSegmentMark(itemKey: "show-s01e01", kind: "intro", at: at(10))
        ledger.saveSegmentMark(mark(start: 36, end: 96), at: at(5))
        XCTAssertTrue(ledger.segmentMarks(forItemKey: "show-s01e01").isEmpty)
    }

    func testSM5_marksSurviveAFileRoundTrip() throws {
        let dir = try tempDir()
        let url = dir.appendingPathComponent("ledger.json")
        let ledger = makeLedger()
        ledger.saveSegmentMark(mark(), at: at(1))
        ledger.saveSegmentMark(mark(kind: "credits", start: 1300, end: 1500), at: at(2))
        ledger.deleteSegmentMark(itemKey: "show-s01e01", kind: "credits", at: at(3))
        try ledger.save(to: url)
        let restored = makeLedger("B")
        XCTAssertEqual(restored.load(from: url), .loaded(records: 2))
        XCTAssertEqual(restored.segmentMarks(forItemKey: "show-s01e01").map { $0.kind }, ["intro"])
    }

    func testSM6_aLedgerWrittenBeforeMarksExistedStillLoadsAndHasNone() throws {
        // FIXTURE: the shape of a version-1 ledger file that holds only a watch record (written before any mark existed).
        let old = """
        {"format":"video-player-ledger","version":1,"entries":[
          {"dirty":false,"tag":"t1","record":{"type":"watch","id":"item1","fields":{"position":{"value":{"d":12},"stamp":{"time":5,"device":"A"}}}}}
        ]}
        """
        let dir = try tempDir()
        let url = dir.appendingPathComponent("old.json")
        try Data(old.utf8).write(to: url)
        let ledger = makeLedger()
        XCTAssertEqual(ledger.load(from: url), .loaded(records: 1))
        XCTAssertTrue(ledger.segmentMarks(forItemKey: "item1").isEmpty)
        ledger.saveSegmentMark(mark(key: "item1"), at: at(10))
        XCTAssertEqual(ledger.segmentMarks(forItemKey: "item1").count, 1)
        XCTAssertEqual(ledger.watchEntries().first?.value.position, 12, "the watch record is untouched")
    }

    func testSM7_aMinimalRecordFromAnOlderOrNewerAppStillReads() {
        // Only kind, start and end (what the schema promised from the first version); no fileDuration, createdAt or v.
        var minimal = UDRecord(type: UDSchema.segment, id: "k|intro")
        minimal.set("kind", .string("intro"), at: stamp(1))
        minimal.set("start", .double(10), at: stamp(1))
        minimal.set("end", .double(70), at: stamp(1))
        let ledger = makeLedger()
        ledger.apply(minimal)
        let got = ledger.segmentMarks(forItemKey: "k").first
        XCTAssertEqual(got?.start, 10)
        XCTAssertNil(got?.fileDuration)
        XCTAssertNil(got?.createdAt)
        // A newer app adds a field and a kind this version does not know: both are kept, the unknown kind is not read as a mark of a known type.
        var future = UDRecord(type: UDSchema.segment, id: "k|montage")
        future.set("kind", .string("montage"), at: stamp(2))
        future.set("start", .double(100), at: stamp(2))
        future.set("end", .double(200), at: stamp(2))
        future.set("v", .int(9), at: stamp(2))
        future.set("color", .string("blue"), at: stamp(2))
        ledger.apply(future)
        minimal.set("note", .string("from the future"), at: stamp(3))
        ledger.apply(minimal)
        XCTAssertEqual(ledger.record(type: UDSchema.segment, id: "k|intro")?["note"]?.asString, "from the future", "unknown fields are kept")
        XCTAssertEqual(ledger.segmentMarks(forItemKey: "k").map { $0.kind }, ["intro", "montage"], "the ledger keeps what it does not understand")
    }

    func testSM8_damagedRecordsAreSkippedNotTrusted() {
        let ledger = makeLedger()
        func put(_ id: String, kind: String?, start: UDValue?, end: UDValue?) {
            var r = UDRecord(type: UDSchema.segment, id: id)
            if let kind { r.set("kind", .string(kind), at: stamp(1)) }
            if let start { r.set("start", start, at: stamp(1)) }
            if let end { r.set("end", end, at: stamp(1)) }
            ledger.apply(r)
        }
        put("k|intro", kind: "intro", start: .double(50), end: .double(40))        // inverted
        put("k|recap", kind: "recap", start: .double(-5), end: .double(20))        // negative
        put("k|credits", kind: "credits", start: .string("soon"), end: .double(20)) // not a number
        put("k|other", kind: "recap", start: .double(1), end: .double(20))        // kind field disagrees with the id
        put("nokind", kind: nil, start: .double(1), end: .double(20))              // id has no kind part
        XCTAssertTrue(ledger.segmentMarks(forItemKey: "k").isEmpty)
        XCTAssertTrue(ledger.segmentMarks(forItemKey: "nokind").isEmpty)
    }

    func testSM9_twoDevicesMergeByTheLaterEditAndTheRangeNeverMixes() {
        let a = makeLedger("A"), b = makeLedger("B")
        a.saveSegmentMark(mark(start: 30, end: 90, duration: 1500), at: at(10))
        b.saveSegmentMark(mark(start: 40, end: 110, duration: 1490), at: at(20))
        for r in a.allRecords() { b.apply(r) }
        for r in b.allRecords() { a.apply(r) }
        let ma = a.segmentMarks(forItemKey: "show-s01e01").first, mb = b.segmentMarks(forItemKey: "show-s01e01").first
        XCTAssertEqual(ma, mb)
        XCTAssertEqual(ma?.start, 40)
        XCTAssertEqual(ma?.end, 110)
        XCTAssertEqual(ma?.fileDuration, 1490, "the length moves with the range")
    }

    func testSM10_marksSyncThroughTheCloudToAnotherDevice() async throws {
        let cloud = InMemoryCloud()
        let a = makeLedger("A"), b = makeLedger("B")
        a.saveSegmentMark(mark(), at: at(10))
        a.saveSegmentMark(mark(kind: "credits", start: 1300, end: 1500), at: at(11))
        a.deleteSegmentMark(itemKey: "show-s01e01", kind: "credits", at: at(12))
        _ = await makeEngine(a, cloud).sync()
        let report = await makeEngine(b, cloud).sync()
        XCTAssertEqual(report.status, .synced)
        XCTAssertEqual(b.segmentMarks(forItemKey: "show-s01e01").map { $0.kind }, ["intro"], "the deletion synced too")
        // B undoes the deletion later; A sees it.
        b.saveSegmentMark(mark(kind: "credits", start: 1310, end: 1500), at: at(30))
        _ = await makeEngine(b, cloud).sync()
        _ = await makeEngine(a, cloud).sync()
        XCTAssertEqual(a.segmentMarks(forItemKey: "show-s01e01").first { $0.kind == "credits" }?.start, 1310)
    }

    func testSM11_marksAreInTheExportAndComeBackOnImport() throws {
        let a = makeLedger("A")
        a.saveSegmentMark(mark(), at: at(10))
        let data = try UDExport.export(a, at: at(20))
        let b = makeLedger("B")
        XCTAssertEqual(try UDExport.import(data, into: b), 1)
        XCTAssertEqual(b.segmentMarks(forItemKey: "show-s01e01").count, 1)
    }

    func testSM12_marksAreNotPartOfTheEssentialsCopy() {
        // The essentials copy in UserDefaults is for the source list and settings only (STORAGE_MODEL section 5); marks use the cloud and Export.
        let ledger = makeLedger()
        ledger.saveSegmentMark(mark(), at: at(1))
        let store = InMemoryKeyValueStore()
        let essentials = UDEssentialsStore(store: store)
        XCTAssertNoThrow(try essentials.save(from: ledger))
        let restored = makeLedger("B")
        essentials.restore(into: restored)
        XCTAssertTrue(restored.segmentMarks(forItemKey: "show-s01e01").isEmpty)
    }
}
