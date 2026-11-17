import SwiftUI
import AppLogic

/// The seasons of a show as a list: a header row with Play and the show-wide actions, then one section per season.
struct SeasonsList: View {
    let content: SeasonsContent
    let model: ScreenModel<SeasonsViewModel>
    var onPlay: (Int64) -> Void

    var body: some View {
        List {
            Section {
                if let resume = content.resumeEpisodeID {
                    Button { onPlay(resume) } label: { Label(content.playTitle, systemImage: "play.fill") }
                }
                Button("Mark Show as Watched", systemImage: "eye") {
                    Task { await model.run { await $0.markSeries(watched: true) } }
                }
                Button("Mark Show as Unwatched", systemImage: "eye.slash") {
                    Task { await model.run { await $0.markSeries(watched: false) } }
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
        .navigationTitle(content.seriesTitle)
    }
}
