import SwiftUI
import AppLogic

/// The show page (#15 5.1, 5.2): backdrop, the title (or its title logo, #15 Part 9), Play and More as buttons (as on the
/// movie page), then one shelf of 16:9 episode cards per season.
///
/// 5.1: only the show-wide mark that changes something is offered, inside More; the "X of Y watched" summary is secondary
/// text under each season's name (R180). 5.2 (OPEN_QUESTIONS R189, PROVISIONAL): every season is its own shelf, so no
/// season menu is needed and nothing is hidden behind one; an episode card shows its still (or the show's picture), the
/// progress inside it, "E1 · Title", the duration and the watched mark. There is no per-episode synopsis in the library
/// index, so the card has none. Fixed in code, verify in next screenshots (55, 56).
struct SeasonsList: View {
    let content: SeasonsContent
    let seriesID: Int64
    let model: ScreenModel<SeasonsViewModel>
    var onPlay: (Int64) -> Void
    @FocusState private var playFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                TitleHeader(title: content.seriesTitle, artworkKey: "series-\(seriesID)")
                actions
                ForEach(content.seasons) { season in
                    VStack(alignment: .leading) {
                        Text(season.title)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        StatusText(season.summary)
                        ScrollView(.horizontal) {
                            // design-lint:allow HIG Layout, 40 pt horizontal spacing between cards (docs/DESIGN_SYSTEM.md section 4)
                            LazyHStack(alignment: .top, spacing: 40) {
                                ForEach(season.episodes) { episode in
                                    EpisodeCard(episode: episode, model: model)
                                        // design-lint:allow HIG Layout, four columns of the grid width for 16:9 episode cards (R189)
                                        .containerRelativeFrame(.horizontal, count: 4, spacing: 40)
                                }
                            }
                        }
                        .scrollClipDisabled()
                    }
                }
            }
        }
        .defaultFocus($playFocused, true)
        // #15 5.2: the show's fan art (or its matched online backdrop) behind the page, as on the movie page.
        .background { BackdropView(artworkKey: "series-\(seriesID)") }
        .pushedScreen(content.seriesTitle)
    }

    private var actions: some View {
        HStack {
            if let resume = content.resumeEpisodeID {
                Button { onPlay(resume) } label: { SlotLabel(content.playTitle, systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
                    .focused($playFocused)
            }
            if content.canMarkWatched || content.canMarkUnwatched {
                Menu {
                    if content.canMarkWatched {
                        Button("Mark Show as Watched", systemImage: "eye") {
                            Task { await model.run { await $0.markSeries(watched: true) } }
                        }
                    }
                    if content.canMarkUnwatched {
                        Button("Mark Show as Unwatched", systemImage: "eye.slash") {
                            Task { await model.run { await $0.markSeries(watched: false) } }
                        }
                    }
                } label: {
                    SlotLabel("More", systemImage: "ellipsis")
                }
            }
        }
    }
}

/// One episode as a 16:9 card: the still is the button (system `.card` style), the text sits below it, as on Home.
private struct EpisodeCard: View {
    let episode: EpisodeRow
    let model: ScreenModel<SeasonsViewModel>

    var body: some View {
        VStack(alignment: .leading) {
            NavigationLink(value: Route.item(episode.id)) {
                ArtworkView(key: episode.artworkKey, symbol: "tv", wide: true)
                    .overlay(alignment: .bottom) {
                        if let progress = episode.progress {
                            ProgressView(value: progress)
                                .padding()
                        }
                    }
            }
            .buttonStyle(.card)
            .accessibilityLabel("\(episode.code), \(episode.title)")
            .accessibilityValue([episode.runtimeText, episode.isWatched ? "Watched" : nil].compactMap { $0 }.joined(separator: ", "))
            .contextMenu {
                Button(episode.isWatched ? "Mark as Unwatched" : "Mark as Watched", systemImage: episode.isWatched ? "eye.slash" : "eye") {
                    Task { await model.run { await $0.setWatched(!episode.isWatched, episodeID: episode.id) } }
                }
            }
            VStack(alignment: .leading) {
                // Rule S1: "S1 E3 · Title" on one line; the code goes first when it does not fit.
                FittingLine(line: ShortLine([.init(episode.code, priority: 2), .init(episode.title, priority: 1)]), style: .caption)
                HStack {
                    if let runtime = episode.runtimeText {
                        FittingText(runtime, style: .caption2)
                            .foregroundStyle(.secondary)
                    }
                    // #15 D5: the watched mark keeps its slot.
                    SymbolColumn(systemImage: "checkmark.circle", isShown: episode.isWatched, accessibilityText: "Watched")
                }
            }
            .padding(.horizontal)
        }
    }
}
