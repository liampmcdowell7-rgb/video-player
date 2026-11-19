import SwiftUI
import AppLogic

struct EpisodeRowView: View {
    let episode: EpisodeRow

    var body: some View {
        NavigationLink(value: Route.item(episode.id)) {
            // The standard title-and-value row (rule S3): "S1 E3 · Title" on one line (rule S1; the title goes before the
            // code when it does not fit), the time, progress and watched mark as the value.
            LabeledContent {
                if let progress = episode.progress {
                    ProgressView(value: progress)
                }
                if let runtime = episode.runtimeText {
                    Text(runtime)
                }
                // #15 D5: the watched mark always takes its slot, so the runtimes of watched and unwatched rows line up.
                // Fixed in code, verify in next screenshots.
                SymbolColumn(systemImage: "checkmark.circle", isShown: episode.isWatched, accessibilityText: "Watched")
            } label: {
                FittingLine(line: ShortLine([.init(episode.code, priority: 2), .init(episode.title, priority: 1)]), style: .body)
            }
        }
    }
}
