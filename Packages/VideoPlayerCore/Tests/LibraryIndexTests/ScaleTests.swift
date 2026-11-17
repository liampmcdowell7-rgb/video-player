import XCTest
import VideoPlayerCore
@testable import LibraryIndex

// Generated libraries of 1,000, 10,000 and 100,000 items. Each test scans a fake source with realistic folder
// shapes, checks the index against what was generated, and prints timings (lines start with "PERF"). The same
// lines are appended to /tmp/library-index-perf.txt so a run can be copied into docs/LIBRARY_INDEX.md.
//
// Ceilings are about ten times what was measured on the reference machine (docs/LIBRARY_INDEX.md): they fail
// on a large regression, not on a slower computer.

struct GeneratedLibrary {
    var source = FakeSource()
    var items = 0
    var videoFiles = 0
    var sidecarFiles = 0
    /// Video files that are the only version of their item (safe to remove without removing the item).
    var singleVersionVideos: [String] = []
    var allVideos: [String] = []
    var flatFolder = ""

    static let words = ["Amber", "Birch", "Cobalt", "Dune", "Ember", "Falcon", "Garnet", "Harbor", "Indigo", "Juniper", "Kestrel", "Lantern", "Meadow", "Nebula", "Onyx",
                        "Pewter", "Quartz", "Raven", "Sable", "Tundra", "Umber", "Velvet", "Willow", "Xenon", "Yarrow", "Zephyr", "Anchor", "Beacon", "Cinder", "Delta",
                        "Echo", "Fjord", "Glacier", "Horizon", "Ivory", "Jasper", "Kindle", "Lagoon", "Mirage", "Nimbus", "Oasis", "Prairie", "Quill", "Ridge", "Summit",
                        "Thistle", "Upland", "Vortex", "Wander", "Yonder", "Zenith", "Aurora", "Basalt", "Canyon", "Drift", "Equinox", "Flint", "Grove", "Hollow", "Island"]

    /// Unique for every index below 216,000.
    static func title(_ i: Int) -> String {
        "\(words[i % 60]) \(words[(i / 60) % 60]) \(words[(i / 3600) % 60])"
    }

    static func generate(items n: Int) -> GeneratedLibrary {
        var lib = GeneratedLibrary()
        var files: [(path: String, size: Int64, modified: Date)] = []
        files.reserveCapacity(n + n / 2)
        var rng = LCG(2024)
        var folderMovie = 0, flatMovie = 0, episode = 0
        for i in 0..<n {
            let size = Int64(700_000_000 + rng.int(40_000_000_000))
            let modified = t0.addingTimeInterval(Double(i) * 60)
            switch i % 100 {
            case 0..<55:
                let title = Self.title(i), year = 1950 + i % 75
                let name = "\(title) (\(year))"
                let dir = "/Movies/\(title.first.map(String.init) ?? "_")/\(name)"
                let path = "\(dir)/\(name).mkv"
                files.append((path, size, modified))
                lib.allVideos.append(path)
                lib.videoFiles += 1
                if folderMovie % 3 == 0 { files.append(("\(dir)/\(name).en.srt", 60_000, modified)); lib.sidecarFiles += 1 }
                if folderMovie % 20 == 0 {
                    files.append(("\(dir)/\(name) 2160p.mkv", size * 3, modified)); lib.videoFiles += 1
                    lib.allVideos.append("\(dir)/\(name) 2160p.mkv")
                } else {
                    lib.singleVersionVideos.append(path)
                }
                folderMovie += 1
            case 55..<70:
                let title = Self.title(i), year = 1950 + i % 75
                let bucket = String(flatMovie / 500 + 1000).dropFirst()
                let path = "/Films/Part \(bucket)/\(title) (\(year)).mp4"
                files.append((path, size, modified))
                lib.allVideos.append(path)
                lib.singleVersionVideos.append(path)
                lib.videoFiles += 1
                if lib.flatFolder.isEmpty { lib.flatFolder = "/Films/Part \(bucket)" }
                flatMovie += 1
            default:
                let show = episode / 30, season = (episode % 30) / 10 + 1, ep = episode % 10 + 1
                let showTitle = Self.title(150_000 + show), showYear = 1990 + show % 30
                let path = "/TV/\(showTitle) (\(showYear))/Season \(season < 10 ? "0" : "")\(season)/\(showTitle) - S\(season < 10 ? "0" : "")\(season)E\(ep < 10 ? "0" : "")\(ep) - \(Self.words[episode % 60]).mkv"
                files.append((path, size, modified))
                lib.allVideos.append(path)
                lib.singleVersionVideos.append(path)
                lib.videoFiles += 1
                episode += 1
            }
        }
        lib.items = n
        lib.source.bulkLoad(files)
        return lib
    }
}

