import XCTest
@testable import UserData

final class MergeTests: XCTestCase {
    // MARK: Values and records

    func testValuesKeepTheirTypeThroughJSON() throws {
        let values: [UDValue] = [.null, .bool(true), .bool(false), .int(3), .int(-9_000_000_000), .double(3.0), .double(0.1), .string(""), .string("héllo \"x\"")]
        for v in values {
            let data = try JSONEncoder().encode(v)
            XCTAssertEqual(try JSONDecoder().decode(UDValue.self, from: data), v, "\(v)")
        }
        XCTAssertNotEqual(try JSONDecoder().decode(UDValue.self, from: JSONEncoder().encode(UDValue.double(3.0))), UDValue.int(3))
    }

    func testANonFiniteNumberIsRefusedAtEncodingNotWrittenAsGarbage() {
        XCTAssertThrowsError(try JSONEncoder().encode(UDValue.double(.infinity)))
        XCTAssertThrowsError(try JSONEncoder().encode(UDValue.double(.nan)))
    }

    func testStampsOrderByTimeThenDevice() {
        XCTAssertLessThan(stamp(1, "B"), stamp(2, "A"))
        XCTAssertLessThan(stamp(1, "A"), stamp(1, "B"))
        XCTAssertEqual(stamp(1, "A"), stamp(1, "A"))
    }

    func testCloudNameIsPlainWhenShortAndAHashWhenLongOrOdd() {
        XCTAssertEqual(UDRecord(type: "watch", id: "movie:heat:1995").cloudName, "watch.movie:heat:1995")
        let long = UDRecord(type: "watch", id: String(repeating: "x", count: 400)).cloudName
        XCTAssertTrue(long.hasPrefix("watch.h"))
        XCTAssertLessThan(long.utf8.count, 60)
        let odd = UDRecord(type: "watch", id: "a/b c é").cloudName
        XCTAssertTrue(odd.hasPrefix("watch.h"))
        XCTAssertEqual(UDRecord(type: "watch", id: "a/b c é").cloudName, odd, "stable")
        XCTAssertNotEqual(UDRecord(type: "watch", id: "a/b c ê").cloudName, odd)
    }

    // MARK: Field rules

    func testALaterFieldWinsAndAnEarlierOneLoses() {
        var a = UDRecord(type: UDSchema.settings, id: "settings"), b = a
        a.set("theme", .string("dark"), at: stamp(10, "A"))
        a.set("rate", .double(1.0), at: stamp(30, "A"))
        b.set("theme", .string("light"), at: stamp(20, "B"))
        b.set("rate", .double(2.0), at: stamp(5, "B"))
        let m = UDSchema.merge(a, b)
        XCTAssertEqual(m["theme"], .string("light"))
        XCTAssertEqual(m["rate"], .double(1.0))
        XCTAssertEqual(UDSchema.merge(b, a), m)
    }

    func testDifferentFieldsOfOneRecordBothSurvive() {
        var a = UDRecord(type: UDSchema.settings, id: "settings"), b = a
        a.set("x", .int(1), at: stamp(1, "A"))
        b.set("y", .int(2), at: stamp(2, "B"))
        let m = UDSchema.merge(a, b)
        XCTAssertEqual(m["x"], .int(1))
        XCTAssertEqual(m["y"], .int(2))
    }

    func testAWatchProgressGroupMovesAsOneAndNeverMixesTwoPlays() {
        // Device A stopped at 600 s at t=100; device B finished the film at t=200. The result is B's finished state,
        // never "position 600 with watched = true".
        let a = UDWatch.progressPatch(key: "k", UDWatchValue(position: 600, duration: 7200, watched: false, playCount: 0, lastPlayed: at(100)), epoch: 0, at: stamp(100, "A"))
        let b = UDWatch.progressPatch(key: "k", UDWatchValue(position: 0, duration: 7200, watched: true, playCount: 1, lastPlayed: at(200)), epoch: 0, at: stamp(200, "B"))
        for m in [UDSchema.merge(a, b), UDSchema.merge(b, a)] {
            let v = UDWatch.value(of: m)
            XCTAssertEqual(v?.watched, true)
            XCTAssertEqual(v?.position, 0)
            XCTAssertEqual(v?.lastPlayed, at(200))
            XCTAssertEqual(v?.playCount, 1)
        }
    }

