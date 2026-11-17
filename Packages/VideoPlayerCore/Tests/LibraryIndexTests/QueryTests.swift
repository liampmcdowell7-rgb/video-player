import XCTest
import VideoPlayerCore
@testable import LibraryIndex

/// A catalogue with exactly known attributes, so every filter and sort can be checked against a plain Swift model.
struct Movie {
    var title: String
    var year: Int
    var rating: Double
    var genres: [String]
    var resolution: ResolutionClass
    var hdr: Set<HDRFormat>
    var dvProfile: Int?
    var channels: Int
    var atmos: Bool
    var container: ContainerFormat
    var added: Date
    var runtime: Double
    var favorite = false
    var watched = false
    var progress = false
    var lastPlayed: Date?
    var id: Int64 = 0

    var fileName: String { year > 0 ? "\(title) (\(year)).\(ext)" : "\(title).\(ext)" }
    var ext: String {
        switch container {
        case .mkv: return "mkv"
        case .mp4: return "mp4"
        case .m4v: return "m4v"
        case .avi: return "avi"
        case .ts: return "ts"
        default: return "mov"
        }
    }
    var allHDR: Set<HDRFormat> { dvProfile != nil ? hdr.union([.dolbyVision]) : hdr }
    var inProgress: Bool { progress && !watched }

    var technical: FileTechnicalInfo {
        let size: (Int, Int)
        switch resolution {
        case .uhd4k: size = (3840, 2160)
        case .hd1080: size = (1920, 1080)
        case .hd720: size = (1280, 720)
        case .sd: size = (720, 480)
        }
        return FileTechnicalInfo(
            duration: runtime, container: container, width: size.0, height: size.1, hdrFormats: hdr, dolbyVisionProfile: dvProfile,
            audioChannels: channels, hasAtmos: atmos
        )
    }
}

struct Fixture {
    var movies: [Movie]
    let h: Harness

    static let adjectives = ["Silent", "Golden", "Broken", "Hidden", "Crimson", "Distant", "Frozen", "Electric", "Hollow", "Lucky", "Midnight", "Rapid"]
    static let nouns = ["River", "Harbor", "Garden", "Engine", "Mirror", "Orchard", "Signal", "Tower", "Valley", "Winter", "Bridge", "Canyon", "Desert", "Forest", "Island", "Lantern", "Meadow", "Planet", "Quarry", "Summit"]
    static let genreNames = ["Drama", "Comedy", "Action", "Horror", "Sci-Fi", "Documentary"]

    static func build(seed: UInt64 = 42, count: Int = 240) async throws -> Fixture {
        var rng = LCG(seed)
        var movies: [Movie] = []
        for i in 0..<count {
            let res = [ResolutionClass.sd, .hd720, .hd1080, .hd1080, .uhd4k][rng.int(5)]
            var hdr: Set<HDRFormat> = []
            var dv: Int?
            if res == .uhd4k {
                for f in [HDRFormat.hdr10, .hdr10Plus, .hlg] where rng.chance(35) { hdr.insert(f) }
                if rng.chance(40) { dv = [5, 7, 8][rng.int(3)] }
            }
            let channels = [2, 2, 6, 8][rng.int(4)]
            movies.append(Movie(
                title: "\(adjectives[i % adjectives.count]) \(nouns[(i / adjectives.count) % nouns.count])",
                year: rng.chance(5) ? 0 : 1960 + rng.int(65), rating: rng.chance(10) ? 0 : Double(rng.int(91)) / 10,
                genres: (0..<rng.int(3)).map { _ in genreNames[rng.int(genreNames.count)] }, resolution: res, hdr: hdr, dvProfile: dv,
                channels: channels, atmos: channels == 8 && rng.chance(50), container: [.mkv, .mkv, .mp4, .m4v, .avi, .ts][rng.int(6)],
                added: day(Double(rng.int(90))), runtime: Double(3_000 + rng.int(6_000)),
                favorite: rng.chance(8), watched: rng.chance(25), progress: rng.chance(10), lastPlayed: nil
            ))
        }
        // Titles that exercise sorting and searching.
        let extras = ["The Zebra Crossing", "An Orchard Tale", "1917", "300", "Amélie", "Alpha"]
        for (i, t) in extras.enumerated() {
            movies.append(Movie(
                title: t, year: 2000 + i, rating: 5 + Double(i), genres: ["Drama"], resolution: .hd1080, hdr: [], dvProfile: nil, channels: 6,
                atmos: false, container: .mkv, added: day(Double(10 + i)), runtime: 6_000
            ))
        }
        for i in movies.indices { movies[i].lastPlayed = (movies[i].watched || movies[i].progress) ? day(40 + Double(rng.int(55))) : nil }

        let table = Dictionary(uniqueKeysWithValues: movies.map { ($0.fileName, $0.technical) })
        let h = try Harness.make(annotator: TableAnnotator(table: table))
        for m in movies { h.source.put("/Lib/" + m.fileName, size: 5_000_000_000, modified: m.added) }
        try await h.syncer.sync()

        let items = try await h.store.page(ItemQuery(), limit: 10_000, offset: 0)
        precondition(items.count == movies.count, "scan found \(items.count) of \(movies.count)")
        var byTitle: [String: Int64] = [:]
        for item in items { byTitle[LibraryText.normalize(item.title)] = item.id }
        var batch: [(itemID: Int64, metadata: ItemMetadata)] = []
        for i in movies.indices {
            guard let id = byTitle[LibraryText.normalize(movies[i].title)] else { preconditionFailure("no item for \(movies[i].title)") }
            movies[i].id = id
            batch.append((id, ItemMetadata(rating: movies[i].rating, genres: movies[i].genres)))
        }
        try await h.store.setMetadata(batch: batch)
        for m in movies {
            if m.favorite { try await h.store.setFavorite(itemID: m.id, favorite: true) }
            if m.watched, let d = m.lastPlayed { try await h.store.markWatched(itemIDs: [m.id], watched: true, at: d) }
            if m.inProgress, let d = m.lastPlayed { try await h.store.updateProgress(itemID: m.id, position: 120, duration: 6_000, at: d) }
        }
        return Fixture(movies: movies, h: h)
    }