enum ProcessMemory {
    static func status(_ key: String, file: String = "/proc/self/status") -> Int? {
        guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix(key + ":") {
            return Int(line.dropFirst(key.count + 1).split(whereSeparator: { $0 == " " || $0 == "\t" }).first ?? "")
        }
        return nil
    }
    static var rssKB: Int? { status("VmRSS") }
    static var peakKB: Int? { status("VmHWM") }
    /// Linux: lets VmHWM start again from the current size.
    static func resetPeak() { try? "5".write(toFile: "/proc/self/clear_refs", atomically: false, encoding: .utf8) }
}

enum PerfLog {
    static let path = "/tmp/library-index-perf.txt"
    static func line(_ s: String) {
        print("PERF \(s)")
        if let data = ("PERF \(s)\n").data(using: .utf8) {
            if let h = FileHandle(forWritingAtPath: path) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }
    static func machine() -> String {
        let cpu = (try? String(contentsOfFile: "/proc/cpuinfo", encoding: .utf8))?.split(separator: "\n").first { $0.hasPrefix("model name") }.map { String($0.split(separator: ":").last ?? "").trimmingCharacters(in: .whitespaces) } ?? "unknown CPU"
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let mem = ProcessMemory.status("MemTotal", file: "/proc/meminfo") ?? 0
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        #if DEBUG
        let build = "debug build"
        #else
        let build = "release build"
        #endif
        return "\(cpu), \(cores) cores, \(mem / 1024) MB RAM, \(os), SQLite \(SQLiteInfo.version), \(build)"
    }
}

struct Timing {
    var label: String
    var cold: Double
    var median: Double
    var worst: Double
}

func milliseconds(_ body: () async throws -> Void) async throws -> Double {
    let start = DispatchTime.now().uptimeNanoseconds
    try await body()
    return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}

func timeQuery(_ label: String, runs: Int = 15, _ body: () async throws -> Void) async throws -> Timing {
    let cold = try await milliseconds(body)
    var samples: [Double] = []
    for _ in 0..<runs { samples.append(try await milliseconds(body)) }
    samples.sort()
    return Timing(label: label, cold: cold, median: samples[samples.count / 2], worst: samples.last ?? cold)
}

final class ScaleTests: XCTestCase {
    // Ceilings are about 10x the release-build numbers measured on the machine in docs/LIBRARY_INDEX.md, so a 10x regression fails and a debug build still passes.
    func testScale1000() async throws { try await runScale(items: 1_000, ceilings: .init(firstScanSeconds: 25, rescanSeconds: 3, changedRescanSeconds: 3, queryMs: 10, searchMs: 15)) }
    func testScale10000() async throws { try await runScale(items: 10_000, ceilings: .init(firstScanSeconds: 225, rescanSeconds: 15, changedRescanSeconds: 17, queryMs: 30, searchMs: 45)) }
    func testScale100000() async throws {
        // Opt-in: the 100,000-item run takes about 5 minutes in a release build and far longer in a debug build, and
        // the Codemagic compile check runs plain `swift test`, which must not spend its few minutes on it.
        // Run it with: VP_RUN_100K=1 swift test -c release --filter ScaleTests (see scripts/test-scale.sh).
        if ProcessInfo.processInfo.environment["VP_RUN_100K"] != "1" { throw XCTSkip("100,000-item run is opt-in: set VP_RUN_100K=1 (about 5 minutes in a release build)") }
        try await runScale(items: 100_000, ceilings: .init(firstScanSeconds: 2_200, rescanSeconds: 160, changedRescanSeconds: 175, queryMs: 300, searchMs: 520))
    }