    func testFavoriteAndHiddenAreIndependentOfProgress() {
        let progress = UDWatch.progressPatch(key: "k", UDWatchValue(position: 10, duration: 100, lastPlayed: at(50)), epoch: 0, at: stamp(50, "A"))
        let fav = UDWatch.favoritePatch(key: "k", favorite: true, at: stamp(10, "B"))   // older than the progress
        let m = UDSchema.merge(progress, fav)
        XCTAssertEqual(UDWatch.value(of: m)?.favorite, true, "an older favourite is not erased by newer progress")
        XCTAssertEqual(UDWatch.value(of: m)?.position, 10)
    }

    func testPlayCountsFromTwoDevicesInOneEpochKeepTheLarger() {
        let a = UDWatch.progressPatch(key: "k", UDWatchValue(watched: true, playCount: 2, lastPlayed: at(10)), epoch: 0, at: stamp(10, "A"))
        let b = UDWatch.progressPatch(key: "k", UDWatchValue(watched: true, playCount: 3, lastPlayed: at(5)), epoch: 0, at: stamp(5, "B"))
        XCTAssertEqual(UDWatch.value(of: UDSchema.merge(a, b))?.playCount, 3)
        XCTAssertEqual(UDWatch.value(of: UDSchema.merge(b, a))?.playCount, 3)
    }

    func testMarkingUnwatchedStartsANewEpochThatBeatsOlderCountsEverywhere() {
        let played = UDWatch.progressPatch(key: "k", UDWatchValue(watched: true, playCount: 5, lastPlayed: at(10)), epoch: 0, at: stamp(10, "A"))
        let reset = UDWatch.progressPatch(key: "k", UDWatchValue(), epoch: at(100).timeIntervalSince1970, at: stamp(100, "B"))
        for m in [UDSchema.merge(played, reset), UDSchema.merge(reset, played)] {
            let v = UDWatch.value(of: m)
            XCTAssertEqual(v?.playCount, 0)
            XCTAssertEqual(v?.watched, false)
        }
    }

    func testAWatchedFlagAlwaysCountsAsAtLeastOnePlay() {
        var r = UDRecord(type: UDSchema.watch, id: "k")
        r.set("watched", .bool(true), at: stamp(1))
        XCTAssertEqual(UDWatch.value(of: r)?.playCount, 1)
    }

    func testMaxFieldsOnlyGrow() {
        var a = UDRecord(type: UDSchema.learnedSkip, id: "s"), b = a
        a.set("samples", .int(5), at: stamp(10, "A"))
        b.set("samples", .int(3), at: stamp(20, "B"))
        XCTAssertEqual(UDSchema.merge(a, b)["samples"], .int(5))
        XCTAssertEqual(UDSchema.merge(b, a)["samples"], .int(5))
    }

    func testViewDefinitionFieldsMoveTogether() {
        var a = UDRecord(type: UDSchema.view, id: "v"), b = a
        a.set("scopeKind", .int(0), at: stamp(10, "A")); a.set("scopeSource", .string(""), at: stamp(10, "A")); a.set("scopePath", .string(""), at: stamp(10, "A")); a.set("query", .string("{A}"), at: stamp(10, "A"))
        b.set("scopeKind", .int(1), at: stamp(20, "B")); b.set("scopeSource", .string("s"), at: stamp(20, "B")); b.set("scopePath", .string("/p"), at: stamp(20, "B")); b.set("query", .string("{B}"), at: stamp(20, "B"))
        a.set("name", .string("Old name"), at: stamp(30, "A"))
        let m = UDSchema.merge(a, b)
        XCTAssertEqual(m["query"], .string("{B}"))
        XCTAssertEqual(m["scopePath"], .string("/p"))
        XCTAssertEqual(m["name"], .string("Old name"), "the name is its own field")
    }

    // MARK: Deletion

