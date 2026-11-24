import XCTest
import LibraryIndex
import MetadataOnline
import RemuxEngine
import UserData
@testable import AppLogic

/// R456: the settings added by the settings reorganisation: defaults, what they control, and the round trip through the user data.
/// FIXTURE: invented values; no device, no iCloud.
final class AppPreferencesTests: XCTestCase {
    private final class Tick: @unchecked Sendable {
        private let lock = NSLock()
        private var t = 1_700_000_000.0
        func next() -> Date { lock.withLock { t += 1; return Date(timeIntervalSince1970: t) } }
    }

    private func ledger(_ id: String, _ tick: Tick = Tick()) -> UserDataLedger { UserDataLedger(deviceID: id, clock: { tick.next() }) }

    func testEverySettingHasItsDefault() {
        XCTAssertEqual(AppPreference.sortOrder.defaultValue, .string("title"))
        XCTAssertEqual(AppPreference.hideSpoilers.defaultValue, .bool(false))
        XCTAssertEqual(AppPreference.streamingCache.defaultValue, .string("auto"))
        XCTAssertEqual(AppPreference.metadataLanguage.defaultValue, .string("auto"))
        XCTAssertEqual(AppPreference.artworkLanguage.defaultValue, .string("auto"))
        XCTAssertEqual(AppPreference.preferLocalArtwork.defaultValue, .bool(true))
        XCTAssertEqual(LibrarySortDefault.stored(nil), .title, "an unknown or missing value is the default")
        XCTAssertEqual(StreamingCache.stored("nonsense"), .auto)
    }

    func testSortOrderIsTheGridsFirstSort() {
        XCTAssertEqual(LibrarySortDefault.title.itemSort, ItemSort(key: .title, ascending: true))
        XCTAssertEqual(LibrarySortDefault.dateAdded.itemSort, ItemSort(key: .added, ascending: false))
        XCTAssertEqual(LibrarySortDefault.releaseDate.itemSort, ItemSort(key: .year, ascending: false))
        XCTAssertEqual(LibrarySortDefault.rating.itemSort, ItemSort(key: .rating, ascending: false))
        XCTAssertEqual(LibrarySortDefault.allCases.map(\.title), ["Title", "Date Added", "Release Date", "Rating"])
    }

    func testTheGridsOpenOnTheChosenSort() throws {
        let store = try LibraryRig.make().store
        XCTAssertEqual(ItemGridViewModel.movies(store: store, sort: LibrarySortDefault.rating.itemSort).query.sort, ItemSort(key: .rating, ascending: false))
        XCTAssertEqual(ItemGridViewModel.movies(store: store).query.sort, ItemSort(), "no setting, the title order as before")
        XCTAssertEqual(ShowsViewModel(store: store, sort: LibrarySortDefault.dateAdded.itemSort).query.sort, ItemSort(key: .added, ascending: false))
        XCTAssertEqual(ShowsViewModel(store: store, sort: LibrarySortDefault.rating.itemSort).query.sort, ItemSort(key: .title, ascending: true),
                       "shows carry no rating, so a rating default opens by title")
    }

    func testStreamingCacheIsTheEngineBudget() {
        XCTAssertEqual(StreamingCache.auto.budget, EngineBudget(), "Auto is the engine's own budget")
        XCTAssertEqual(StreamingCache.small.memoryBytes * 2, StreamingCache.auto.memoryBytes)
        XCTAssertEqual(StreamingCache.large.memoryBytes, StreamingCache.auto.memoryBytes * 2)
        // A smaller budget shortens the segments at a high bitrate (less read ahead); a larger one never lengthens past the maximum.
        XCTAssertLessThanOrEqual(StreamingCache.small.budget.targetSegmentSeconds(bitrate: 80_000_000), StreamingCache.large.budget.targetSegmentSeconds(bitrate: 80_000_000))
    }

    func testLanguageAutoFollowsTheAppleTV() {
        XCTAssertEqual(LanguagePreference.resolved(nil, system: ["fr-FR", "en-US"]), "fr")
        XCTAssertEqual(LanguagePreference.resolved("auto", system: ["de-DE"]), "de")
        XCTAssertEqual(LanguagePreference.resolved("ja", system: ["de-DE"]), "ja")
        XCTAssertEqual(LanguagePreference.resolved("junk", system: []), "en", "an invalid choice and no system language: English")
        XCTAssertEqual(LanguagePreference.title("auto"), "Auto")
        XCTAssertEqual(LanguagePreference.title("de"), "German")
    }

    func testTheArtworkLanguageLeadsTheGalleryOrder() {
        let refs = [ImageRef(path: "/en", language: "en"), ImageRef(path: "/de", language: "de")]
        let sorted = ArtworkCandidates.sorted(ArtworkCandidates.online(refs), userLanguage: LanguagePreference.resolved("de", system: ["en-US"]))
        XCTAssertEqual(sorted.map(\.id), ["online:/de", "online:/en"])
    }

