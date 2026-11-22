import SwiftUI
import AppLogic
import MetadataOnline

/// Discover: titles the user does not own yet. Missing episodes of shows they have, the rest of a collection, titles similar to
/// what they watch, and their watchlist, each with where to watch in their region. Works only with the user's own key: with
/// none, it says exactly what is needed and sends nothing (docs/ARTWORK_DISCOVER.md).
///
/// Shown in the Search tab below the search field while the field is empty (OPEN_QUESTIONS R167, option (c), PROVISIONAL;
/// AppLogic `SearchTabContent`). The Search tab owns the model (`DiscoverLoader`), so typing and clearing the field does
/// not load Discover again.
struct DiscoverView: View {
    let loader: DiscoverLoader

    var body: some View {
        if let model = loader.model {
            ScreenStateView(state: model.screen.state, onRetry: { Task { await loader.reload() } }) { content in
                DiscoverContentView(content: content, loader: loader, onToggle: { title in
                    Task { await model.run { $0.toggleWatchlist(title) } }
                })
            }
        } else {
            LoadingView()
        }
    }
}

/// Discover's model, kept by the Search tab. Loads only when asked (the Search field is empty and Discover is on), and again
/// only when the library or the key changed since the last load.
@MainActor @Observable
final class DiscoverLoader {
    private(set) var model: ScreenModel<DiscoverViewModel>?
    @ObservationIgnored private var loadedFor: String?
    @ObservationIgnored private weak var services: AppServices?

    /// Loads when `stamp` (library and key revision) differs from the last load.
    func loadIfNeeded(services: AppServices) async {
        self.services = services
        let stamp = "\(services.libraryRevision)|\(services.online.keyRevision)"
        guard stamp != loadedFor else { return }
        loadedFor = stamp
        await reload()
    }

    func reload() async {
        guard let services else { return }
        var source: (any DiscoverDataSource)? = services.online.discoverSource
        var library: any DiscoverLibraryProviding = StoreDiscoverLibrary(store: services.store)
        #if DEBUG
        // R342: the screenshot job's invented Discover (`-UITestFakeDiscover`; no key, no network). Not in Release.
        if UITestLaunch.usesFakeDiscover(arguments: ProcessInfo.processInfo.arguments, mode: UITestMode.current) {
            source = UITestFixtureDiscover.Source()
            library = UITestFixtureDiscover.Library()
        }
        #endif
        let screen = DiscoverViewModel(source: source, library: library,
                                       watchlist: LedgerWatchlist(ledger: services.ledger), region: services.online.region)
        if model == nil { model = ScreenModel(screen) }
        await model?.run { $0 = screen; await $0.load() }
    }
}

private struct DiscoverContentView: View {
    let content: DiscoverContent
    let loader: DiscoverLoader
    let onToggle: (DiscoverTitle) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                ForEach(content.problems, id: \.self) { problem in
                    Text(problem)
                        .foregroundStyle(.secondary)
                }
                if !content.watchlist.isEmpty {
                    shelf("Your Watchlist", content.watchlist)
                }
                if !content.missingEpisodes.isEmpty {
                    Text("Missing Episodes")
                        .font(.title3)
                    ForEach(content.missingEpisodes) { group in
                        MissingEpisodesView(group: group, region: content.region)
                    }
                }
                ForEach(content.collectionGaps) { gap in
                    shelf("More from \(gap.name)", gap.missing, caption: "You have \(gap.ownedCount) of this collection.")
                }
                if !content.similar.isEmpty {
                    shelf("Similar to Your Library", content.similar)
                }
                // #26 item 7: the TMDB notice is in Settings > About > Data Sources only; the JustWatch line stays with its data.
                Text(Attribution.whereToWatchNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollClipDisabled()
    }

    private func shelf(_ title: String, _ titles: [DiscoverTitle], caption: String? = nil) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.title3)
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                // design-lint:allow HIG Layout, 40 pt horizontal spacing between posters (docs/DESIGN_SYSTEM.md section 4)
                LazyHStack(alignment: .top, spacing: 40) {
                    ForEach(titles) { item in
                        DiscoverCard(title: item, region: content.region, loader: loader, onToggle: { onToggle(item) })
                            // design-lint:allow HIG Layout, six columns of the grid so shelf posters line up with grid posters
                            .containerRelativeFrame(.horizontal, count: 6, spacing: 40)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }
}

/// One suggested title; the line below says where to watch. R342 (Decided by the owner, 21 Nov 2026; docs/HIG_AUDIT.md
/// T12): Select on the poster opens the title's page (`DiscoverTitlePage`), as a poster does everywhere else; adding to
/// or removing from the watchlist is in the card's context menu (press and hold; SwiftUI `contextMenu(menuItems:)`; HIG
/// Context menus, read 21 Nov 2026: "functionality that's directly related to an item", and "Always make context menu items
/// available in the main interface, too", which the page's button does).
private struct DiscoverCard: View {
    let title: DiscoverTitle
    let region: String
    let loader: DiscoverLoader
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            NavigationLink {
                DiscoverTitlePage(loader: loader, shown: title, region: region)
            } label: {
                ArtworkView(key: title.artworkKey, symbol: title.kind == .movie ? "film" : "tv")
            }
            .buttonStyle(.card)
            .accessibilityLabel(title.title)
            .accessibilityHint(DiscoverCardText.cardHint)
            .contextMenu {
                let action = DiscoverCardText.watchlistAction(title)
                Button(action.label, systemImage: action.symbol, action: onToggle)
            }
            FittingText(title.title, style: .caption)
            // Rule S1: "2021 · Because you watched …" on one line; the year goes first when it does not fit.
            FittingLine(line: DiscoverCardText.detailLine(title), style: .caption2)
                .foregroundStyle(.secondary)
            if title.onWatchlist {
                Label("On Your Watchlist", systemImage: "checkmark")
                    .font(.caption2)
            }
            Text(WhereToWatchText.line(title.watch, region: region))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }
}

private struct MissingEpisodesView: View {
    let group: MissingEpisodesGroup
    let region: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(group.seriesTitle)
                .font(.headline)
            Text(WhereToWatchText.line(group.watch, region: region))
                .font(.caption)
                .foregroundStyle(.secondary)
            // R379 (audit #29; HIG Focus and selection: "people can bring focus to every element"): each line is a plain
            // focusable row, so a swipe moves down the list and the scroll view follows the focus. Which lines and their
            // text: AppLogic `MissingEpisodeLines` (Linux tests). No look of our own: the system draws the focus.
            ForEach(MissingEpisodeLines.lines(group)) { (line: MissingEpisodeLine) in
                Text(line.text)
                    .font(.callout)
                    // design-lint:allow R379: a read-only line takes the system focus so the Siri Remote can scroll the list (as About's text rows)
                    .focusable(line.isFocusable)
            }
        }
        // R379, WWDC21 "Direct and reflect focus in SwiftUI": with `focusSection()` "the frame of that view becomes capable
        // of accepting focus if it contains any focusable subviews". The group spans the column, so a swipe down from any
        // poster of the shelf above lands in the list even when no line sits under that poster.
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }
}

/// The one sentence under a title about where to watch it.
enum WhereToWatchText {
    static func line(_ watch: WhereToWatch?, region: String) -> String {
        guard let watch else { return "Where to watch: not listed for \(region)." }
        return "Where to watch (\(watch.region)): \(watch.summary)"
    }
}