    func testADeletionBeatsOlderFieldsAndALaterEditBringsTheRecordBack() {
        var live = UDRecord(type: UDSchema.view, id: "v")
        live.set("name", .string("Action"), at: stamp(10, "A"))
        live.set("query", .string("{}"), at: stamp(10, "A"))
        let dead = UDView.tombstone(uid: "v", at: stamp(20, "B"))
        let gone = UDSchema.merge(live, dead)
        XCTAssertTrue(gone.isDeleted)
        XCTAssertTrue(gone.liveFields.isEmpty)
        XCTAssertEqual(UDSchema.merge(dead, live), gone)
        var edit = UDRecord(type: UDSchema.view, id: "v")
        edit.set("name", .string("Action 2"), at: stamp(30, "A"))
        let back = UDSchema.merge(gone, edit)
        XCTAssertFalse(back.isDeleted)
        XCTAssertEqual(back["name"], .string("Action 2"))
        XCTAssertNil(back["query"], "fields older than the deletion stay gone")
    }

    func testADeletionAtTheSameStampAsAFieldWins() {
        var live = UDRecord(type: UDSchema.view, id: "v")
        live.set("name", .string("x"), at: stamp(10, "A"))
        XCTAssertTrue(UDSchema.merge(live, UDView.tombstone(uid: "v", at: stamp(10, "A"))).isDeleted)
    }

    func testARecordOfAnUnknownTypeSurvivesAndMergesFieldByField() {
        var a = UDRecord(type: "futuretype", id: "1"), b = a
        a.set("p", .int(1), at: stamp(1, "A"))
        b.set("p", .int(2), at: stamp(2, "B"))
        b.set("q", .string("new"), at: stamp(2, "B"))
        let m = UDSchema.merge(a, b)
        XCTAssertEqual(m["p"], .int(2))
        XCTAssertEqual(m["q"], .string("new"))
    }

    func testRecordsOfDifferentIdentityAreNotMerged() {
        let a = UDRecord(type: "watch", id: "a", fields: ["x": UDField(.int(1), stamp(1))])
        let b = UDRecord(type: "watch", id: "b", fields: ["x": UDField(.int(2), stamp(2))])
        XCTAssertEqual(UDSchema.merge(a, b), a)
    }

    // MARK: The three laws, on random records

    private func randomRecord(_ rng: inout LCG, type: String, id: String) -> UDRecord {
        var r = UDRecord(type: type, id: id)
        let devices = ["A", "B", "C"]
        let t = Double(rng.int(6) + 1)
        let d = devices[rng.int(3)]
        switch type {
        case UDSchema.watch:
            if rng.chance(70) {
                let st = stamp(t, d)
                let v = UDWatchValue(position: Double(rng.int(4) * 100), duration: rng.chance(50) ? 7200 : nil, watched: rng.chance(40), playCount: rng.int(4), lastPlayed: rng.chance(60) ? at(t) : nil)
                r = UDWatch.progressPatch(key: id, v, epoch: Double(rng.int(3)), at: st)
            }
            if rng.chance(40) { r.set("favorite", .bool(rng.chance(50)), at: stamp(Double(rng.int(6) + 1), devices[rng.int(3)])) }
        case UDSchema.settings:
            for k in ["a", "b", "c"] where rng.chance(60) { r.set(k, .int(Int64(rng.int(3))), at: stamp(Double(rng.int(6) + 1), devices[rng.int(3)])) }
        default:
            for k in ["name", "pinned", "query", "scopeKind", "scopeSource", "scopePath", "position"] where rng.chance(50) {
                r.set(k, .int(Int64(rng.int(3))), at: stamp(Double(rng.int(6) + 1), devices[rng.int(3)]))
            }
        }
        if rng.chance(15) { r.deleted = stamp(Double(rng.int(6) + 1), devices[rng.int(3)]) }
        return r
    }

    func testMergeIsCommutativeAssociativeAndIdempotentOnRandomRecords() {
        var rng = LCG(7)
        for type in [UDSchema.watch, UDSchema.settings, UDSchema.view] {
            for round in 0..<400 {
                let a = randomRecord(&rng, type: type, id: "k"), b = randomRecord(&rng, type: type, id: "k"), c = randomRecord(&rng, type: type, id: "k")
                XCTAssertEqual(UDSchema.merge(a, b), UDSchema.merge(b, a), "commutative \(type) #\(round)")
                XCTAssertEqual(UDSchema.merge(UDSchema.merge(a, b), c), UDSchema.merge(a, UDSchema.merge(b, c)), "associative \(type) #\(round)")
                let m = UDSchema.merge(a, a)
                XCTAssertEqual(UDSchema.merge(m, a), m, "idempotent \(type) #\(round)")
                XCTAssertEqual(UDSchema.merge(m, m), m)
            }
        }
    }
}
