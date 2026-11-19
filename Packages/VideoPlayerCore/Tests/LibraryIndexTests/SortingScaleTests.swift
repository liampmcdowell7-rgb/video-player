import XCTest
import VideoPlayerCore
@testable import LibraryIndex

/// Addendum #18 F: the cost of sorting a whole library, measured on a synthetic 10,000-file library (synthetic names only).
/// Each test prints its time ("SORT-TIMING ...") so the run log holds the number, and fails when it is over its time box.
/// The boxes are several times the times measured on the Linux test machine in a Debug build (docs/SORTING.md), so a
/// slower machine does not fail them but a change that makes sorting many times slower does. An Apple TV is not measured
/// here (DEVICE_TEST_CHECKLIST_SORTING.md).
final class SortingScaleTests: XCTestCase {
    static let fileCount = 10_000

    /// 10,000 video paths in 250 folders of 40: shows in season folders, movies in their own folders, and flat mixed folders
    /// (episodes, movies and names that end in Needs Review side by side).
    static func library() -> [String] {
        var paths: [String] = []
        paths.reserveCapacity(fileCount)
        var n = 0
        func two(_ v: Int) -> String { v < 10 ? "0\(v)" : "\(v)" }
        while paths.count < fileCount {
            switch n % 3 {
            case 0:
                let show = "Sample Show \(n)"
                for e in 1...40 { paths.append("/Shows/\(show)/Season \(1 + e / 20)/\(show) - S\(two(1 + e / 20))E\(two(e)).mkv") }
            case 1:
                for m in 0..<40 {
                    let title = "Sample Movie \(n)-\(m)"
                    paths.append("/Movies/\(title) (\(1950 + (n + m) % 70))/\(title) (\(1950 + (n + m) % 70)) 1080p.mkv")
                }
            default:
                for m in 0..<40 {
                    switch m % 4 {
                    case 0: paths.append("/Mixed \(n)/Sample.Flat.Show.\(n).S01E\(two(m / 4 + 1)).720p.mkv")
                    case 1: paths.append("/Mixed \(n)/Sample Flat Movie \(n)-\(m) \(1960 + m).mkv")
                    case 2: paths.append("/Mixed \(n)/Sample Unsorted \(n) Part Of Day \(m).mkv")
                    default: paths.append("/Mixed \(n)/sample home video \(n) \(m).mp4")
                    }
                }
            }
            n += 1
        }
        return Array(paths.prefix(fileCount))
    }

    static func seconds(_ start: UInt64) -> Double { Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000 }

    func testTheLibraryHasTenThousandFiles() {
        let paths = Self.library()
        XCTAssertEqual(paths.count, Self.fileCount)
        XCTAssertEqual(Set(paths).count, Self.fileCount)
    }

    /// The classifier alone (MediaSorter.decide and the grouping key) for every file, with each folder's sibling index.
    func testSortingTenThousandFilesStaysWithinItsTimeBox() {
        let paths = Self.library()
        let byFolder = Dictionary(grouping: paths) { LibraryPath.parent(of: $0) }
        let start = DispatchTime.now().uptimeNanoseconds
        var counts: [SortOutcome: Int] = [:]
        for (folder, files) in byFolder {
            let names = files.map { ($0 as NSString).lastPathComponent }
            let siblings = SiblingIndex(names: names)
            let ancestors = LibraryPath.ancestorNames(of: folder + "/x")
            // Once per folder, as LibrarySyncer.scanFolder does.
            let ancestorInfos = ancestors.map(FilenameParser.parseFolderName)
            for name in names {
                let d = MediaSorter.decide(fileName: name, context: SortContext(folders: ancestors, folderInfos: ancestorInfos, siblings: siblings))
                _ = ItemGrouping.seed(parsed: d.parsed, fileName: name)
                counts[d.outcome, default: 0] += 1
            }
        }
        let elapsed = Self.seconds(start)
        print("SORT-TIMING classifier \(Self.fileCount) files: \(String(format: "%.3f", elapsed)) s; \(counts.map { "\($0.key.rawValue) \($0.value)" }.sorted().joined(separator: ", "))")
        XCTAssertEqual(counts.values.reduce(0, +), Self.fileCount)
        XCTAssertGreaterThan(counts[.needsReview] ?? 0, 0, "the library has files that end in Needs Review")
        // The same decisions as before the speed-up of addendum #19 A (measured on the old code).
        XCTAssertEqual(counts, [.episode: 4190, .movie: 4150, .needsReview: 1660])
        XCTAssertLessThan(elapsed, Self.classifierBox, "sorting 10,000 file names took \(elapsed) s")
    }