    func testHideSpoilersHidesOnlyUnwatchedEpisodes() {
        XCTAssertEqual(SpoilerRules.synopsis("The killer is the butler.", watched: false, hideSpoilers: true), SpoilerRules.hiddenSynopsis)
        XCTAssertEqual(SpoilerRules.synopsis("The killer is the butler.", watched: true, hideSpoilers: true), "The killer is the butler.")
        XCTAssertEqual(SpoilerRules.synopsis("The killer is the butler.", watched: false, hideSpoilers: false), "The killer is the butler.", "off by default")
        XCTAssertNil(SpoilerRules.synopsis(nil, watched: false, hideSpoilers: true), "an episode with no description stays without one")
        XCTAssertEqual(SpoilerRules.synopsis("  ", watched: false, hideSpoilers: true), "  ", "a blank description is left alone")
        XCTAssertTrue(SpoilerRules.hidesStill(watched: false, hideSpoilers: true))
        XCTAssertFalse(SpoilerRules.hidesStill(watched: true, hideSpoilers: true))
    }

    func testTheArtworkSourceOrderForEveryCombination() {
        XCTAssertEqual(ArtworkPrecedence.order(preferLocal: true), [.userChoice, .localFile, .server, .online])
        XCTAssertEqual(ArtworkPrecedence.order(preferLocal: false), [.userChoice, .online, .localFile, .server])
        for preferLocal in [true, false] { XCTAssertEqual(ArtworkPrecedence.order(preferLocal: preferLocal).first, .userChoice, "your own choice is always first") }
    }

    func testSettingsTravelRecordByRecordAndTheNewestEditWins() throws {
        let tick = Tick()
        let a = ledger("A", tick), b = ledger("B", tick)
        PreferenceSync.push(to: a, stored: { ["sortOrder": UDValue.string("rating"), "hideSpoilers": .bool(true)][$0] })
        PreferenceSync.push(to: b, stored: { ["hideSpoilers": UDValue.bool(false), "streamingCache": .string("large")][$0] })
        // A restore or sync merges both ways; each setting keeps its own newest value.
        _ = try UDExport.import(UDExport.export(a), into: b)
        _ = try UDExport.import(UDExport.export(b), into: a)
        XCTAssertEqual(PreferenceSync.pull(from: a), PreferenceSync.pull(from: b))
        let merged = PreferenceSync.pull(from: b)
        XCTAssertEqual(merged["sortOrder"], .string("rating"))
        XCTAssertEqual(merged["streamingCache"], .string("large"))
        XCTAssertEqual(merged["hideSpoilers"], .bool(false), "B wrote hideSpoilers last")
    }

    func testAnUnchangedSettingIsNotWrittenAgain() {
        let l = ledger("A")
        PreferenceSync.push(to: l, stored: { $0 == "sortOrder" ? UDValue.string("title") : nil })
        let first = l.record(type: UDSchema.settings, id: UDSettings.recordID)?.liveFields["sortOrder"]?.stamp
        PreferenceSync.push(to: l, stored: { $0 == "sortOrder" ? UDValue.string("title") : nil })
        XCTAssertEqual(l.record(type: UDSchema.settings, id: UDSettings.recordID)?.liveFields["sortOrder"]?.stamp, first)
    }

    func testANewerSchemaIsKeptAndNotRead() {
        let l = ledger("A")
        l.setSetting(AppPreference.schemaKey, .int(Int64(AppPreference.schemaVersion + 1)))
        l.setSetting("sortOrder", .string("rating"))
        XCTAssertTrue(PreferenceSync.pull(from: l).isEmpty, "never restore a newer format")
        XCTAssertEqual(l.settingValues()["sortOrder"], .string("rating"), "and the record itself is left as it is")
    }

    func testAWrongTypeOrAnUnknownKeyIsIgnored() {
        let values = PreferenceSync.importable(["hideSpoilers": .string("yes"), "sortOrder": .string("title"), "somethingElse": .bool(true)])
        XCTAssertEqual(values, ["sortOrder": .string("title")])
    }

    func testNoPasscodeOrPasswordCanTravel() {
        let names = AppPreference.synced.map { $0.lowercased() }
        XCTAssertFalse(names.contains { $0.contains("pin") || $0.contains("passcode") || $0.contains("password") || $0.contains("parental") })
        let injected = PreferenceSync.importable(["parentalPIN": .string("1234"), "passcodeHash": .string("abc"), "sortOrder": .string("title")])
        XCTAssertEqual(Set(injected.keys), ["sortOrder"], "a key outside the list is never applied")
        let exported = PreferenceSync.export(stored: { _ in UDValue.string("1234") })
        XCTAssertEqual(Set(exported.keys), Set(AppPreference.synced + [AppPreference.schemaKey]))
    }
}
