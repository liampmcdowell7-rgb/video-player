import SwiftUI
import AppLogic

/// R342 (Decided by the owner, 21 Nov 2026; docs/HIG_AUDIT.md T12): the page a Discover card opens, as Select on a poster
/// opens a title everywhere else. The title is not in the library, so the page shows what Discover already has: the
/// poster, the title, year and why it is suggested, where to watch it, and the watchlist button (the same action as the
/// card's context menu). Nothing new is requested for it. The title is read from Discover's model by id, so a change made
/// from the context menu or here shows on both. A pushed page (rule D1). How close this is to the TV app's title page
/// on tvOS 27 is UNVERIFIED.
struct DiscoverTitlePage: View {
    let loader: DiscoverLoader
    /// The title as the card showed it, used when it is no longer listed (for example after a reload).
    let shown: DiscoverTitle
    let region: String

    private var title: DiscoverTitle { loader.model?.screen.state.content?.title(id: shown.id) ?? shown }

    var body: some View {
        HStack(alignment: .top) {
            ArtworkView(key: title.artworkKey, symbol: title.kind == .movie ? "film" : "tv")
                // design-lint:allow HIG Layout, the poster one fourth of the page width, as a grid column of four
                .containerRelativeFrame(.horizontal, count: 4, spacing: 40)
            VStack(alignment: .leading) {
                // Rule S1: one line, scaled to fit, never cut.
                FittingText(title.title, style: .title2)
                    .accessibilityAddTraits(.isHeader)
                FittingLine(line: DiscoverCardText.detailLine(title), style: .callout)
                    .foregroundStyle(.secondary)
                Text(DiscoverCardText.kindText(title))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(WhereToWatchText.line(title.watch, region: region))
                    .font(.callout)
                let action = DiscoverCardText.watchlistAction(title)
                Button(action.label, systemImage: action.symbol) { toggle() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(ControlID.discoverWatchlist)
            }
        }
        .pushedScreen(title.title)
    }

    private func toggle() {
        let current = title
        Task { await loader.model?.run { $0.toggleWatchlist(current) } }
    }
}