    /// Addendum #19 A: where the time goes. Each stage runs over all 10,000 files on its own and prints its time, so the
    /// log shows which one dominates. Only the totals are asserted (each stage is part of the classifier box above).
    func testSortingStageTimes() {
        let paths = Self.library()
        let names = paths.map { ($0 as NSString).lastPathComponent }
        let byFolder = Dictionary(grouping: paths) { LibraryPath.parent(of: $0) }
        func time(_ label: String, _ body: () -> Void) -> Double {
            let start = DispatchTime.now().uptimeNanoseconds
            body()
            let t = Self.seconds(start)
            print("SORT-STAGE \(label): \(String(format: "%.3f", t)) s (\(String(format: "%.3f", t * 1000 / Double(Self.fileCount))) ms per file)")
            return t
        }
        var sink = 0
        _ = time("name normalisation (LibraryText.normalize)") { for n in names { sink &+= LibraryText.normalize(n).count } }
        _ = time("pattern matching, file name only (FilenameParser.parse)") { for n in names { sink &+= FilenameParser.parse(fileName: n).title.count } }
        _ = time("folder names (parseFolderName, each folder of each file)") {
            for p in paths { for f in LibraryPath.ancestorNames(of: p) { sink &+= FilenameParser.parseFolderName(f).title.count } }
        }
        _ = time("sibling index (once per folder)") { for (_, files) in byFolder { sink &+= SiblingIndex(names: files.map { ($0 as NSString).lastPathComponent }).marked.count } }
        var decisions: [(SortDecision, String)] = []
        decisions.reserveCapacity(Self.fileCount)
        let siblings = byFolder.mapValues { SiblingIndex(names: $0.map { ($0 as NSString).lastPathComponent }) }
        _ = time("decision (MediaSorter.decide, siblings ready)") {
            for p in paths {
                let folder = LibraryPath.parent(of: p)
                let name = (p as NSString).lastPathComponent
                decisions.append((MediaSorter.decide(fileName: name, context: SortContext(folders: LibraryPath.ancestorNames(of: p), siblings: siblings[folder]!)), name))
            }
        }
        _ = time("grouping (ItemGrouping.seed)") { for (d, n) in decisions { sink &+= ItemGrouping.seed(parsed: d.parsed, fileName: n).key.count } }
        XCTAssertGreaterThan(sink, 0)
        XCTAssertEqual(decisions.count, Self.fileCount)
    }

    /// The one-time re-sort of an existing library: a first scan, then every sort record dropped (what the upgrade looks like)
    /// and one more scan, which sorts every file again and writes it.
    func testTheOneTimeResortOfTenThousandFilesStaysWithinItsTimeBox() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        for (i, path) in Self.library().enumerated() { h.source.put(path, size: Int64(1_000 + i)) }
        let firstStart = DispatchTime.now().uptimeNanoseconds
        let first = try await h.syncer.sync()
        let firstTime = Self.seconds(firstStart)
        XCTAssertEqual(first.progress.added, Self.fileCount)

        try await h.store.forgetSortRecords()
        let start = DispatchTime.now().uptimeNanoseconds
        let resort = try await h.syncer.sync()
        let elapsed = Self.seconds(start)
        print("SORT-TIMING first scan \(Self.fileCount) files: \(String(format: "%.3f", firstTime)) s; one-time re-sort: \(String(format: "%.3f", elapsed)) s (\(resort.progress.changed) files rewritten)")
        XCTAssertEqual(resort.progress.changed, Self.fileCount)
        XCTAssertLessThan(elapsed, Self.resortBox, "the one-time re-sort of 10,000 files took \(elapsed) s")
    }

    /// Measured 2026-11-18 on the Linux test machine.
    /// Before addendum #19 A (55 patterns compiled on every parse, each name parsed up to 6 times): Debug classifier 47.9 to
    /// 50.9 s, re-sort 55.8 to 58.1 s; Release classifier 45.8 s, re-sort 44.4 s.
    /// After: Debug classifier 8.1 s (0.81 ms per file), re-sort 13.3 to 13.4 s; Release classifier 7.1 s, re-sort 12.8 s.
    /// Boxes are about 3x the Debug times, so a real regression fails.
    static let classifierBox = 25.0
    static let resortBox = 40.0
}
