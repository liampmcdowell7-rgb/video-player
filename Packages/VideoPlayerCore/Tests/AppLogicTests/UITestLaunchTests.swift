import XCTest
import VideoPlayerCore
import LibraryIndex
@testable import AppLogic

/// The UI-test launch switch and the synthetic sample library (screenshots in CI). The sample library must never be
/// reachable in a Release build: the switch refuses when the build does not allow it, and every file that holds sample data
/// is wrapped in `#if DEBUG` (checked below by reading the files).
final class UITestLaunchTests: XCTestCase {
    #if DEBUG // the switch exists only in debug builds (tests are built debug)
    // MARK: The switch

    func testAReleaseBuildNeverTurnsAUITestModeOn() {
        for args in [["app", "-UITestFixtures"], ["app", "-UITestEmpty"], ["app", "-UITestFixtures", "-UITestEmpty", "-UITestTab", "movies"]] {
            XCTAssertEqual(UITestLaunch.mode(arguments: args, buildAllowsUITestModes: false), .off, "\(args)")
        }
        XCTAssertNil(UITestLaunch.value(of: UITestLaunch.tabArgument, arguments: ["app", "-UITestTab", "movies"], mode: .off))
    }

    func testADebugBuildReadsTheArguments() {
        XCTAssertEqual(UITestLaunch.mode(arguments: ["app"], buildAllowsUITestModes: true), .off)
        XCTAssertEqual(UITestLaunch.mode(arguments: ["app", "-UITestEmpty"], buildAllowsUITestModes: true), .empty)
        XCTAssertEqual(UITestLaunch.mode(arguments: ["app", "-UITestFixtures"], buildAllowsUITestModes: true), .fixtures)
        XCTAssertEqual(UITestLaunch.mode(arguments: ["app", "-UITestEmpty", "-UITestFixtures"], buildAllowsUITestModes: true), .fixtures)
        let args = ["app", "-UITestFixtures", "-UITestTab", "movies", "-UITestOpen", "Sample Movie 1"]
        XCTAssertEqual(UITestLaunch.value(of: UITestLaunch.tabArgument, arguments: args, mode: .fixtures), "movies")
        XCTAssertEqual(UITestLaunch.value(of: UITestLaunch.openArgument, arguments: args, mode: .fixtures), "Sample Movie 1")
        XCTAssertNil(UITestLaunch.value(of: UITestLaunch.tabArgument, arguments: ["app", "-UITestTab"], mode: .fixtures))
        XCTAssertNil(UITestLaunch.value(of: UITestLaunch.tabArgument, arguments: ["app", "-UITestTab", "-UITestEmpty"], mode: .empty))
    }

    /// Rule 17 screenshots: Larger Text and Bold Text are drawn by the app itself in UI-test mode, and only there.
    func testTheAccessibilityVariantsAreReadOnlyInAUITestMode() {
        let args = ["app", "-UITestFixtures", "-UITestTextSize", "accessibility3", "-UITestBoldText"]
        XCTAssertEqual(UITestLaunch.textSize(arguments: args, mode: .fixtures), "accessibility3")
        XCTAssertTrue(UITestLaunch.boldText(arguments: args, mode: .fixtures))
        XCTAssertNil(UITestLaunch.textSize(arguments: args, mode: .off))
        XCTAssertFalse(UITestLaunch.boldText(arguments: args, mode: .off))
        XCTAssertNil(UITestLaunch.textSize(arguments: ["app", "-UITestEmpty", "-UITestTextSize", "huge"], mode: .empty), "unknown size")
        XCTAssertFalse(UITestLaunch.boldText(arguments: ["app", "-UITestEmpty"], mode: .empty))
    }
    #endif

