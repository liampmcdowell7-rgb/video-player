import SwiftUI
import AppLogic
import MetadataOnline

/// Discover: titles the user does not own yet. Missing episodes of shows they have, the rest of a collection, titles similar to
/// what they watch, and their watchlist, each with where to watch in their region. Works only with the user's own key: with
/// none, it says exactly what is needed and sends nothing (docs/ARTWORK_DISCOVER.md).
struct DiscoverView: View {
    @Environment(AppServices.self) private var services
    @State private var model: ScreenModel<DiscoverViewModel>?

    var body: some View {
        Group {
            if let model {
                ScreenStateView(state: model.screen.state, onRetry: { Task { await reload() } }) { content in
                    DiscoverContentView(content: content, onToggle: { title in
                        Task { await model.run { $0.toggleWatchlist(title) } }
                    })
                }
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Discover")
        .task(id: "\(services.libraryRevision)|\(services.online.keyRevision)") { await reload() }
    }

    private func reload() async {
        let screen = DiscoverViewModel(source: services.online.discoverSource, library: StoreDiscoverLibrary(store: services.store),
                                       watchlist: LedgerWatchlist(ledger: services.ledger), region: services.online.region)
        if model == nil { model = ScreenModel(screen) }
        await model?.run { $0 = screen; await $0.load() }
    }
}

private struct DiscoverContentView: View {
    let content: DiscoverContent
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
                Text(Attribution.catalogueNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        DiscoverCard(title: item, region: content.region, onToggle: { onToggle(item) })
                            // design-lint:allow HIG Layout, six columns of the grid so shelf posters line up with grid posters
                            .containerRelativeFrame(.horizontal, count: 6, spacing: 40)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }
}

/// One suggested title. Choosing the poster adds it to the watchlist or removes it; the line below says where to watch.
private struct DiscoverCard: View {
    let title: DiscoverTitle
    let region: String
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Button(action: onToggle) {
                ArtworkView(key: title.artworkKey, symbol: title.kind == .movie ? "film" : "tv")
            }
            .buttonStyle(.card)
            .accessibilityLabel(title.title)
            .accessibilityHint(title.onWatchlist ? "Removes it from your watchlist" : "Adds it to your watchlist")
            Text(title.title)
                .font(.caption)
                .lineLimit(1)
            Text(title.year.map { "\($0) · \(title.reason)" } ?? title.reason)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
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
            ForEach(group.episodes) { episode in
                Text(line(episode))
                    .font(.callout)
            }
        }
    }

    private func line(_ e: MissingEpisode) -> String {
        let base = "\(e.code)  \(e.name)"
        guard let date = e.airDate else { return base }
        return "\(base)  (aired \(date))"
    }
}

/// The one sentence under a title about where to watch it.
enum WhereToWatchText {
    static func line(_ watch: WhereToWatch?, region: String) -> String {
        guard let watch else { return "Where to watch: not listed for \(region)." }
        return "Where to watch (\(watch.region)): \(watch.summary)"
    }
}
