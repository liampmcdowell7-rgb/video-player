import XCTest
import MetadataOnline
import UserData
@testable import AppLogic

private final class Tick: @unchecked Sendable {
    private let lock = NSLock()
    private var t = 1_700_000_000.0
    func next() -> Date { lock.withLock { t += 1; return Date(timeIntervalSince1970: t) } }
}

/// R455: the candidate list of a gallery: grouping, language names, order, filter, the kinds per level, the override rule.
/// FIXTURE: invented picture paths and sizes; nothing is fetched.
final class ArtworkChoiceTests: XCTestCase {
    private let us = Locale(identifier: "en_US")

    private func ref(_ path: String, _ language: String?, _ rating: Double = 0, _ w: Int = 1000, _ h: Int = 1500) -> ImageRef {
        ImageRef(path: path, width: w, height: h, language: language, voteAverage: rating)
    }

    func testLanguageNamesAreWordsAndNeverACodeAlone() {
        XCTAssertEqual(ArtworkCandidates.languageName(code: "en", locale: us), "English")
        XCTAssertEqual(ArtworkCandidates.languageName(code: "de", locale: us), "German")
        XCTAssertEqual(ArtworkCandidates.languageName(code: nil, locale: us), "No Text")
        XCTAssertEqual(ArtworkCandidates.languageName(code: "xx", locale: us), "No Text", "a textless marker is No Text")
        XCTAssertEqual(ArtworkCandidates.languageName(code: "", locale: us), "No Text")
        XCTAssertEqual(ArtworkCandidates.languageName(code: "zzzz", locale: us), "Other Language", "an unknown code is never shown alone")
    }

    func testPixelSizeIsPlainText() {
        XCTAssertEqual(ArtworkCandidates.online([ref("/a.jpg", "en", 0, 2000, 3000)])[0].pixelSizeText, "2000 × 3000")
        XCTAssertNil(ArtworkCandidates.online([ImageRef(path: "/b.jpg")])[0].pixelSizeText, "no size from the source, none invented")
    }

    func testCandidatesComeFromTheKindsListAndDuplicatesAreDropped() {
        let set = ImageSet(posters: [ref("/p1.jpg", "en"), ref("/p1.jpg", "en"), ref("/p2.jpg", nil)], backdrops: [ref("/b1.jpg", nil)], logos: [])
        XCTAssertEqual(ArtworkCandidates.online(set, kind: .poster).map(\.id), ["online:/p1.jpg", "online:/p2.jpg"])
        XCTAssertEqual(ArtworkCandidates.online(set, kind: .background).count, 1)
        XCTAssertTrue(ArtworkCandidates.online(set, kind: .logo).isEmpty, "a kind with no pictures stays empty")
        XCTAssertTrue(ArtworkCandidates.online(set, kind: .episodeStill).isEmpty)
    }

    func testOrderIsUserLanguageThenNoTextThenRatingThenSize() {
        let list = ArtworkCandidates.online([
            ref("/fr.jpg", "fr", 9), ref("/none-low.jpg", nil, 3), ref("/en-low.jpg", "en", 2), ref("/en-high.jpg", "en", 7),
            ref("/none-big.jpg", nil, 3, 4000, 6000), ref("/de.jpg", "de", 1),
        ])
        let sorted = ArtworkCandidates.sorted(list, userLanguage: "en-US")
        XCTAssertEqual(sorted.map(\.id), ["online:/en-high.jpg", "online:/en-low.jpg", "online:/none-big.jpg", "online:/none-low.jpg", "online:/fr.jpg", "online:/de.jpg"])
    }

    func testSourcesKeepTheirOrderAndOnlineIsFirst() {
        let online = ArtworkCandidate(source: .online, origin: .online("/a.jpg"), languageCode: "en")
        let file = ArtworkCandidate(source: .yourFiles, origin: .yourFile(sourceID: "s", path: "/poster.jpg"))
        let server = ArtworkCandidate(source: .server, origin: .server("k"))
        let sorted = ArtworkCandidates.sorted([server, file, online], userLanguage: "en")
        XCTAssertEqual(sorted.map(\.source), [.online, .yourFiles, .server])
        XCTAssertEqual(ArtworkSourceKind.allCases.map(\.title), ["Online", "From Your Files", "From the Server", "Web Address"])
    }

    func testFilterMenuListsTheUsersLanguageAndNoTextFirstThenAllLanguages() {
        let list = ArtworkCandidates.online([ref("/a", "fr"), ref("/b", nil), ref("/c", "en"), ref("/d", "de")])
        let filters = ArtworkCandidates.filters(for: list, userLanguage: "en-US", locale: us)
        XCTAssertEqual(filters, [.language("en"), .noText, .language("fr"), .language("de"), .all])
        XCTAssertEqual(ArtworkCandidates.defaultFilter(for: list, userLanguage: "en-US", locale: us), .language("en"))
        XCTAssertEqual(filters.map { $0.title(locale: us) }, ["English", "No Text", "French", "German", "All Languages"])
        XCTAssertEqual(ArtworkCandidates.filtered(list, by: .noText).map(\.id), ["online:/b"])
        XCTAssertEqual(ArtworkCandidates.filtered(list, by: .all).count, 4)
        XCTAssertEqual(ArtworkCandidates.filtered(list, by: .language("fr")).count, 1)
    }

