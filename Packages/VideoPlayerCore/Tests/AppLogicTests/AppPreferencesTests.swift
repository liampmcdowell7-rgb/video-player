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

    /// A device: stored values (UserDefaults stand-in), its ledger and its baseline.
    private final class Device {
        var stored: [String: UDValue]
        var baseline: PreferenceBaseline
        let ledger: UserDataLedger
        init(_ id: String, _ tick: Tick, stored: [String: UDValue] = [:]) {
            self.stored = stored
            self.ledger = UserDataLedger(deviceID: id, clock: { tick.next() })
            self.baseline = PreferenceSync.firstBaseline(stored: { stored[$0] })
        }
        func push() { baseline = PreferenceSync.push(to: ledger, stored: { self.stored[$0] }, baseline: baseline) }
        func pull() {
            let r = PreferenceSync.pull(from: ledger, stored: { self.stored[$0] }, baseline: baseline)
            for (k, v) in r.apply { stored[k] = v }
            baseline = r.baseline
        }
        /// What the app does after every completed sync: own edits first, then the newest values.
        func reconcile() { push(); pull() }
        func edit(_ key: AppPreference, _ value: UDValue) { stored[key.rawValue] = value }
    }

    func testSettingsTravelRecordByRecordAndTheNewestEditWins() throws {
        let tick = Tick()
        let a = Device("A", tick), b = Device("B", tick)
        a.edit(.sortOrder, .string("rating")); a.edit(.hideSpoilers, .bool(true)); a.push()
        b.edit(.hideSpoilers, .bool(false)); b.edit(.streamingCache, .string("large")); b.push()
        // A restore or sync merges both ways; each setting keeps its own newest value.
        _ = try UDExport.import(UDExport.export(a.ledger), into: b.ledger)
        _ = try UDExport.import(UDExport.export(b.ledger), into: a.ledger)
        a.reconcile(); b.reconcile()
        XCTAssertEqual(a.stored, b.stored)
        XCTAssertEqual(b.stored["sortOrder"], .string("rating"))
        XCTAssertEqual(b.stored["streamingCache"], .string("large"))
        XCTAssertEqual(b.stored["hideSpoilers"], .bool(false), "B wrote hideSpoilers last")
    }

    /// R457 item 1: device A launches with an old stored value, B's newer edit arrives, A opens Settings: B's value stays the newest.
    func testANewerValueFromAnotherDeviceSurvivesOpeningSettingsOnTheOlderDevice() throws {
        let tick = Tick()
        let a = Device("A", tick, stored: ["sortOrder": .string("title")])
        let b = Device("B", tick)
        a.push()                                    // A's launch: nothing changed since its baseline, nothing written
        XCTAssertNil(a.ledger.settingValues()["sortOrder"], "an unchanged stored value is not written with a new stamp")
        b.edit(.sortOrder, .string("rating")); b.push()          // B's newer edit
        _ = try UDExport.import(UDExport.export(b.ledger), into: a.ledger)   // arrives on A after launch
        a.push()                                    // A opens Settings BEFORE the pull ran: still no write
        XCTAssertEqual(a.ledger.settingValues()["sortOrder"], .string("rating"))
        a.reconcile()                               // after the sync completes
        XCTAssertEqual(a.stored["sortOrder"], .string("rating"))
        a.push()                                    // A opens Settings again
        XCTAssertEqual(a.ledger.settingValues()["sortOrder"], .string("rating"), "B's value is still the newest")
        _ = try UDExport.import(UDExport.export(a.ledger), into: b.ledger)
        XCTAssertEqual(b.ledger.settingValues()["sortOrder"], .string("rating"))
    }

    func testAnEditOnThisDeviceIsWrittenOnceAndWinsOverTheOlderLedgerValue() throws {
        let tick = Tick()
        let a = Device("A", tick), b = Device("B", tick)
        b.edit(.hideSpoilers, .bool(true)); b.push()
        _ = try UDExport.import(UDExport.export(b.ledger), into: a.ledger)
        a.edit(.hideSpoilers, .bool(false))         // A edits, then the sync completes before Settings was left
        a.reconcile()
        XCTAssertEqual(a.ledger.settingValues()["hideSpoilers"], .bool(false), "the newer edit is the one written")
        XCTAssertEqual(a.stored["hideSpoilers"], .bool(false))
        let stamp = a.ledger.record(type: UDSchema.settings, id: UDSettings.recordID)?.liveFields["hideSpoilers"]?.stamp
        a.push(); a.reconcile()
        XCTAssertEqual(a.ledger.record(type: UDSchema.settings, id: UDSettings.recordID)?.liveFields["hideSpoilers"]?.stamp, stamp, "written once")
    }

    func testEverySwitchAndPickerOfSettingsIsInTheRecordWithItsOwnTypeAndDefault() {
        let expected: Set<String> = ["sortOrder", "hideSpoilers", "showContinueWatching", "showNextUp", "showRecentlyAdded", "continueWatchingDays",
            "showDiscover", "scanOnLaunch", "showTitleLogos", "preferLocalArtwork", "onlineRegion", "onlineFreeSources", "metadataLanguage",
            "artworkLanguage", "streamingCache", "autoPlayNextEpisode", "showSkipButtons", "skipIntrosAutomatically", "skipCreditsAutomatically",
            "showPlaybackStatsButton", "rememberTrackChoicePerShow", "trueHDCompatibilityCore"]
        XCTAssertEqual(Set(AppPreference.synced), expected)
        XCTAssertEqual(AppPreference.continueWatchingDays.defaultValue, .int(90))
        XCTAssertEqual(AppPreference.onlineRegion.defaultValue, .string("US"))
        XCTAssertEqual(AppPreference.onlineFreeSources.defaultValue, .bool(false))
        XCTAssertEqual(AppPreference.skipIntrosAutomatically.defaultValue, .bool(true))
        XCTAssertEqual(AppPreference.skipCreditsAutomatically.defaultValue, .bool(false))
        // Every SettingsKey that is a switch or a picker travels except none: the table below is the whole list.
        XCTAssertEqual(Set(SettingsKey.allCases.map(\.rawValue)).subtracting(expected), [])
    }

    func testAStoredNumberIsNotReadAsASwitchAndTheBaselineKeepsItsTypes() {
        XCTAssertEqual(AppPreference.continueWatchingDays.read(Int(60)), .int(60))
        XCTAssertNil(AppPreference.hideSpoilers.read("yes"), "wrong type: ignored")
        XCTAssertEqual(AppPreference.sortOrder.read("rating"), .string("rating"))
        let baseline = PreferenceBaseline(values: ["showNextUp": .bool(false), "sortOrder": .string("rating"), "continueWatchingDays": .int(30)])
        XCTAssertEqual(PreferenceBaseline(encoded: baseline.encoded), baseline)
        XCTAssertNil(PreferenceBaseline(encoded: "not json"))
        XCTAssertEqual(PreferenceBaseline(encoded: "{\"parentalPIN\":\"s:1234\"}")?.values, [:], "an unknown key is dropped")
    }

    func testTheBaselineIsNeverPartOfTheSyncedKeys() {
        XCTAssertFalse(AppPreference.synced.contains(AppPreference.baselineKey))
        XCTAssertFalse(AppPreference.synced.contains("vp.deviceID"))
    }

    func testAnUnchangedSettingIsNotWrittenAgain() {
        let l = ledger("A")
        var baseline = PreferenceBaseline()
        let stored: (String) -> UDValue? = { $0 == "sortOrder" ? UDValue.string("title") : nil }
        baseline = PreferenceSync.push(to: l, stored: stored, baseline: baseline)
        let first = l.record(type: UDSchema.settings, id: UDSettings.recordID)?.liveFields["sortOrder"]?.stamp
        baseline = PreferenceSync.push(to: l, stored: stored, baseline: baseline)
        XCTAssertEqual(l.record(type: UDSchema.settings, id: UDSettings.recordID)?.liveFields["sortOrder"]?.stamp, first)
    }

    func testANewerSchemaIsKeptAndNotRead() {
        let l = ledger("A")
        l.setSetting(AppPreference.schemaKey, .int(Int64(AppPreference.schemaVersion + 1)))
        l.setSetting("sortOrder", .string("rating"))
        XCTAssertTrue(PreferenceSync.pull(from: l, stored: { _ in nil }, baseline: PreferenceBaseline()).apply.isEmpty, "never restore a newer format")
        XCTAssertEqual(l.settingValues()["sortOrder"], .string("rating"), "and the record itself is left as it is")
    }

    func testAWrongTypeOrAnUnknownKeyIsIgnored() {
        let values = PreferenceSync.importable(["hideSpoilers": .string("yes"), "sortOrder": .string("title"), "somethingElse": .bool(true)])
        XCTAssertEqual(values, ["sortOrder": .string("title")])
    }

    func testNoPasscodeOrPasswordCanTravel() {
        let names = AppPreference.synced.map { $0.lowercased() }
        XCTAssertFalse(names.contains { $0 == "pin" || $0.hasPrefix("pin") || $0.hasSuffix("pin") || $0.contains("passcode") || $0.contains("password") || $0.contains("parental") || $0.contains("token") || $0.contains("secret") || $0.contains("apikey") })
        let injected = PreferenceSync.importable(["parentalPIN": .string("1234"), "passcodeHash": .string("abc"), "sortOrder": .string("title")])
        XCTAssertEqual(Set(injected.keys), ["sortOrder"], "a key outside the list is never applied")
        let exported = PreferenceSync.export(stored: { _ in UDValue.string("1234") })
        XCTAssertEqual(Set(exported.keys), Set(AppPreference.synced + [AppPreference.schemaKey]))
    }

    /// R457 items 3, 4, 5: the footers say what the switches cover, in one short line each.
    func testTheFootersSayWhatTheSwitchesCover() {
        XCTAssertTrue(SpoilerRules.footer.contains("Continue Watching") && SpoilerRules.footer.contains("Next Up") && SpoilerRules.footer.contains("Info tab"))
        XCTAssertTrue(SpoilerRules.footer.contains("episode page") || SpoilerRules.footer.contains("episode pages"))
        XCTAssertTrue(ArtworkPrecedence.footer(preferLocal: true).hasPrefix("Posters, backgrounds and logos"))
        XCTAssertTrue(ArtworkPrecedence.footer(preferLocal: false).contains("online first"))
        XCTAssertNotEqual(ArtworkPrecedence.footer(preferLocal: true), ArtworkPrecedence.footer(preferLocal: false))
        XCTAssertTrue(SyncAndBackupText.settingsFooter.contains("No passcode or key"))
        XCTAssertLessThan(SyncAndBackupText.settingsFooter.count, 120, "one short line")
    }

    /// An episode counts as unwatched until it is watched; a started one is not watched (R457 item 5, PROVISIONAL).
    func testAStartedEpisodeStaysHiddenUntilWatched() {
        XCTAssertTrue(SpoilerRules.hidesStill(watched: false, hideSpoilers: true), "started or not started: not watched")
        XCTAssertFalse(SpoilerRules.hidesStill(watched: true, hideSpoilers: true))
        XCTAssertFalse(SpoilerRules.hidesStill(watched: false, hideSpoilers: false))
        XCTAssertEqual(SpoilerRules.synopsis("The killer is the butler.", watched: false, hideSpoilers: true), SpoilerRules.hiddenSynopsis, "the player's Info tab uses the same rule")
        XCTAssertEqual(SpoilerRules.synopsis("The killer is the butler.", watched: true, hideSpoilers: true), "The killer is the butler.")
    }
}