    /// The plain-Swift definition of every filter.
    func matches(_ m: Movie, _ f: ItemFilter) -> Bool {
        if !f.kinds.isEmpty, !f.kinds.contains(.movie) { return false }
        if !f.genres.isEmpty, !m.genres.contains(where: { g in f.genres.contains { $0.lowercased() == g.lowercased() } }) { return false }
        if let y = f.yearMin, !(m.year > 0 && m.year >= y) { return false }
        if let y = f.yearMax, !(m.year > 0 && m.year <= y) { return false }
        if let r = f.minRating, !(m.rating > 0 && m.rating >= r) { return false }
        switch f.watch {
        case .unwatched?: if m.watched { return false }
        case .watched?: if !m.watched { return false }
        case .inProgress?: if !m.inProgress { return false }
        case nil: break
        }
        if !f.resolutions.isEmpty, !f.resolutions.contains(m.resolution) { return false }
        if !f.hdrFormats.isEmpty, m.allHDR.isDisjoint(with: f.hdrFormats) { return false }
        if let dv = f.dolbyVision, m.allHDR.contains(.dolbyVision) != dv { return false }
        if !f.dolbyVisionProfiles.isEmpty, !(m.dvProfile.map { f.dolbyVisionProfiles.contains($0) } ?? false) { return false }
        if let a = f.dolbyAtmos, m.atmos != a { return false }
        if let c = f.minChannels, m.channels < c { return false }
        if !f.containers.isEmpty, !f.containers.contains(m.container) { return false }
        if let d = f.addedAfter, m.added < d { return false }
        if f.favoritesOnly, !m.favorite { return false }
        if let text = f.text {
            let title = LibraryText.normalize(m.title)
            for w in LibraryText.normalize(text).split(separator: " ") where !title.contains(w) { return false }
        }
        return true
    }

    func order(_ list: [Movie], _ sort: ItemSort) -> [Int64] {
        func value(_ m: Movie) -> (String, Double) {
            switch sort.key {
            case .title: return (LibraryText.titleSortValue(m.title).value, 0)
            case .year: return ("", Double(m.year))
            case .rating: return ("", m.rating)
            case .added: return ("", m.added.timeIntervalSince1970)
            case .lastPlayed: return ("", m.lastPlayed?.timeIntervalSince1970 ?? 0)
            case .runtime: return ("", m.runtime)
            }
        }
        let sorted = list.sorted { a, b in
            let x = value(a), y = value(b)
            if x.0 != y.0 { return sort.ascending ? x.0 < y.0 : x.0 > y.0 }
            if x.1 != y.1 { return sort.ascending ? x.1 < y.1 : x.1 > y.1 }
            return sort.ascending ? a.id < b.id : a.id > b.id
        }
        return sorted.map(\.id)
    }

    func randomFilter(_ rng: inout LCG) -> ItemFilter {
        var f = ItemFilter()
        if rng.chance(20) { f.genres = Set((0...rng.int(2)).map { _ in Self.genreNames[rng.int(Self.genreNames.count)] }) }
        if rng.chance(20) { f.yearMin = 1960 + rng.int(60) }
        if rng.chance(20) { f.yearMax = 1980 + rng.int(45) }
        if rng.chance(20) { f.minRating = Double(rng.int(9)) }
        if rng.chance(30) { f.watch = [WatchFilter.unwatched, .watched, .inProgress][rng.int(3)] }
        if rng.chance(25) { f.resolutions = Set((0...rng.int(2)).map { _ in ResolutionClass.allCases[rng.int(4)] }) }
        if rng.chance(15) { f.hdrFormats = Set((0...rng.int(2)).map { _ in HDRFormat.allCases[1 + rng.int(4)] }) }
        if rng.chance(15) { f.dolbyVision = rng.chance(60) }
        if rng.chance(10) { f.dolbyVisionProfiles = [[5, 7, 8][rng.int(3)]] }
        if rng.chance(15) { f.dolbyAtmos = rng.chance(70) }
        if rng.chance(20) { f.minChannels = [2, 6, 8][rng.int(3)] }
        if rng.chance(20) { f.containers = Set((0...rng.int(2)).map { _ in [ContainerFormat.mkv, .mp4, .m4v, .avi, .ts][rng.int(5)] }) }
        if rng.chance(20) { f.addedAfter = day(Double(rng.int(90))) }
        if rng.chance(10) { f.favoritesOnly = true }
        if rng.chance(10) { f.text = Self.adjectives[rng.int(Self.adjectives.count)].lowercased() }
        return f
    }
}

final class QueryTests: XCTestCase {
    func testManyRandomFilterCombinationsMatchThePlainSwiftModel() async throws {
        let fx = try await Fixture.build()
        defer { fx.h.cleanup() }
        var rng = LCG(7)
        var nonEmpty = 0, multi = 0
        for round in 0..<300 {
            let f = fx.randomFilter(&rng)
            let expected = fx.movies.filter { fx.matches($0, f) }
            let got = try await fx.h.store.page(ItemQuery(filter: f), limit: 10_000, offset: 0)
            XCTAssertEqual(Set(ids(got)), Set(expected.map(\.id)), "round \(round) filter \(f)")
            let c = try await fx.h.store.count(ItemQuery(filter: f))
            XCTAssertEqual(c, expected.count, "round \(round)")
            if !expected.isEmpty { nonEmpty += 1 }
            let facets = [!f.genres.isEmpty, f.yearMin != nil, f.yearMax != nil, f.minRating != nil, f.watch != nil, !f.resolutions.isEmpty, !f.hdrFormats.isEmpty,
                          f.dolbyVision != nil, !f.dolbyVisionProfiles.isEmpty, f.dolbyAtmos != nil, f.minChannels != nil, !f.containers.isEmpty,
                          f.addedAfter != nil, f.favoritesOnly, f.text != nil].filter { $0 }.count
            if facets >= 3 { multi += 1 }
        }
        XCTAssertGreaterThan(nonEmpty, 150, "the random filters should mostly select something")
        XCTAssertGreaterThan(multi, 30, "many rounds combine three or more facets")
    }

