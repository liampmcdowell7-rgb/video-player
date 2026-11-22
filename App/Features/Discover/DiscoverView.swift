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
                    ShelfHeader("Missing Episodes")
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
            ShelfHeader(title)
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
            // R402 (owner's review of the run on f0a67d3, item 4; PROVISIONAL): room above the cards for the lifted
            // lockup, as on Home's shelves (`RowSpacing.shelfFocusRoom`).
            .padding(.top, CGFloat(RowSpacing.shelfFocusRoom))
            // R402 (item 4): the shelf is as tall as its cards with their tallest caption, plus room under it for the
            // lifted lockup, so the focused card's caption no longer runs over the next shelf's header or the
            // where-to-watch line under the last shelf (75-discover-card-menu, 75-search-discover-cards). UNVERIFIED
            // until a run.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, CGFloat(RowSpacing.shelfFocusRoom))
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

    /// R393 (item 10 of the owner's review of the run on fd9731f): the card is the same lockup as every other poster
    /// (Apple's sample, "Create content lockups": `.borderless`, the image and the text as siblings in the label, so
    /// "the button's title ... automatically move[s] out of the way of the button's image as it scales up on focus").
    /// Cause of the fault: the poster alone was a `.card` button and the title stood outside it, so the focused, larger
    /// poster covered its own title (75-discover-card-menu). The three titles had three sizes because each one was
    /// scaled to its own width (`FittingText`); now every title is the Caption style, wrapped when it is long.
    var body: some View {
        NavigationLink {
            DiscoverTitlePage(loader: loader, shown: title, region: region)
        } label: {
            ArtworkView(key: title.artworkKey, symbol: title.kind == .movie ? "film" : "tv")
                // design-lint:allow R393: Apple's tvOS media catalog sample attaches the borderless lockup's highlight by hand to a custom artwork view; the system effect, not our own
                .hoverEffect(.highlight)
            VStack(alignment: .leading) {
                // R402 (item 4): rule S1, the same caption as every lockup (`CardCaption`): one line in Caption, else one
                // line in Caption 2 (the floor), and only a title that does not fit even there wraps. R393 had every
                // title wrap in Caption, so short titles broke ("Sample / Suggestion 1"). Titles of one shelf may now
                // differ in size (R393's reason for one size; its alternative (f)).
                CardCaption(text: title.title)
                // Rule S1: "2021 · Because you watched …" on one line; the year goes first when it does not fit.
                FittingLine(line: DiscoverCardText.detailLine(title), style: .caption2)
                    .foregroundStyle(.secondary)
                if title.onWatchlist {
                    Label("On Your Watchlist", systemImage: "checkmark")
                        .font(.caption2)
                }
                // R396 (audit Q5): the where-to-watch sentence (up to three lines) is no longer under the card; it is
                // on the title's page, which Select opens (`DiscoverTitlePage`). The caption is the title and one line.
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title.title)
        .accessibilityHint(DiscoverCardText.cardHint)
        .contextMenu {
            let action = DiscoverCardText.watchlistAction(title)
            Button(action.label, systemImage: action.symbol, action: onToggle)
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
