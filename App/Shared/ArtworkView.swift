import SwiftUI
import AppLogic

/// A poster or still. The picture is found by the artwork resolver (a picture next to the video first, then the matched online
/// poster when the user entered a key); until then, and when there is none, a plain placeholder with a symbol (no invented art).
/// Pictures load through the system image loader with its disk cache capped and kept in Caches (D-DS5).
struct ArtworkView: View {
    let key: String
    let symbol: String
    @Environment(AppServices.self) private var services
    @State private var result: ArtworkResult = .none

    var body: some View {
        content
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .task(id: "\(key)|\(services.online.keyRevision)") {
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
