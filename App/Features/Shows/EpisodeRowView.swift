import SwiftUI
import AppLogic

struct EpisodeRowView: View {
    let episode: EpisodeRow

    var body: some View {
        NavigationLink(value: Route.item(episode.id)) {
            HStack {
                Text(episode.code)
                    .foregroundStyle(.secondary)
                Text(episode.title)
                Spacer()
                if let progress = episode.progress {
                    ProgressView(value: progress)
                }
                if let runtime = episode.runtimeText {
                    Text(runtime)
                        .foregroundStyle(.secondary)
                }
                if episode.isWatched {
                    Image(systemName: "checkmark.circle")
                        .accessibilityLabel("Watched")
                }
            }
        }
    }
}