    func testEverySortInBothDirectionsAndBothPagingStylesMatchesTheModel() async throws {
        let fx = try await Fixture.build()
        defer { fx.h.cleanup() }
        var rng = LCG(99)
        for key in ItemSortKey.allCases {
            for ascending in [true, false] {
                for round in 0..<6 {
                    var f = round == 0 ? ItemFilter() : fx.randomFilter(&rng)
                    if round % 2 == 1 { f.watch = nil }
                    let sort = ItemSort(key: key, ascending: ascending)
                    let expected = fx.order(fx.movies.filter { fx.matches($0, f) }, sort)
                    let query = ItemQuery(filter: f, sort: sort)

                    // Keyset pages of 17.
                    var keyset: [Int64] = []
                    var cursor: ItemCursor?
                    var pages = 0
                    repeat {
                        let page = try await fx.h.store.page(query, limit: 17, after: cursor)
                        keyset += ids(page.items)
                        cursor = page.next
                        pages += 1
                    } while cursor != nil && pages < 100
                    XCTAssertEqual(keyset, expected, "keyset \(key) asc=\(ascending) round \(round)")

                    // Offset pages of 23.
                    var offsetIDs: [Int64] = []
                    var offset = 0
                    while true {
                        let page = try await fx.h.store.page(query, limit: 23, offset: offset)
                        if page.isEmpty { break }
                        offsetIDs += ids(page)
                        offset += page.count
                    }
                    XCTAssertEqual(offsetIDs, expected, "offset \(key) asc=\(ascending) round \(round)")
                }
            }
        }
    }

    func testPageEdgesLimitZeroExactMultipleAndEmptyResults() async throws {
        let fx = try await Fixture.build(count: 20)
        defer { fx.h.cleanup() }
        let q = ItemQuery()
        let total = fx.movies.count
        let zero = try await fx.h.store.page(q, limit: 0, after: nil)
        XCTAssertTrue(zero.items.isEmpty)
        XCTAssertNil(zero.next)
        let all = try await fx.h.store.page(q, limit: total, after: nil)
        XCTAssertEqual(all.items.count, total)
        XCTAssertNil(all.next, "exactly one full page has no next page")
        let almost = try await fx.h.store.page(q, limit: total - 1, after: nil)
        XCTAssertNotNil(almost.next)
        let last = try await fx.h.store.page(q, limit: total - 1, after: almost.next)
        XCTAssertEqual(last.items.count, 1)
        XCTAssertNil(last.next)
        var none = ItemFilter()
        none.text = "zzzzqqq"
        let empty = try await fx.h.store.page(ItemQuery(filter: none), limit: 10, after: nil)
        XCTAssertTrue(empty.items.isEmpty)
        XCTAssertNil(empty.next)
        let beyond = try await fx.h.store.page(q, limit: 10, offset: 10_000)
        XCTAssertTrue(beyond.isEmpty)
    }

    func testAlphabetIndexPointsAtTheFirstItemOfEachLetter() async throws {
        let fx = try await Fixture.build()
        defer { fx.h.cleanup() }
        var rng = LCG(5)
        for round in 0..<12 {
            let f = round == 0 ? ItemFilter() : fx.randomFilter(&rng)
            for ascending in [true, false] {
                let query = ItemQuery(filter: f, sort: ItemSort(key: .title, ascending: ascending))
                let index = try await fx.h.store.alphabetIndex(query)
                let total = try await fx.h.store.count(query)
                XCTAssertEqual(index.map(\.count).reduce(0, +), total)
                XCTAssertEqual(index.first?.offset ?? 0, 0)
                let letters = index.map(\.letter)
                XCTAssertEqual(letters, ascending ? letters.sorted() : letters.sorted(by: >), "order \(round) asc=\(ascending)")
                var running = 0
                for entry in index {
                    XCTAssertEqual(entry.offset, running)
                    running += entry.count
                    let first = try await fx.h.store.page(query, limit: 1, offset: entry.offset).first
                    let key = LibraryText.sortKey(first?.title ?? "", dropArticle: true)
                    XCTAssertEqual(LibraryText.letter(forSortKey: key), entry.letter, "first item at offset \(entry.offset)")
                    let lastInGroup = try await fx.h.store.page(query, limit: 1, offset: entry.offset + entry.count - 1).first
                    XCTAssertEqual(LibraryText.letter(forSortKey: LibraryText.sortKey(lastInGroup?.title ?? "", dropArticle: true)), entry.letter)
                }
            }
        }
        let other = try await fx.h.store.alphabetIndex(ItemQuery(sort: ItemSort(key: .year)))
        XCTAssertTrue(other.isEmpty, "the jump index only exists for title order")
    }