    func testWithoutTheUsersLanguageTheFilterOpensOnNoTextThenAll() {
        let textless = ArtworkCandidates.online([ref("/a", nil), ref("/b", "fr")])
        XCTAssertEqual(ArtworkCandidates.defaultFilter(for: textless, userLanguage: "en", locale: us), .noText)
        XCTAssertEqual(ArtworkCandidates.defaultFilter(for: [], userLanguage: "en", locale: us), .all)
    }

    func testAHundredAndFiftyCandidatesSortAndFilterInOnePass() {
        let many = ArtworkCandidates.online((0..<150).map { ref("/p\($0).jpg", ["en", "fr", "de", nil][$0 % 4], Double($0 % 10), 1000 + $0, 1500) })
        let sorted = ArtworkCandidates.sorted(many, userLanguage: "en")
        XCTAssertEqual(sorted.count, 150)
        XCTAssertEqual(Set(sorted.map(\.id)).count, 150)
        XCTAssertEqual(ArtworkCandidates.filtered(sorted, by: .language("en")).count, 38)
        XCTAssertTrue(sorted.prefix(38).allSatisfy { $0.languageCode == "en" }, "the user's language leads")
    }

    func testKindsPerLevelAndTheirAspect() {
        XCTAssertEqual(ArtworkGalleryKind.kinds(for: .movie), [.poster, .background, .logo])
        XCTAssertEqual(ArtworkGalleryKind.kinds(for: .show), [.poster, .background, .logo])
        XCTAssertEqual(ArtworkGalleryKind.kinds(for: .season), [.seasonPoster])
        XCTAssertEqual(ArtworkGalleryKind.kinds(for: .episode), [.episodeStill])
        XCTAssertEqual(ArtworkGalleryKind.poster.aspectRatio, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(ArtworkGalleryKind.background.aspectRatio, 16.0 / 9.0, accuracy: 0.0001)
        XCTAssertEqual(ArtworkGalleryKind.episodeStill.aspectRatio, 16.0 / 9.0, accuracy: 0.0001)
        XCTAssertEqual(ArtworkGalleryKind.allCases.map(\.field), [.poster, .backdrop, .logo, .seasonPoster, .episodeStill])
    }

    func testChoosingStoresOnlineAsItsPathAndAutomaticIsNoOverride() {
        let c = ArtworkCandidates.online([ref("/abc.jpg", "en")])[0]
        XCTAssertEqual(c.onlineChoice?.stored, "online:/abc.jpg")
        // A choice is a user-layer value; removing it (Automatic) leaves no override and the automatic rule decides.
        XCTAssertEqual(ArtworkOverride.resolve(.artwork(.file("abc.jpg")), onlineAvailable: false), .file("abc.jpg"))
        XCTAssertNil(ArtworkOverride.resolve(nil, onlineAvailable: true), "Automatic removes the override")
        XCTAssertEqual(ArtworkOverride.resolve(.artwork(.online("/abc.jpg")), onlineAvailable: true), .online("/abc.jpg"))
        XCTAssertNil(ArtworkOverride.resolve(.artwork(.online("/abc.jpg")), onlineAvailable: false), "no online request without the switch (R209)")
    }

    func testTheOverrideBeatsEverySourceThroughTheLedger() async {
        let tick = Tick()
        let ledger = UserDataLedger(deviceID: "A", clock: { tick.next() })
        let key = UDEditKey.movie(tmdbID: 603)
        ledger.setEdit(key, .poster, .artwork(.file("chosen.jpg")))
        let chosen = ArtworkOverride.resolve(ledger.edits(for: [key])[.poster], onlineAvailable: true)
        let picked = await ArtworkOverride.pick(override: chosen, automatic: { ArtworkOverride.Resolved.online("/automatic.jpg") })
        XCTAssertEqual(picked, .file("chosen.jpg"))
        // A rescan and Fix Match write other records; an online refresh changes the cache. The edit record is untouched.
        ledger.setEdit(UDEditKey.movie(tmdbID: 604), .poster, .artwork(.file("other.jpg")))
        XCTAssertEqual(ArtworkOverride.resolve(ledger.edits(for: [key])[.poster], onlineAvailable: true), .file("chosen.jpg"))
        ledger.resetEdit(key, .poster)
        XCTAssertNil(ArtworkOverride.resolve(ledger.edits(for: [key])[.poster], onlineAvailable: true), "Automatic removes it")
    }

    func testTheOnlineOffLineAndEmptyStateAreWords() {
        let gallery = ArtworkGallery(kind: .logo, candidates: [], onlineSwitchOff: true)
        XCTAssertTrue(gallery.isEmpty)
        XCTAssertEqual(ArtworkGallery.onlineOffLine, "Online pictures need Online Lookup in Settings.")
        XCTAssertEqual(gallery.emptyText, "No logo pictures were found for this title. You can add one from a web address.")
    }
}
