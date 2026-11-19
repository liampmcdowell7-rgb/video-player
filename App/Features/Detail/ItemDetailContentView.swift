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
                // #15 Part 9: a movie's title logo when one is found and the setting is on; otherwise the text title (rule S1).
                TitleHeader(title: content.title, artworkKey: content.kind == .movie ? content.artworkKey : nil)
                if !content.facts.isEmpty {
                    FittingText(content.facts, style: .body)
                        .foregroundStyle(.secondary)
                }
                if !content.badges.isEmpty {
                    FittingLine(line: CardBuilder.badgeLine(content.badges), style: .callout)
                        .foregroundStyle(.secondary)
                }
                // #15 D3: how much is left, as text, instead of a full-width bar. Fixed in code, verify in next screenshots.
                if let timeLeft = content.timeLeft {
                    StatusText(timeLeft)
                }
                actions
            }
        }
        .pushedScreen(content.title)
    }

    private var actions: some View {
        // #15 D2: every button in the row uses `SlotLabel`, so the symbol slot, and with it the button height, is the same.
        HStack {
            Button { onPlay(false) } label: { SlotLabel(content.playTitle, systemImage: "play.fill") }
                .buttonStyle(.borderedProminent)
            if content.canStartOver {
                Button { onPlay(true) } label: { SlotLabel("Start Over", systemImage: "arrow.counterclockwise") }
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
        Menu {
            Button(content.isWatched ? "Mark as Unwatched" : "Mark as Watched", systemImage: content.isWatched ? "eye.slash" : "eye") {
                Task { await model.run { await $0.setWatched(!content.isWatched) } }
            }
            Button(content.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: content.isFavorite ? "heart.slash" : "heart") {
                Task { await model.run { await $0.toggleFavorite() } }
            }
            Button("Fix Match", systemImage: "magnifyingglass", action: onFixMatch)
            // docs/SORTING.md: which rule put this title in Movies or Shows, with Move and Sort Automatically.
            Button("How This Was Sorted", systemImage: "arrow.up.arrow.down", action: onSortInfo)
        } label: {
            SlotLabel("More", systemImage: "ellipsis")
        }
    }
}