    func testArticlesAreIgnoredAndNumbersSortBeforeLettersAndNaturally() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        for t in ["The Zebra Crossing (2001)", "An Orchard Tale (2002)", "1917 (2019)", "300 (2006)", "Apollo 13 (1995)", "Apollo 100 (2001)", "Amélie (2001)", "A Beta (2010)", "Zulu (1964)"] {
            h.source.put("/L/\(t).mkv", size: 1, modified: day(1))
        }
        try await h.syncer.sync()
        let all = try await h.store.page(ItemQuery(), limit: 20, offset: 0)
        // Numbers first (by value), then A to Z ignoring a leading "The", "A" or "An", digits inside names by value.
        XCTAssertEqual(titles(all), ["300", "1917", "Amélie", "Apollo 13", "Apollo 100", "A Beta", "An Orchard Tale", "The Zebra Crossing", "Zulu"])
        let index = try await h.store.alphabetIndex(ItemQuery())
        XCTAssertEqual(index.map(\.letter), ["#", "A", "B", "O", "Z"])
        XCTAssertEqual(index.map(\.count), [2, 3, 1, 1, 2])
        XCTAssertEqual(index.map(\.offset), [0, 2, 5, 6, 7])
    }

    func testSearchIgnoresCaseAccentsAndWordOrder() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        for t in ["Amélie (2001)", "The Silent River (1999)", "River Of No Return (1954)", "Silent Hill (2006)"] { h.source.put("/L/\(t).mkv", size: 1, modified: day(1)) }
        try await h.syncer.sync()
        func search(_ text: String) async throws -> [String] {
            var f = ItemFilter()
            f.text = text
            return titles(try await h.store.page(ItemQuery(filter: f), limit: 10, offset: 0)).sorted()
        }
        let r1 = try await search("amelie"); XCTAssertEqual(r1, ["Amélie"])
        let r2 = try await search("AMÉLIE"); XCTAssertEqual(r2, ["Amélie"])
        let r3 = try await search("river silent"); XCTAssertEqual(r3, ["The Silent River"])
        let r4 = try await search("sil"); XCTAssertEqual(r4, ["Silent Hill", "The Silent River"])
        let r5 = try await search("  river  "); XCTAssertEqual(r5, ["River Of No Return", "The Silent River"])
        let r6 = try await search("nothing here"); XCTAssertEqual(r6, [])
        let r7 = try await search("100%_"); XCTAssertEqual(r7, [], "wildcard characters are ordinary text")
        let r8 = try await search(""); XCTAssertEqual(r8.count, 4, "empty text means no text filter")
    }

    func testSearchMatchesSeriesTitleForEpisodes() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        h.source.put("/TV/Breaking Trail/Season 1/Breaking Trail - S01E01 - Opening.mkv", size: 1, modified: day(1))
        try await h.syncer.sync()
        var f = ItemFilter()
        f.text = "trail opening"
        let r = try await h.store.page(ItemQuery(filter: f), limit: 5, offset: 0)
        XCTAssertEqual(titles(r), ["Opening"])
        f.text = "breaking"
        let n = try await h.store.count(ItemQuery(filter: f))
        XCTAssertEqual(n, 1)
    }

    func testFiltersUseTheBestOfAllVersionsOfAnItem() async throws {
        let table: [String: FileTechnicalInfo] = [
            "Dune (2021) 1080p.mkv": FileTechnicalInfo(container: .mkv, width: 1920, height: 1080, audioChannels: 8, hasAtmos: true),
            "Dune (2021) 2160p.mp4": FileTechnicalInfo(container: .mp4, width: 3840, height: 2160, hdrFormats: [.hdr10], dolbyVisionProfile: 8, audioChannels: 6),
        ]
        let h = try Harness.make(annotator: TableAnnotator(table: table))
        defer { h.cleanup() }
        h.source.put("/L/Dune (2021) 1080p.mkv", size: 10, modified: day(1))
        h.source.put("/L/Dune (2021) 2160p.mp4", size: 30, modified: day(2))
        try await h.syncer.sync()
        let dune = try await unwrap(try await h.store.page(ItemQuery(), limit: 1, offset: 0).first)
        XCTAssertEqual(dune.versionCount, 2)
        XCTAssertEqual(dune.maxResolution, .uhd4k)
        XCTAssertEqual(dune.hdrFormats, [.hdr10, .dolbyVision])
        XCTAssertEqual(dune.dolbyVisionProfiles, [8])
        XCTAssertEqual(dune.maxChannels, 8)
        XCTAssertTrue(dune.hasAtmos)
        XCTAssertEqual(dune.containers, [.mkv, .mp4])
        var f = ItemFilter()
        f.resolutions = [.hd1080]
        let c1 = try await h.store.count(ItemQuery(filter: f)); XCTAssertEqual(c1, 0, "resolution means the best version's resolution")
        f.resolutions = [.uhd4k]; f.dolbyAtmos = true; f.dolbyVisionProfiles = [8]
        let c2 = try await h.store.count(ItemQuery(filter: f)); XCTAssertEqual(c2, 1, "attributes are matched across versions")
        XCTAssertEqual(dune.runtime, nil)
    }

    func testFolderScopeSeriesAndSeasonFilters() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        basicLibrary(h.source)
        h.source.put("/Movies/Heat (1995)/Extras/Heat (1995) 480p.mkv", size: 1, modified: day(1))
        try await h.syncer.sync()
        func count(_ scope: FolderScope?, season: Int? = nil, series: Int64? = nil) async throws -> Int {
            var f = ItemFilter()
            f.folder = scope
            f.season = season
            f.seriesID = series
            return try await h.store.count(ItemQuery(filter: f))
        }
        let s = Harness.sourceID
        let whole = try await count(FolderScope(sourceID: s, path: "/")); XCTAssertEqual(whole, 4)
        let tv = try await count(FolderScope(sourceID: s, path: "/TV")); XCTAssertEqual(tv, 3)
        let season1 = try await count(FolderScope(sourceID: s, path: "/TV/Show One (2010)/Season 1", recursive: false)); XCTAssertEqual(season1, 2)
        let showDirect = try await count(FolderScope(sourceID: s, path: "/TV/Show One (2010)", recursive: false)); XCTAssertEqual(showDirect, 0)
        let showAll = try await count(FolderScope(sourceID: s, path: "/TV/Show One (2010)")); XCTAssertEqual(showAll, 3)
        let heatDirect = try await count(FolderScope(sourceID: s, path: "/Movies/Heat (1995)", recursive: false)); XCTAssertEqual(heatDirect, 1)
        let heatAll = try await count(FolderScope(sourceID: s, path: "/Movies/Heat (1995)")); XCTAssertEqual(heatAll, 1, "versions in sub folders belong to the same item")
        let other = try await count(FolderScope(sourceID: "nope", path: "/")); XCTAssertEqual(other, 0)
        let sibling = try await count(FolderScope(sourceID: s, path: "/Movies/Heat")); XCTAssertEqual(sibling, 0, "a folder name prefix is not a parent")
        let seriesID = try await unwrap(try await h.store.page(ItemQuery(filter: { var f = ItemFilter(); f.kinds = [.episode]; return f }()), limit: 1, offset: 0).first?.seriesID)
        let bySeries = try await count(nil, series: seriesID); XCTAssertEqual(bySeries, 3)
        let bySeason = try await count(nil, season: 1, series: seriesID); XCTAssertEqual(bySeason, 2)
        let specials = try await count(nil, season: 0, series: seriesID); XCTAssertEqual(specials, 1)
    }

    func testSavedViewsAreStoredPerScopePinnedOrderedAndSurviveReopening() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        var filter = ItemFilter()
        filter.resolutions = [.uhd4k, .hd1080]
        filter.hdrFormats = [.hdr10]
        filter.dolbyVision = true
        filter.genres = ["Drama"]
        filter.yearMin = 1990
        filter.minRating = 6.5
        filter.watch = .unwatched
        filter.minChannels = 6
        filter.dolbyAtmos = true
        filter.containers = [.mkv]
        filter.addedAfter = day(3)
        filter.folder = FolderScope(sourceID: "src1", path: "/Movies", recursive: false)
        filter.text = "heat"
        let query = ItemQuery(filter: filter, sort: ItemSort(key: .rating, ascending: false))

        let a = try await h.store.saveView(name: "4K Dolby", scope: .library, query: query, pinned: true)
        let b = try await h.store.saveView(name: "Unwatched", scope: .library, query: ItemQuery(filter: { var f = ItemFilter(); f.watch = .unwatched; return f }()), pinned: false)
        let folder = ViewScope.folder(sourceID: "src1", path: "/Movies")
        let c = try await h.store.saveView(name: "Newest here", scope: folder, query: ItemQuery(sort: ItemSort(key: .added, ascending: false)), pinned: true)
        XCTAssertEqual([a.position, b.position, c.position], [0, 1, 0], "positions count per scope")

        var library = try await h.store.views(scope: .library)
        XCTAssertEqual(library.map(\.name), ["4K Dolby", "Unwatched"])
        XCTAssertEqual(library.first?.query, query, "filters and sort come back exactly")
        let inFolder = try await h.store.views(scope: folder)
        XCTAssertEqual(inFolder.map(\.name), ["Newest here"])
        let other = try await h.store.views(scope: .folder(sourceID: "src1", path: "/TV"))
        XCTAssertTrue(other.isEmpty)
        let pinned = try await h.store.pinnedViews()
        XCTAssertEqual(Set(pinned.map(\.name)), ["4K Dolby", "Newest here"])

        // Rename, re-order and unpin.
        var changed = library[1]
        changed.name = "To watch"
        changed.position = -1
        changed.pinned = true
        changed.query.sort = ItemSort(key: .year, ascending: true)
        try await h.store.updateView(changed)
        library = try await h.store.views(scope: .library)
        XCTAssertEqual(library.map(\.name), ["To watch", "4K Dolby"])
        XCTAssertEqual(library.first?.query.sort, ItemSort(key: .year, ascending: true))
        var ghost = changed
        ghost.id = 9_999
        do { try await h.store.updateView(ghost); XCTFail("expected notFound") } catch let e as LibraryIndexError { XCTAssertEqual(e, .notFound("view 9999")) }

        try await h.store.deleteView(id: a.id)
        let afterDelete = try await h.store.views(scope: .library)
        XCTAssertEqual(afterDelete.map(\.name), ["To watch"])
        let pinnedNames = try await h.store.pinnedViews().map(\.name)
        XCTAssertEqual(pinnedNames, ["To watch", "Newest here"], "pinned views are ordered by position, then creation")

        // Everything is still there after closing and reopening the database file.
        try await h.store.checkpoint()
        let reopened = try SQLiteLibraryStore(path: h.dbPath)
        let again = try await reopened.views(scope: .library)
        XCTAssertEqual(again.map(\.name), ["To watch"])
        XCTAssertEqual(again.first?.query.sort.key, .year)
        let folderAgain = try await reopened.views(scope: folder)
        XCTAssertEqual(folderAgain.first?.query.sort, ItemSort(key: .added, ascending: false))
        XCTAssertEqual(folderAgain.first?.pinned, true)
    }

    func testASavedViewGivesTheSameGridAsTheQueryItWasMadeFrom() async throws {
        let fx = try await Fixture.build(count: 80)
        defer { fx.h.cleanup() }
        var f = ItemFilter()
        f.resolutions = [.hd1080, .uhd4k]
        f.watch = .unwatched
        let query = ItemQuery(filter: f, sort: ItemSort(key: .rating, ascending: false))
        let view = try await fx.h.store.saveView(name: "Good stuff", scope: .library, query: query, pinned: false)
        let loaded = try await unwrap(try await fx.h.store.views(scope: .library).first { $0.id == view.id })
        let direct = try await fx.h.store.page(query, limit: 500, offset: 0)
        let viaView = try await fx.h.store.page(loaded.query, limit: 500, offset: 0)
        XCTAssertEqual(ids(direct), ids(viaView))
        XCTAssertFalse(direct.isEmpty)
    }

    func testContinueWatchingOrdersByRecencyHonoursRetentionAndHiding() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        for n in ["A (2000)", "B (2001)", "C (2002)", "D (2003)"] { h.source.put("/L/\(n).mkv", size: 1, modified: day(1)) }
        try await h.syncer.sync()
        let all = try await h.store.page(ItemQuery(), limit: 10, offset: 0)
        let (a, b, c, d) = (all[0].id, all[1].id, all[2].id, all[3].id)
        try await h.store.updateProgress(itemID: a, position: 100, duration: 1_000, at: day(95))
        try await h.store.updateProgress(itemID: b, position: 500, duration: 1_000, at: day(96))
        try await h.store.updateProgress(itemID: c, position: 300, duration: 1_000, at: day(10))   // older than 60 days
        try await h.store.updateProgress(itemID: d, position: 0, duration: 1_000, at: day(97))    // nothing watched yet
        var row = try await h.store.continueWatching(limit: 10, now: day(100), retentionDays: 60)
        XCTAssertEqual(ids(row), [b, a])
        row = try await h.store.continueWatching(limit: 1, now: day(100), retentionDays: 60)
        XCTAssertEqual(ids(row), [b])
        row = try await h.store.continueWatching(limit: 10, now: day(100), retentionDays: 365)
        XCTAssertEqual(ids(row), [b, a, c])

        try await h.store.hideFromContinue(itemID: b, hidden: true)
        row = try await h.store.continueWatching(limit: 10, now: day(100), retentionDays: 60)
        XCTAssertEqual(ids(row), [a])
        try await h.store.updateProgress(itemID: b, position: 600, duration: 1_000, at: day(98))
        row = try await h.store.continueWatching(limit: 10, now: day(100), retentionDays: 60)
        XCTAssertEqual(ids(row), [b, a], "playing again brings it back")

        try await h.store.updateProgress(itemID: b, position: 960, duration: 1_000, at: day(99))   // 96 % counts as finished
        row = try await h.store.continueWatching(limit: 10, now: day(100), retentionDays: 60)
        XCTAssertEqual(ids(row), [a])
        let finished = try await unwrap(try await h.store.item(id: b))
        XCTAssertTrue(finished.watch.watched)
        XCTAssertEqual(finished.watch.playCount, 1)
        XCTAssertEqual(finished.watch.position, 0)
    }

    func testWatchStateRules() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        h.source.put("/L/A (2000).mkv", size: 1, modified: day(1))
        try await h.syncer.sync()
        let id = try await unwrap(try await h.store.page(ItemQuery(), limit: 1, offset: 0).first).id
        var item = try await unwrap(try await h.store.item(id: id))
        XCTAssertEqual(item.watch, WatchState.none)

        try await h.store.updateProgress(itemID: id, position: 250, duration: 1_000, at: day(1))
        item = try await unwrap(try await h.store.item(id: id))
        XCTAssertEqual(item.watch.position, 250)
        XCTAssertEqual(item.watch.duration, 1_000)
        XCTAssertFalse(item.watch.watched)
        XCTAssertEqual(item.watch.lastPlayed, day(1))

        try await h.store.updateProgress(itemID: id, position: 300, duration: nil, at: day(2))     // duration is remembered
        try await h.store.updateProgress(itemID: id, position: 950, duration: nil, at: day(3))
        item = try await unwrap(try await h.store.item(id: id))
        XCTAssertTrue(item.watch.watched)
        XCTAssertEqual(item.watch.playCount, 1)

        try await h.store.markWatched(itemIDs: [id], watched: true, at: day(4))                    // already watched: count stays
        item = try await unwrap(try await h.store.item(id: id))
        XCTAssertEqual(item.watch.playCount, 1)
        try await h.store.markWatched(itemIDs: [id], watched: false, at: day(5))
        item = try await unwrap(try await h.store.item(id: id))
        XCTAssertEqual(item.watch, WatchState(position: 0, duration: 1_000, watched: false, playCount: 0, lastPlayed: nil, favorite: false, hiddenFromContinue: false))
        try await h.store.markWatched(itemIDs: [id], watched: true, at: day(6))
        try await h.store.setFavorite(itemID: id, favorite: true)
        item = try await unwrap(try await h.store.item(id: id))
        XCTAssertTrue(item.watch.watched)
        XCTAssertTrue(item.watch.favorite)
        XCTAssertEqual(item.watch.playCount, 1)
        var fav = ItemFilter()
        fav.favoritesOnly = true
        let favCount = try await h.store.count(ItemQuery(filter: fav))
        XCTAssertEqual(favCount, 1)
        do { try await h.store.updateProgress(itemID: 12_345, position: 1, duration: 2, at: day(1)); XCTFail("expected notFound") } catch let e as LibraryIndexError { XCTAssertEqual(e, .notFound("item 12345")) }
    }

    func testNextUpFollowsTheSeriesAcrossSeasonsAndNeverOffersSpecials() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        for (s, e) in [(1, 1), (1, 2), (1, 3), (2, 1)] {
            h.source.put("/TV/Alpha/Season \(s)/Alpha - S0\(s)E0\(e).mkv", size: 1, modified: day(1))
        }
        h.source.put("/TV/Alpha/Specials/Alpha - S00E01 - Extra.mkv", size: 1, modified: day(1))
        try await h.syncer.sync()
        let seriesID = try await unwrap(try await h.store.page(ItemQuery(), limit: 1, offset: 0).first?.seriesID)
        let eps = try await h.store.episodes(ofSeries: seriesID)
        XCTAssertEqual(eps.map { "\($0.season ?? -1)x\($0.episode ?? -1)" }, ["0x1", "1x1", "1x2", "1x3", "2x1"])
        let id = Dictionary(uniqueKeysWithValues: eps.map { ("\($0.season ?? -1)x\($0.episode ?? -1)", $0.id) })

        var next = try await h.store.nextUp(limit: 10, now: day(100), retentionDays: 60)
        XCTAssertTrue(next.isEmpty, "nothing watched, nothing to continue")

        try await h.store.markWatched(itemIDs: [try XCTUnwrap(id["0x1"])], watched: true, at: day(94))
        next = try await h.store.nextUp(limit: 10, now: day(100), retentionDays: 60)
        XCTAssertTrue(next.isEmpty, "watching a special does not start the series")

        try await h.store.markWatched(itemIDs: [try XCTUnwrap(id["1x1"])], watched: true, at: day(95))
        next = try await h.store.nextUp(limit: 10, now: day(100), retentionDays: 60)
        XCTAssertEqual(next.map(\.item.id), [try XCTUnwrap(id["1x2"])])
        XCTAssertEqual(next.first?.afterEpisodeID, id["1x1"])

        try await h.store.markWatched(itemIDs: [try XCTUnwrap(id["1x3"])], watched: true, at: day(96))   // skipped 1x2: next is after the LAST watched
        next = try await h.store.nextUp(limit: 10, now: day(100), retentionDays: 60)
        XCTAssertEqual(next.map(\.item.id), [try XCTUnwrap(id["2x1"])], "season rollover")

        try await h.store.markWatched(itemIDs: [try XCTUnwrap(id["2x1"])], watched: true, at: day(97))
        next = try await h.store.nextUp(limit: 10, now: day(100), retentionDays: 60)
        XCTAssertTrue(next.isEmpty, "finished; the special is not offered")

        try await h.store.markWatched(itemIDs: [try XCTUnwrap(id["1x3"])], watched: false, at: day(98))
        try await h.store.markWatched(itemIDs: [try XCTUnwrap(id["2x1"])], watched: false, at: day(98))
        next = try await h.store.nextUp(limit: 10, now: day(100), retentionDays: 60)
        XCTAssertEqual(next.map(\.item.id), [try XCTUnwrap(id["1x2"])], "unwatching rewinds the series")
        XCTAssertEqual(next.first?.afterEpisodeID, id["1x1"])

        // In progress: the episode is in Continue Watching instead, the series leaves Next Up.
        try await h.store.updateProgress(itemID: try XCTUnwrap(id["1x2"]), position: 100, duration: 1_000, at: day(99))
        next = try await h.store.nextUp(limit: 10, now: day(100), retentionDays: 60)
        XCTAssertTrue(next.isEmpty)
        let cw = try await h.store.continueWatching(limit: 10, now: day(100), retentionDays: 60)
        XCTAssertEqual(ids(cw), [try XCTUnwrap(id["1x2"])])

        // Retention (60 days by default in the app): stale series disappear.
        try await h.store.updateProgress(itemID: try XCTUnwrap(id["1x2"]), position: 990, duration: 1_000, at: day(99))
        next = try await h.store.nextUp(limit: 10, now: day(100), retentionDays: 60)
        XCTAssertEqual(next.map(\.item.id), [try XCTUnwrap(id["1x3"])])
        next = try await h.store.nextUp(limit: 10, now: day(200), retentionDays: 60)
        XCTAssertTrue(next.isEmpty)

        // Hiding the next episode removes it from the row.
        try await h.store.hideFromContinue(itemID: try XCTUnwrap(id["1x3"]), hidden: true)
        next = try await h.store.nextUp(limit: 10, now: day(100), retentionDays: 60)
        XCTAssertTrue(next.isEmpty)
    }

    func testNextUpRanksSeriesByRecencyAndHonoursTheLimit() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        for show in ["Alpha", "Bravo", "Charlie"] {
            for e in 1...3 { h.source.put("/TV/\(show)/Season 1/\(show) - S01E0\(e).mkv", size: 1, modified: day(1)) }
        }
        try await h.syncer.sync()
        let all = try await h.store.page(ItemQuery(filter: { var f = ItemFilter(); f.kinds = [.episode]; return f }()), limit: 20, offset: 0)
        func first(of show: String) -> LibraryItem { all.first { $0.seriesTitle == show && $0.episode == 1 }! }
        try await h.store.markWatched(itemIDs: [first(of: "Alpha").id], watched: true, at: day(90))
        try await h.store.markWatched(itemIDs: [first(of: "Charlie").id], watched: true, at: day(98))
        try await h.store.markWatched(itemIDs: [first(of: "Bravo").id], watched: true, at: day(95))
        let next = try await h.store.nextUp(limit: 10, now: day(100), retentionDays: 60)
        XCTAssertEqual(next.map { $0.item.seriesTitle ?? "" }, ["Charlie", "Bravo", "Alpha"])
        XCTAssertEqual(next.map { $0.item.episode ?? 0 }, [2, 2, 2])
        let two = try await h.store.nextUp(limit: 2, now: day(100), retentionDays: 60)
        XCTAssertEqual(two.map { $0.item.seriesTitle ?? "" }, ["Charlie", "Bravo"])
    }

    func testMarkingASeasonOrSeriesWatched() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        for (s, e) in [(1, 1), (1, 2), (2, 1)] { h.source.put("/TV/Alpha/Season \(s)/Alpha - S0\(s)E0\(e).mkv", size: 1, modified: day(1)) }
        try await h.syncer.sync()
        let seriesID = try await unwrap(try await h.store.page(ItemQuery(), limit: 1, offset: 0).first?.seriesID)
        try await h.store.markSeries(seriesID: seriesID, season: 1, watched: true, at: day(10))
        var eps = try await h.store.episodes(ofSeries: seriesID)
        XCTAssertEqual(eps.map(\.watch.watched), [true, true, false])
        try await h.store.markSeries(seriesID: seriesID, season: nil, watched: true, at: day(11))
        eps = try await h.store.episodes(ofSeries: seriesID)
        XCTAssertEqual(eps.map(\.watch.watched), [true, true, true])
        XCTAssertEqual(eps.map(\.watch.playCount), [1, 1, 1])
        try await h.store.markSeries(seriesID: seriesID, season: nil, watched: false, at: day(12))
        eps = try await h.store.episodes(ofSeries: seriesID)
        XCTAssertEqual(eps.map(\.watch.watched), [false, false, false])
        var f = ItemFilter()
        f.watch = .unwatched
        f.seriesID = seriesID
        let unwatched = try await h.store.count(ItemQuery(filter: f))
        XCTAssertEqual(unwatched, 3)
    }

    func testRecentlyAddedUsesFileDatesNotScanTime() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        h.source.put("/L/Old (1990).mkv", size: 1, modified: day(5))
        h.source.put("/L/Newest (2024).mkv", size: 1, modified: day(60))
        h.source.put("/L/Middle (2000).mkv", size: 1, modified: day(30))
        h.source.put("/TV/Show/Season 1/Show - S01E01 - Pilot.mkv", size: 1, modified: day(45))
        h.source.put("/L/Future (2030).mkv", size: 1, modified: day(500))   // file date after the scan: capped at scan time (day 100)
        try await h.syncer.sync()
        let all = try await h.store.recentlyAdded(limit: 10, kind: nil)
        XCTAssertEqual(titles(all), ["Future", "Newest", "Pilot", "Middle", "Old"])
        XCTAssertEqual(all.first?.addedAt, day(100))
        let movies = try await h.store.recentlyAdded(limit: 2, kind: .movie)
        XCTAssertEqual(titles(movies), ["Future", "Newest"])
        let episodes = try await h.store.recentlyAdded(limit: 5, kind: .episode)
        XCTAssertEqual(titles(episodes), ["Pilot"])
        var f = ItemFilter()
        f.addedAfter = day(40)
        let c = try await h.store.count(ItemQuery(filter: f))
        XCTAssertEqual(c, 3)
    }

    func testMetadataUpdatesTitleSortAndSearchAndGenres() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        h.source.put("/L/zz (2000).mkv", size: 1, modified: day(1))
        h.source.put("/L/Beta (2001).mkv", size: 1, modified: day(1))
        try await h.syncer.sync()
        let zz = try await unwrap(try await h.store.page(ItemQuery(), limit: 5, offset: 0).first { $0.title == "zz" })
        try await h.store.setMetadata(itemID: zz.id, ItemMetadata(title: "Alpha: The Return", year: 2001, rating: 7.4, genres: ["Drama", "Sci-Fi", "drama"], tmdbID: 603))
        let after = try await unwrap(try await h.store.item(id: zz.id))
        XCTAssertEqual(after.title, "Alpha: The Return")
        XCTAssertEqual(after.rating, 7.4)
        XCTAssertEqual(after.tmdbID, 603)
        let order = try await h.store.page(ItemQuery(), limit: 5, offset: 0)
        XCTAssertEqual(titles(order), ["Alpha: The Return", "Beta"])
        var f = ItemFilter()
        f.text = "return alpha"
        let c1 = try await h.store.count(ItemQuery(filter: f)); XCTAssertEqual(c1, 1)
        f = ItemFilter(); f.genres = ["sci-fi"]
        let c2 = try await h.store.count(ItemQuery(filter: f)); XCTAssertEqual(c2, 1, "genres match without regard to case")
        try await h.store.setMetadata(itemID: zz.id, ItemMetadata(genres: []))
        let c3 = try await h.store.count(ItemQuery(filter: f)); XCTAssertEqual(c3, 0)
        let still = try await unwrap(try await h.store.item(id: zz.id))
        XCTAssertEqual(still.title, "Alpha: The Return", "nil fields are left alone")
        // A rescan does not undo the metadata.
        h.source.put("/L/zz (2000).mkv", size: 2, modified: day(9))
        try await h.syncer.sync()
        let kept = try await unwrap(try await h.store.item(id: zz.id))
        XCTAssertEqual(kept.title, "Alpha: The Return")
        XCTAssertEqual(kept.rating, 7.4)
        do { try await h.store.setMetadata(itemID: 4_242, ItemMetadata(title: "x")); XCTFail("expected notFound") } catch let e as LibraryIndexError { XCTAssertEqual(e, .notFound("item 4242")) }
    }

    func testTechnicalInfoCanBeFilledInLaterByAProbe() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        h.source.put("/L/Film (2010).mkv", size: 1, modified: day(1))
        try await h.syncer.sync()
        let film = try await unwrap(try await h.store.page(ItemQuery(), limit: 1, offset: 0).first)
        XCTAssertNil(film.maxResolution)
        let file = try await unwrap(try await h.store.versions(of: film.id).first)
        try await h.store.setTechnicalInfo(fileID: file.id, FileTechnicalInfo(duration: 7_200, container: .mkv, width: 3840, height: 1600, hdrFormats: [.hdr10Plus], dolbyVisionProfile: 7, videoCodec: "hevc", audioCodec: "truehd", audioChannels: 8, hasAtmos: true, bitrate: 50_000_000))
        let after = try await unwrap(try await h.store.item(id: film.id))
        XCTAssertEqual(after.maxResolution, .uhd4k, "a 3840 x 1600 scope film is still 4K")
        XCTAssertEqual(after.hdrFormats, [.hdr10Plus, .dolbyVision])
        XCTAssertEqual(after.dolbyVisionProfiles, [7])
        XCTAssertEqual(after.maxChannels, 8)
        XCTAssertEqual(after.runtime, 7_200)
        let stored = try await unwrap(try await h.store.versions(of: film.id).first)
        XCTAssertEqual(stored.technical?.audioCodec, "truehd")
        XCTAssertEqual(stored.technical?.bitrate, 50_000_000)
        // An unchanged file keeps what the probe found across rescans.
        try await h.syncer.sync()
        let again = try await unwrap(try await h.store.item(id: film.id))
        XCTAssertEqual(again.maxResolution, .uhd4k)
        do { try await h.store.setTechnicalInfo(fileID: 777_777, FileTechnicalInfo()); XCTFail("expected notFound") } catch let e as LibraryIndexError { XCTAssertEqual(e, .notFound("file 777777")) }
    }

    func testGridQueriesUseIndexesAndNeverSortInATempTree() async throws {
        let fx = try await Fixture.build(count: 60)
        defer { fx.h.cleanup() }
        for key in ItemSortKey.allCases {
            for asc in [true, false] {
                let plan = try await fx.h.store.gridPlan(ItemQuery(sort: ItemSort(key: key, ascending: asc)))
                let text = plan.joined(separator: " | ")
                XCTAssertTrue(text.contains("idx_items_"), "\(key) asc=\(asc): \(text)")
                XCTAssertFalse(text.contains("TEMP B-TREE"), "\(key) asc=\(asc): \(text)")
            }
        }
        var f = ItemFilter()
        f.watch = .inProgress
        let cw = try await fx.h.store.queryPlan("SELECT i.id FROM items i WHERE i.version_count > 0 AND i.watched = 0 AND i.position > 0 AND i.hidden = 0 AND i.last_played >= 1 ORDER BY i.last_played DESC LIMIT 10")
        XCTAssertTrue(cw.joined().contains("idx_items_continue"), "\(cw)")
        let letters = try await fx.h.store.queryPlan("SELECT i.letter, COUNT(*) FROM items i WHERE i.version_count > 0 GROUP BY i.letter")
        XCTAssertTrue(letters.joined().contains("idx_items_letter"), "\(letters)")
    }
}
