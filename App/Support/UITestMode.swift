#if DEBUG
import Foundation
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
        for base in [fm.urls(for: .cachesDirectory, in: .userDomainMask)[0], fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]] {
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

    static func tab(named name: String?) -> AppTab? {
        switch name {
        case "home": return .home
        case "movies": return .movies
        case "shows": return .shows
        case "files": return .files
        case "discover": return .discover
        case "search": return .search
        case "settings": return .settings
        default: return nil
        }
    }
}
#endif