    struct Ceilings {
        var firstScanSeconds: Double
        var rescanSeconds: Double
        var changedRescanSeconds: Double
        var queryMs: Double
        var searchMs: Double
    }

    func runScale(items n: Int, ceilings: Ceilings) async throws {
        PerfLog.line("=== \(n) items === machine: \(PerfLog.machine())")
        let genStart = DispatchTime.now().uptimeNanoseconds
        var lib = GeneratedLibrary.generate(items: n)
        PerfLog.line("\(n): generated \(lib.videoFiles) video files, \(lib.sidecarFiles) sidecars, \(lib.source.folderCount) folders in \(Int(Double(DispatchTime.now().uptimeNanoseconds - genStart) / 1_000_000)) ms (not part of any timing)")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("libidx-scale-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbPath = dir.appendingPathComponent("library.sqlite").path
        let store = try SQLiteLibraryStore(path: dbPath)
        let sourceID = "scale"
        try await store.upsertSource(LibrarySourceRecord(id: sourceID, kind: .webdav, name: "Scale", addedAt: t0))
        let scanClock = t0.addingTimeInterval(400 * 86_400)
        let syncer = LibrarySyncer(store: store, source: lib.source, sourceID: sourceID, annotator: HashAnnotator(), clock: { scanClock })

        // ---- First scan
        let rssBefore = ProcessMemory.rssKB
        ProcessMemory.resetPeak()
        let maxPending = Locked(0)
        let first = try await syncer.sync(progress: { p in maxPending.with { $0 = max($0, p.foldersPending) } })
        let peakAfter = ProcessMemory.peakKB
        XCTAssertEqual(first.status, .completed)
        XCTAssertTrue(first.failures.isEmpty)
        XCTAssertEqual(first.progress.added, lib.videoFiles + lib.sidecarFiles)
        XCTAssertEqual(first.progress.foldersDone, lib.source.folderCount)
        let counts = try await store.counts()
        XCTAssertEqual(counts.items, n)
        XCTAssertEqual(counts.files, lib.videoFiles + lib.sidecarFiles)
        XCTAssertEqual(counts.folders, lib.source.folderCount)
        PerfLog.line("\(n): first scan \(String(format: "%.2f", first.seconds)) s (\(Int(Double(n) / max(first.seconds, 0.001))) items/s), \(counts.files) files, \(counts.folders) folders, \(first.progress.foldersDone) listings; pending-folder queue peaked at \(maxPending.get)")
        if let before = rssBefore, let peak = peakAfter {
            PerfLog.line("\(n): memory during first scan: process RSS before \(before / 1024) MB, peak after \(peak / 1024) MB (growth \((peak - before) / 1024) MB, includes the in-memory fake source's reads and the database cache)")
        }
        XCTAssertLessThan(first.seconds, ceilings.firstScanSeconds)

        // ---- Enrich: ratings, genres, watch state (streamed in pages)
        var rng = LCG(11)
        let genres = ["Drama", "Comedy", "Action", "Horror", "Sci-Fi", "Documentary", "Animation", "Thriller"]
        let enrichStart = DispatchTime.now().uptimeNanoseconds
        var cursor: ItemCursor?
        var seen = 0
        repeat {
            let page = try await store.page(ItemQuery(sort: ItemSort(key: .added)), limit: 2_000, after: cursor)
            var batch: [(itemID: Int64, metadata: ItemMetadata)] = []
            var watched: [Int64] = []
            for item in page.items {
                batch.append((item.id, ItemMetadata(rating: Double(rng.int(91)) / 10, genres: (0..<(1 + rng.int(2))).map { _ in genres[rng.int(genres.count)] })))
                if rng.chance(5) { watched.append(item.id) }
            }
            try await store.setMetadata(batch: batch)
            try await store.markWatched(itemIDs: watched, watched: true, at: t0.addingTimeInterval(390 * 86_400))
            for item in page.items where rng.chance(1) {
                try await store.updateProgress(itemID: item.id, position: 300, duration: 6_000, at: t0.addingTimeInterval(Double(380 + rng.int(18)) * 86_400))
            }
            seen += page.items.count
            cursor = page.next
        } while cursor != nil
        XCTAssertEqual(seen, n)
        PerfLog.line("\(n): enrich (metadata for every item, 5% watched, 1% in progress) \(Int(Double(DispatchTime.now().uptimeNanoseconds - enrichStart) / 1_000_000)) ms")

        // ---- Rescan without changes
        lib.source.resetCalls()
        let quiet = try await syncer.sync()
        XCTAssertEqual(quiet.progress.added + quiet.progress.changed + quiet.progress.removed, 0)
        XCTAssertEqual(quiet.progress.unchanged, lib.videoFiles + lib.sidecarFiles)
        PerfLog.line("\(n): rescan, nothing changed: \(String(format: "%.2f", quiet.seconds)) s (\(Int(Double(n) / max(quiet.seconds, 0.001))) items/s), \(lib.source.totalListCalls) listings")
        XCTAssertLessThan(quiet.seconds, ceilings.rescanSeconds)

        // ---- Rescan with about 1% changed (0.6% edited, 0.2% removed, 0.3% added -> about 1.1%)
        let stepEdit = 160, stepRemove = 500
        var edited = 0, removed = 0, removedItems = 0
        let singles = Set(lib.singleVersionVideos)
        for (k, path) in lib.allVideos.enumerated() {
            if k % stepEdit == 3 {
                lib.source.put(path, size: 123_456_789, modified: t0.addingTimeInterval(399 * 86_400))
                edited += 1
            } else if k % stepRemove == 7 {
                lib.source.remove(path, bump: t0.addingTimeInterval(399 * 86_400))
                removed += 1
                if singles.contains(path) { removedItems += 1 }
            }
        }
        let addCount = max(1, n * 3 / 1000)
        for j in 0..<addCount {
            let name = "Fresh Arrival \(j) (2024)"
            lib.source.put("/Movies/F/\(name)/\(name).mkv", size: 5_000_000_000, modified: t0.addingTimeInterval(399 * 86_400))
        }
        lib.source.resetCalls()
        let changed = try await syncer.sync()
        let changedListings = lib.source.totalListCalls
        XCTAssertEqual(changed.progress.changed, edited)
        XCTAssertEqual(changed.progress.added, addCount)
        // A folder whose only file was removed lists as empty; the empty-listing rule holds that back once,
        // so the next scan finishes the job. Together the two scans account for every removal.
        let settle = try await syncer.sync()
        XCTAssertEqual(changed.progress.removed + settle.progress.removed, removed)
        XCTAssertLessThanOrEqual(changed.progress.removed, removed)
        let afterCounts = try await store.counts()
        XCTAssertEqual(afterCounts.items, n - removedItems + addCount)
        let pct = Double(edited + removed + addCount) / Double(lib.videoFiles + lib.sidecarFiles) * 100
        PerfLog.line("\(n): rescan, \(edited) edited + \(removed) removed + \(addCount) added (\(String(format: "%.1f", pct))% of files): \(String(format: "%.2f", changed.seconds)) s, \(changedListings) listings (\(changed.progress.removed) removals applied at once, \(settle.progress.removed) after the empty-folder hold)")
        XCTAssertLessThan(changed.seconds, ceilings.changedRescanSeconds)

        // Same again with trusted folder versions: only the folders on the way to a change are listed.
        let trustFirst = try await syncer.sync(options: ScanOptions(trustFolderVersions: true), resume: false)   // stamps every folder's version
        lib.source.resetCalls()
        lib.source.put("/Movies/F/Fresh Arrival 0 (2024)/Fresh Arrival 0 (2024).mkv", size: 5_000_000_001, modified: t0.addingTimeInterval(399 * 86_400 + 5))
        lib.source.put("/Movies/F/Fresh Late (2025)/Fresh Late (2025).mkv", size: 1, modified: t0.addingTimeInterval(399 * 86_400 + 9))
        let trusted = try await syncer.sync(options: ScanOptions(trustFolderVersions: true))
        XCTAssertEqual(trusted.progress.changed, 1)
        XCTAssertEqual(trusted.progress.added, 1)
        PerfLog.line("\(n): rescan with trusted folder versions after 2 edits: \(String(format: "%.3f", trusted.seconds)) s, \(lib.source.totalListCalls) listings (a stamping scan before it took \(String(format: "%.2f", trustFirst.seconds)) s)")
        XCTAssertLessThan(lib.source.totalListCalls, 12)

        // ---- Queries
        var fourK = ItemFilter()
        fourK.resolutions = [.uhd4k]
        fourK.watch = .unwatched
        fourK.minRating = 6
        var combo = fourK
        combo.genres = ["Drama", "Thriller"]
        combo.yearMin = 1980
        combo.yearMax = 2010
        combo.dolbyVision = true
        combo.minChannels = 6

        let totalItems = try await store.counts().items   // after the trusted-scan step added one more item
        let index = try await store.alphabetIndex(ItemQuery())
        XCTAssertEqual(index.map(\.count).reduce(0, +), totalItems)
        let letterM = try await unwrap(index.first { $0.letter == "M" })
        let mid = totalItems / 2

        var timings: [Timing] = []
        timings.append(try await timeQuery("grid first page (60), sorted by title, no filter") { _ = try await store.page(ItemQuery(), limit: 60, after: nil) })
        timings.append(try await timeQuery("grid first page (60), sorted by title, 4K + unwatched + rating >= 6") { _ = try await store.page(ItemQuery(filter: fourK), limit: 60, after: nil) })
        timings.append(try await timeQuery("grid first page (60), sorted by title, 4K + unwatched + rating + genres + years + Dolby Vision + 5.1") { _ = try await store.page(ItemQuery(filter: combo), limit: 60, after: nil) })
        timings.append(try await timeQuery("grid first page (60), sorted by year descending") { _ = try await store.page(ItemQuery(sort: ItemSort(key: .year, ascending: false)), limit: 60, after: nil) })
        timings.append(try await timeQuery("grid first page (60), sorted by rating descending, unwatched") { var f = ItemFilter(); f.watch = .unwatched; _ = try await store.page(ItemQuery(filter: f, sort: ItemSort(key: .rating, ascending: false)), limit: 60, after: nil) })
        timings.append(try await timeQuery("grid page (60) from the middle by offset (\(mid)), sorted by title") { _ = try await store.page(ItemQuery(), limit: 60, offset: mid) })
        timings.append(try await timeQuery("alphabet index (letter -> row offset), all letters") { _ = try await store.alphabetIndex(ItemQuery()) })
        timings.append(try await timeQuery("alphabet jump: page (60) at the first M") { _ = try await store.page(ItemQuery(), limit: 60, offset: letterM.offset) })
        timings.append(try await timeQuery("count for the filter 4K + unwatched + rating >= 6") { _ = try await store.count(ItemQuery(filter: fourK)) })
        let search = timings.count
        timings.append(try await timeQuery("title search, 2 words (\"amber birch\"), first 60") { var f = ItemFilter(); f.text = "amber birch"; _ = try await store.page(ItemQuery(filter: f), limit: 60, after: nil) })
        timings.append(try await timeQuery("title search, one word that matches a lot (\"ra\"), first 60") { var f = ItemFilter(); f.text = "ra"; _ = try await store.page(ItemQuery(filter: f), limit: 60, after: nil) })
        timings.append(try await timeQuery("title search, no match") { var f = ItemFilter(); f.text = "qqqzzz"; _ = try await store.page(ItemQuery(filter: f), limit: 60, after: nil) })
        let home = timings.count
        timings.append(try await timeQuery("Continue Watching row (20)") { _ = try await store.continueWatching(limit: 20, now: t0.addingTimeInterval(400 * 86_400), retentionDays: 60) })
        timings.append(try await timeQuery("Next Up row (20)") { _ = try await store.nextUp(limit: 20, now: t0.addingTimeInterval(400 * 86_400), retentionDays: 60) })
        timings.append(try await timeQuery("Recently Added row (20)") { _ = try await store.recentlyAdded(limit: 20, kind: nil) })
        timings.append(try await timeQuery("direct browsing: first 100 of a folder with 500 files") { _ = try await store.children(sourceID: sourceID, folder: lib.flatFolder, sort: FileSort(), limit: 100, offset: 0) })
        timings.append(try await timeQuery("direct browsing: first 100 of the root folder") { _ = try await store.children(sourceID: sourceID, folder: "/", sort: FileSort(), limit: 100, offset: 0) })
        timings.append(try await timeQuery("open one item: versions + item") { let id = try await unwrap(try await store.page(ItemQuery(), limit: 1, after: nil).items.first).id; _ = try await store.item(id: id); _ = try await store.versions(of: id) })
        timings.append(try await timeQuery("write: update playback position of one item") { try await store.updateProgress(itemID: 1, position: 500, duration: 6_000, at: t0.addingTimeInterval(399 * 86_400)) })
        for (k, t) in timings.enumerated() {
            PerfLog.line("\(n): query \"\(t.label)\": first call \(String(format: "%.2f", t.cold)) ms, median \(String(format: "%.2f", t.median)) ms, worst of 15 \(String(format: "%.2f", t.worst)) ms")
            let ceiling = (k >= search && k < home) ? ceilings.searchMs : ceilings.queryMs
            XCTAssertLessThan(t.median, ceiling, t.label)
        }

        // ---- Correctness of query answers against the generated data
        var movieFilter = ItemFilter()
        movieFilter.kinds = [.movie]   // episodes sort under their series title, so only movies are checked against their own title
        let firstPage = try await store.page(ItemQuery(filter: movieFilter), limit: 60, after: nil)
        let keys = firstPage.items.map { LibraryText.titleSortValue($0.title).value }
        XCTAssertEqual(keys, keys.sorted())
        var walked = 0
        var cur: ItemCursor?
        var lastKey = ""
        repeat {
            let p = try await store.page(ItemQuery(filter: movieFilter), limit: 500, after: cur)
            for item in p.items {
                let k = LibraryText.titleSortValue(item.title).value
                XCTAssertLessThanOrEqual(lastKey, k)
                lastKey = k
            }
            walked += p.items.count
            cur = p.next
        } while cur != nil && walked < 5_000
        let c4k = try await store.count(ItemQuery(filter: fourK))
        let walkAll = try await store.count(ItemQuery())
        XCTAssertEqual(walkAll, totalItems)
        XCTAssertGreaterThan(c4k, 0)
        XCTAssertLessThan(c4k, totalItems)
        if n <= 10_000 {
            // Every filtered answer is checked row by row against the item's own fields.
            var matched = 0
            var c: ItemCursor?
            repeat {
                let p = try await store.page(ItemQuery(filter: combo), limit: 200, after: c)
                for i in p.items {
                    matched += 1
                    XCTAssertEqual(i.maxResolution, .uhd4k)
                    XCTAssertFalse(i.watch.watched)
                    XCTAssertGreaterThanOrEqual(i.rating ?? 0, 6)
                    XCTAssertTrue(i.hdrFormats.contains(.dolbyVision))
                    XCTAssertGreaterThanOrEqual(i.maxChannels ?? 0, 6)
                    XCTAssertTrue((1980...2010).contains(i.year ?? 0))
                }
                c = p.next
            } while c != nil
            let counted = try await store.count(ItemQuery(filter: combo))
            XCTAssertEqual(matched, counted)
        }

        // ---- Size on disk
        try await store.checkpoint()
        let size = (try? FileManager.default.attributesOfItem(atPath: dbPath)[.size] as? Int) ?? 0
        let wal = (try? FileManager.default.attributesOfItem(atPath: dbPath + "-wal")[.size] as? Int) ?? 0
        PerfLog.line("\(n): database file \(String(format: "%.1f", Double(size) / 1_048_576)) MB (\(size / max(totalItems, 1)) bytes per item; WAL after checkpoint \(wal) bytes)")
        try await expectEqual(try await store.integrityCheck(), "ok")
        PerfLog.line("\(n): peak process RSS at the end \((ProcessMemory.peakKB ?? 0) / 1024) MB")
    }
}
