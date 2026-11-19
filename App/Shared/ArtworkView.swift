import SwiftUI
import AppLogic

/// A poster or still. The picture is found by the artwork resolver (a picture next to the video first, then the matched online
/// poster when the user entered a key); until then, and when there is none, a plain placeholder with a symbol (no invented art).
/// Pictures load through the system image loader with its disk cache capped and kept in Caches (D-DS5).
struct ArtworkView: View {
    let key: String
    let symbol: String
    /// #15 4.1: a 16:9 card (Continue Watching). An episode shows its still; a movie its backdrop, else its poster.
    var wide = false
    @Environment(AppServices.self) private var services
    @State private var result: ArtworkResult = .none

    var body: some View {
        // One shape per card kind (screenshot review item 3c): a 2:3 (or 16:9) frame that the picture FILLS and is clipped
        // to. Before, the filled picture was the frame's child without a clip, so a 16:9 picture (an episode still or a
        // fan-art image) reported its own wider size and its card came out wider than the posters next to it.
        Color.clear
            .aspectRatio(wide ? 16.0 / 9.0 : 2.0 / 3.0, contentMode: .fit)
            .overlay { content }
            .clipped()
            .task(id: "\(key)|\(services.online.keyRevision)|\(wide)") {
                if wide && symbol == "film" {
                    let backdrop = await services.online.backdrop(key: key)
                    if backdrop != .none { result = backdrop; return }
                }
                result = await services.online.resolveArtwork(key: key)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch result {
        case .file(let url), .remote(let url):
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    placeholder
                }
            }
            .asyncImageURLSession(services.online.imageSession)
        case .none:
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: symbol)
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
    }
}
