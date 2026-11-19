#if DEBUG
import Foundation
import SwiftUI
import VideoPlayerCore
import LibraryIndex
import UserData
import AppLogic

/// UI-test launch modes for the screenshot job (docs/GITHUB_ACTIONS_RUNBOOK.md). Debug builds only: this file is inside
/// `#if DEBUG` and every call to it is too, so a Release build has none of it (UITestLaunchTests checks the guard).
///
/// `-UITestEmpty`: clean start (saved settings, library database, ledger file and picture caches removed), no iCloud calls,
/// no scan. `-UITestFixtures`: the same, then the synthetic sample library (AppLogic `UITestFixtures`) is scanned in through
/// the real library scan from an in-memory source. Nothing in either mode uses the network.
enum UITestMode {
    static let current = UITestLaunch.mode(arguments: ProcessInfo.processInfo.arguments, buildAllowsUITestModes: true)

    static func value(_ name: String) -> String? {
        UITestLaunch.value(of: name, arguments: ProcessInfo.processInfo.arguments, mode: current)
    }

    /// Removes what an earlier launch saved, so every UI-test launch starts the same. Called first in `AppServices.init`.
    static func resetPersistentState() {
        guard current != .off else { return }
        if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
        let fm = FileManager.default
        for base in [(fm.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory), (fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory)] {
            for name in (try? fm.contentsOfDirectory(atPath: base.path)) ?? [] {
                try? fm.removeItem(at: base.appendingPathComponent(name))
            }
        }
    }

    /// The sample source for its saved definition; nil for every other definition (and in every other mode).
    static func fixtureSource(for definition: UDSourceDefinition) -> (any MediaSource)? {
        guard current == .fixtures, definition.id == UITestFixtures.sourceID else { return nil }
        return FixtureSource()
    }

    /// Fills the library (fixtures mode). Called by the root screen instead of the iCloud start-up and the launch scan.
    @MainActor
    static func prepare(_ services: AppServices) async {
        guard current == .fixtures else { return }
        services.ledger.upsertSource(UITestFixtures.definition)
        // A Jellyfin source that is never scanned or contacted (UI-test launches do not scan; its host is .invalid), only
        // so its source page with "Sort by Filename Instead of Server Library Types" can be drawn (addendum #18 B).
        services.ledger.upsertSource(UITestFixtures.serverDefinition)
        try? services.essentials.save(from: services.ledger)
        services.isScanning = true
        try? await UITestFixtures.seed(into: services.sqlite)
        services.isScanning = false
        services.libraryRevision += 1
    }

    /// Where `-UITestOpen <title>` leads: the movie with that title, or the show with that title.
    @MainActor
    static func route(forTitle title: String, in services: AppServices) async -> Route? {
        guard let items = try? await services.store.page(ItemQuery(), limit: 500, offset: 0) else { return nil }
        if let movie = items.first(where: { $0.kind == .movie && $0.title == title }) { return .item(movie.id) }
        if let episode = items.first(where: { $0.seriesTitle == title }), let series = episode.seriesID { return .series(series) }
        return nil
    }

    /// `-UITestTextSize` as a SwiftUI size (rule 17 screenshots); nil when not asked for.
    static var dynamicTypeSize: DynamicTypeSize? {
        switch UITestLaunch.textSize(arguments: ProcessInfo.processInfo.arguments, mode: current) {
        case "xLarge": return .xLarge
        case "xxLarge": return .xxLarge
        case "xxxLarge": return .xxxLarge
        case "accessibility1": return .accessibility1
        case "accessibility2": return .accessibility2
        case "accessibility3": return .accessibility3
        case "accessibility4": return .accessibility4
        case "accessibility5": return .accessibility5
        default: return nil
        }
    }

    /// `-UITestBoldText` (rule 17 screenshots).
    static var boldText: Bool { UITestLaunch.boldText(arguments: ProcessInfo.processInfo.arguments, mode: current) }

    /// `-UITestTab` names are the `AppTabID` raw values (home, movies, shows, files, search, settings).
    static func tab(named name: String?) -> AppTab? {
        name.flatMap(AppTabID.init(rawValue:))
    }
}
#endif
