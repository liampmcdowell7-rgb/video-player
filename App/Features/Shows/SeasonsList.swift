import SwiftUI
import AppLogic

/// The show page (#15 5.1, 5.2): backdrop, the title (or its title logo, #15 Part 9), the synopsis, Play and More as buttons,
/// the cast (#22 B: synopsis and cast as on the movie page, nothing when there are no details), then one shelf of 16:9
/// episode cards per season.
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
    @Environment(AppServices.self) private var services
    /// #22 B (OPEN_QUESTIONS R193): the show's synopsis and cast, from the same details lookup as the movie page. Nil (no
    /// key, no match, or both empty) draws nothing: no empty band (rule L6).
    @State private var details: TitleDetails?
    @FocusState private var playFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                TitleHeader(title: content.seriesTitle, artworkKey: "series-\(seriesID)")
                // As on the movie page: the synopsis above the buttons (three lines, the whole text one press away).
                if let overview = details?.overview {
                    SynopsisLink(title: content.seriesTitle, text: overview)
                }
                actions
                // #25 B7 (OPEN_QUESTIONS R193, the alternative now taken, still PROVISIONAL): the episode shelves right after
                // Play, the cast after the last season.
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
                if let cast = details?.cast, !cast.isEmpty {
                    CastShelf(cast: cast)
                }
            }
        }
        .defaultFocus($playFocused, true)
        // #25 B10: as on the movie page, Play takes the focus once the page is on screen (a page pushed at launch kept the
        // tab bar's focus).
        .task(id: seriesID) { playFocused = true }
        // #15 5.2: the show's fan art (or its matched online backdrop) behind the page, as on the movie page.
        .background { BackdropView(artworkKey: "series-\(seriesID)") }
        .task(id: "series-\(seriesID)|\(services.online.keyRevision)") {
            details = await services.online.details(key: "series-\(seriesID)")
        }
        .pushedScreen(content.seriesTitle)
    }

    private var actions: some View {
        ActionRow {
            if let resume = content.resumeEpisodeID {
                Button { onPlay(resume) } label: { ActionLabel(content.playTitle, systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
                    .focused($playFocused)
                    .accessibilityIdentifier(ControlID.play)
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
                    ActionLabel("More", systemImage: "ellipsis")
                }
                .accessibilityLabel("More")
                .accessibilityIdentifier(ControlID.more)
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
                // #25 B7: always "S2 E1 · Title" (the title is "Episode 1" when the file names none, never the code again).
                // One line under rule S1: scaled to fit, never cut (FittingText; R199 for a title that is very long).
                FittingText(episode.code + " · " + episode.title, style: .caption)
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
