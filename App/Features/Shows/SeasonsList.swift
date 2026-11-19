import SwiftUI
import AppLogic

/// The seasons of a show: the title (or its title logo, #15 Part 9), Play and More, then one section per season.
///
/// #15 5.1: only the show-wide mark that changes something is offered, inside More (as on the movie page); the "X of Y
/// watched" summary stays secondary footer text under each season. PROVISIONAL (OPEN_QUESTIONS R180): the seasons stay
/// sections of one list; the 16:9 episode shelf of #15 5.2 waits for episode stills (docs/ARTWORK_AUDIT.md).
struct SeasonsList: View {
    let content: SeasonsContent
    let seriesID: Int64
    let model: ScreenModel<SeasonsViewModel>
    var onPlay: (Int64) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            TitleHeader(title: content.seriesTitle, artworkKey: "series-\(seriesID)")
            List {
                Section {
                    if let resume = content.resumeEpisodeID {
                        Button { onPlay(resume) } label: { SlotLabel(content.playTitle, systemImage: "play.fill") }
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
                ForEach(content.seasons) { season in
                    Section {
                        ForEach(season.episodes) { episode in
                            EpisodeRowView(episode: episode)
                                .contextMenu {
                                    Button(episode.isWatched ? "Mark as Unwatched" : "Mark as Watched", systemImage: episode.isWatched ? "eye.slash" : "eye") {
                                        Task { await model.run { await $0.setWatched(!episode.isWatched, episodeID: episode.id) } }
                                    }
                                }
                        }
                    } header: {
                        Text(season.title)
                    } footer: {
                        Text(season.summary)
                    }
                }
            }
        }
        .pushedScreen(content.seriesTitle)
    }
}
