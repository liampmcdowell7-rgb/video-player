import SwiftUI
import AppLogic

/// The loaded detail page. Everything reachable is a button or a menu, so the remote can scroll to all of it.
struct ItemDetailContentView: View {
    let content: ItemDetailContent
    let model: ScreenModel<ItemDetailViewModel>
    var onPlay: (Bool) -> Void
    var onFixMatch: () -> Void
    var onSortInfo: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                if let series = content.seriesTitle, let seriesID = content.seriesID {
                    NavigationLink(series, value: Route.series(seriesID))
                }
                // Rule S1: one line each, scaled to the readable minimum, never cut or wrapped.
                Text(content.title)
                    .font(.largeTitle)
                    .lineLimit(1)
                    // design-lint:allow rule S1 (OPEN_QUESTIONS R165): the system text style shrinks to fit, never below Apple's 23 pt minimum (HIG Typography)
                    .minimumScaleFactor(ShortLine.minimumScale(forPointSize: TVTextStyle.title1.pointSize))
                if !content.facts.isEmpty {
                    FittingText(content.facts, style: .body)
                        .foregroundStyle(.secondary)
                }
                if !content.badges.isEmpty {
                    FittingLine(line: ShortLine(ordered: content.badges), style: .callout)
                        .foregroundStyle(.secondary)
                }
                if let progress = content.progress {
                    ProgressView(value: progress)
                }
                actions
            }
        }
        .navigationTitle(content.title)
    }

    private var actions: some View {
        HStack {
            Button { onPlay(false) } label: { Label(content.playTitle, systemImage: "play.fill") }
                .buttonStyle(.borderedProminent)
            if content.canStartOver {
                Button("Start Over", systemImage: "arrow.counterclockwise") { onPlay(true) }
                    .buttonStyle(.bordered)
            }
            if content.versions.count > 1 {
                VersionsMenu(versions: content.versions, model: model)
            }
            if !content.extras.isEmpty {
                ExtrasMenu(extras: content.extras)
            }
            moreMenu
        }
    }

    private var moreMenu: some View {
        Menu("More", systemImage: "ellipsis") {
            Button(content.isWatched ? "Mark as Unwatched" : "Mark as Watched", systemImage: content.isWatched ? "eye.slash" : "eye") {
                Task { await model.run { await $0.setWatched(!content.isWatched) } }
            }
            Button(content.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: content.isFavorite ? "heart.slash" : "heart") {
                Task { await model.run { await $0.toggleFavorite() } }
            }
            Button("Fix Match", systemImage: "magnifyingglass", action: onFixMatch)
            // docs/SORTING.md: which rule put this title in Movies or Shows, with Move and Sort Automatically.
            Button("How This Was Sorted", systemImage: "arrow.up.arrow.down", action: onSortInfo)
        }
    }
}