    /// Every file that holds sample data, the launch-argument texts or reads the switch starts with `#if DEBUG` and ends with `#endif`, so a Release build
    /// does not contain it. The repo is found through VP_PROJECT_ROOT (scripts/test-core.sh sets it, because it copies only
    /// the package before building) or next to this test file (Packages/VideoPlayerCore in a checkout), as in NamesTests.
    func testEverySampleDataFileIsCompiledOnlyInDebugBuilds() throws {
        var candidates: [URL] = []
        if let root = ProcessInfo.processInfo.environment["VP_PROJECT_ROOT"], !root.isEmpty {
            candidates.append(URL(fileURLWithPath: root))
        }
        candidates.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
        let found = candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("App").path) }
        #if !os(Linux)
        // In a tvOS Simulator run the checkout may not be readable (CI sets TEST_RUNNER_VP_PROJECT_ROOT): skipped, never passed.
        if found == nil { throw XCTSkip("the repository (with App/) is not readable from this test host") }
        #endif
        let repo = try XCTUnwrap(found, "the repository (with App/) was not found")
        let package = repo.appendingPathComponent("Packages/VideoPlayerCore")
        let guarded = [
            package.appendingPathComponent("Sources/AppLogic/UITestFixtures.swift"),
            package.appendingPathComponent("Sources/AppLogic/UITestLaunch.swift"),
            package.appendingPathComponent("Sources/AppLogic/UITestFixtureDetails.swift"),
            repo.appendingPathComponent("App/Support/UITestMode.swift"),
        ]
        for url in guarded {
            let text = try String(contentsOf: url, encoding: .utf8)
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
            XCTAssertEqual(lines.first, "#if DEBUG", url.lastPathComponent)
            XCTAssertEqual(lines.last, "#endif", url.lastPathComponent)
            // One block only: no `#endif` before the end that would let code after it into a Release build.
            XCTAssertEqual(lines.filter { $0.hasPrefix("#endif") }.count, lines.filter { $0.hasPrefix("#if") }.count, url.lastPathComponent)
        }
    }

    #if DEBUG // the sample library exists only in debug builds (tests are built debug)
    // MARK: Sample library content

    /// D7: Show 1's episodes carry invented titles the parser reads; Show 2 is the item with missing data (no titles,
    /// no poster, no fan art).
    func testShowOneHasEpisodeTitlesAndShowTwoHasMissingData() {
        let files = UITestFixtures.files().keys
        let one = UITestFixtures.shows[0].folder, two = UITestFixtures.shows[1].folder
        let titles = files.filter { $0.hasPrefix(one + "/Season") }.compactMap {
            FilenameParser.parse(fileName: ($0 as NSString).lastPathComponent).episodeTitle
        }
        XCTAssertEqual(titles.count, 7, "\(titles)")
        XCTAssertTrue(titles.contains { $0.count > 60 }, "one title longer than any card")
        let twoEpisodes = files.filter { $0.hasPrefix(two + "/Season") }
        XCTAssertEqual(twoEpisodes.count, 3)
        XCTAssertTrue(twoEpisodes.allSatisfy { FilenameParser.parse(fileName: ($0 as NSString).lastPathComponent).episodeTitle == nil })
        XCTAssertFalse(files.contains(two + "/poster.png"))
        XCTAssertFalse(files.contains(two + "/fanart.png"))
    }

    func testTheSampleLibraryUsesOnlyGenericNames() {
        let allowed = try! NSRegularExpression(pattern:
            // "( [A-Za-z]+)*": plain words after the number, for the long-title fixture (#17 C). "( - [A-Z][a-z]*( [a-z]+)*)?":
            // an invented sentence-case episode title (D7): one capital letter, then lower-case words only.
            #"^(Movies|Shows|Season \d+|poster\.png|fanart\.png|clearlogo\.png|Sample (Movie|Show) \d+( [A-Za-z]+)*( \(\d{4}\))?( - S\d\dE\d\d( - [A-Z][a-z]*( [a-z]+)*)?)?( - )?( ?(2160p|1080p|720p))?(\.en)?\.(mkv|mp4|srt|sup))$|^Sample (Movie|Show) \d+( [A-Za-z]+)*( \(\d{4}\))?$|^Unsorted$|^Sample (Clip|Unsorted [A-Za-z0-9 -]+)\.(mkv|mp4|m4v)$"#)
        for path in UITestFixtures.files().keys {
            for part in path.split(separator: "/") {
                let s = String(part)
                XCTAssertNotNil(allowed.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), "unexpected name: \(s)")
            }
        }
        XCTAssertEqual(UITestFixtures.sourceName, "Sample Library")
        XCTAssertEqual(UITestFixtures.serverDefinition.name, "Sample Server")
        XCTAssertTrue(UITestFixtures.serverDefinition.host.hasSuffix(".invalid"), "never resolves, so it can never be contacted")
        XCTAssertEqual(UITestFixtures.serverDefinition.auth, "none", "no password gap is shown for it")
    }

    /// Addendum #18 B: at least 8 Needs Review files, one very long name and one with no year, all ending in Needs Review
    /// through the real scan, and none in Movies or Shows.
    func testTheSampleLibraryHasNeedsReviewFiles() async throws {
        XCTAssertGreaterThanOrEqual(UITestFixtures.review.count, 8)
        let names = UITestFixtures.review.map { ($0 as NSString).lastPathComponent }
        XCTAssertTrue(names.contains { $0.count > 100 }, "one very long file name")
        XCTAssertTrue(names.contains("Sample Unsorted Recital.mkv"), "one with no year")
        let store = try SQLiteLibraryStore(path: ":memory:")
        try await UITestFixtures.seed(into: store, now: Date(timeIntervalSince1970: 1_780_000_000))
        let review = try await store.needsReview(limit: 100)
        XCTAssertEqual(Set(review.map(\.fileName)), Set(names))
        let count = try await store.needsReviewCount()
        XCTAssertEqual(count, UITestFixtures.review.count)
        let items = try await UITestFixtures.allItems(store)
        XCTAssertFalse(items.contains { $0.title.contains("Unsorted") || $0.title == "Sample Clip" }, "never in Movies or Shows")
    }

    func testThePicturesAreValidPNGFilesOfTheRightSize() throws {
        let png = GradientPNG.make(width: 24, height: 36, hue: 0.3)
        XCTAssertEqual(Array(png.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        // IHDR: length 13, type, width 24, height 36, and its CRC matches.
        XCTAssertEqual(Array(png[8..<16]), [0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52])
        XCTAssertEqual(Array(png[16..<24]), [0, 0, 0, 24, 0, 0, 0, 36])
        let crc = GradientPNG.crc32(png.subdata(in: 12..<29))
        XCTAssertEqual(Array(png[29..<33]), Array(GradientPNG.be32(crc)))
        XCTAssertEqual(Array(png.suffix(12)), [0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])
        // Known CRC-32 check value ("123456789" gives CBF43926).
        XCTAssertEqual(GradientPNG.crc32(Data("123456789".utf8)), 0xCBF4_3926)
    }

    func testSeedingFillsTheLibraryThroughTheRealScan() async throws {
        let store = try SQLiteLibraryStore(path: ":memory:")
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        try await UITestFixtures.seed(into: store, now: now)
        let items = try await UITestFixtures.allItems(store)
        let movies = items.filter { $0.kind == .movie }
        let episodes = items.filter { $0.kind == .episode }
        XCTAssertEqual(movies.count, 7, "\(movies.map(\.title))")
        // #17 C: the long-title fixture is scanned with its whole title (rule S1 decides how it is shown, never the data).
        XCTAssertTrue(movies.contains { $0.title == "Sample Movie 7 With A Much Longer Title Than Any Card Is Wide" }, "\(movies.map(\.title))")
        XCTAssertEqual(episodes.count, 10, "\(episodes.map(\.title))")
        XCTAssertTrue(items.allSatisfy { $0.title.hasPrefix("Sample") || ($0.seriesTitle ?? "").hasPrefix("Sample") }, "\(items.map(\.title))")

        // Two versions of Sample Movie 2, the 4K one first.
        let two = try XCTUnwrap(movies.first { $0.title == "Sample Movie 2" }, "\(movies.map(\.title))")
        XCTAssertEqual(two.versionCount, 2)
        XCTAssertEqual(two.watch.watched, true)

        // Real format names in the detail page's version row.
        let one = try XCTUnwrap(movies.first { $0.title == "Sample Movie 1" })
        var detail = ItemDetailViewModel(store: store, itemID: one.id)
        await detail.load()
        guard case .loaded(let content) = detail.state else { return XCTFail("detail did not load: \(detail.state)") }
        let row = try XCTUnwrap(content.versions.first?.detail)
        XCTAssertTrue(row.contains("HEVC"), row)
        XCTAssertTrue(row.contains("Dolby Vision"), row)
        XCTAssertTrue(row.contains("Dolby TrueHD with Dolby Atmos"), row)
        XCTAssertEqual(content.playTitle, "Resume")
        // The two subtitle files; poster.png and fanart.png are the item's artwork, not extras.
        XCTAssertEqual(content.extras.map(\.name).sorted(), ["Sample Movie 1 (2021) 2160p.en.srt", "Sample Movie 1 (2021) 2160p.en.sup"])

        // Continue Watching has the half-watched movies and the started episode.
        let continuing = try await store.continueWatching(limit: 20, now: now, retentionDays: 90)
        XCTAssertEqual(Set(continuing.map(\.title)).isSuperset(of: ["Sample Movie 1", "Sample Movie 4"]), true, "\(continuing.map(\.title))")
        XCTAssertTrue(continuing.contains { $0.kind == .episode }, "\(continuing.map(\.title))")
        XCTAssertTrue(movies.contains { $0.watch.favorite })

        // #21 D: the fake synopsis and cast, found by the page's artwork key like the online path.
        let withDetails = await UITestFixtureDetails.details(key: "item-\(one.id)", store: store)
        let oneDetails = try XCTUnwrap(withDetails)
        XCTAssertEqual(oneDetails.overview?.filter { $0 == "." }.count, 3, "three sentences")
        XCTAssertFalse(oneDetails.cast.isEmpty)
        XCTAssertEqual(UITestFixtureDetails.details(forTitle: "Sample Movie 2")?.cast.count, TitleDetails.castLimit)
        XCTAssertGreaterThan(UITestFixtureDetails.details(forTitle: "Sample Movie 4")?.overview?.count ?? 0, 1000, "the very long synopsis")
        XCTAssertNil(UITestFixtureDetails.details(forTitle: "Sample Movie 6"), "the page with neither")
        let episodeKey = await UITestFixtureDetails.details(key: "item-\(try XCTUnwrap(episodes.first).id)", store: store)
        XCTAssertNil(episodeKey, "movies only, like the online path")
        for title in movies.map(\.title) {
            let d = UITestFixtureDetails.details(forTitle: title)
            XCTAssertTrue(d.map { ($0.overview ?? UITestFixtureDetails.marker).hasPrefix(UITestFixtureDetails.marker) } ?? true,
                          "every fake text carries the marker the Release check looks for")
            XCTAssertTrue(d?.cast.allSatisfy { $0.name.hasPrefix("Sample Actor") } ?? true)
        }
    }

    func testTheSampleSourceRefusesToReadAVideo() async throws {
        let source = FixtureSource()
        let root = try await source.list("/")
        XCTAssertEqual(root.map(\.name), ["Movies", "Shows", "Unsorted"])
        let poster = try await source.read("/Movies/Sample Movie 1 (2021)/poster.png", range: ByteRange(offset: 0, length: 8))
        XCTAssertEqual(Array(poster), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        do {
            _ = try await source.read("/Movies/Sample Movie 1 (2021)/Sample Movie 1 (2021) 2160p.mkv", range: ByteRange(offset: 0, length: 16))
            XCTFail("reading a sample video must fail")
        } catch let error as SourceError {
            XCTAssertEqual(error, .unsupported(FixtureSource.noVideo))
        }
    }
    #endif
}
