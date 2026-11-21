import SwiftUI
import AppLogic

/// The wide picture behind a movie or show page (#15 6.2 and 5.2). Fan art next to the media first, then the matched
/// online backdrop (`ArtworkEngine.backdrop`); with none, the page keeps the system background. Decorative: hidden from
/// VoiceOver.
///
/// R336 (PROVISIONAL, docs/HIG_AUDIT.md T6; supersedes the strengths of R182): the picture is drawn at FULL strength
/// ("Deliver beautiful, edge-to-edge artwork", HIG Designing for tvOS) under the system `regularMaterial`, as Apple's sample
/// "Creating a tvOS media catalog app in SwiftUI" builds a product page ("keep the content's showcase image, with a
/// suitable blur, as a background for the view when scrolling below"; "its defining artwork tinting the content"). The
/// page's text starts at the top, so the material covers the whole picture (the sample's below-the-fold state); the
/// sample's above-the-fold layout (text at the bottom, the top of the picture clear) would move the page's content: R336
/// alternative (b), for the owner. Before: the picture alone at 40 % (15 % with Reduce Transparency) over the system
/// background. The material follows Reduce Transparency and Increase Contrast itself (HIG Materials: "system settings can
/// change its appearance"); its exact look on tvOS 27 is UNVERIFIED.
struct BackdropView: View {
    let artworkKey: String
    @Environment(AppServices.self) private var services
    @State private var result: ArtworkResult = .none

    var body: some View {
        Color.clear
            .overlay { picture }
            .clipped()
            // design-lint:allow a decorative full-bleed background picture holds no content, so it may reach the screen edges
            .ignoresSafeArea()
            .accessibilityHidden(true)
            .task(id: "\(artworkKey)|\(services.online.keyRevision)") {
                result = await services.online.backdrop(key: artworkKey)
            }
    }

    @ViewBuilder
    private var picture: some View {
        switch result {
        case .file(let url), .remote(let url):
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: .fill)
                        .overlay {
                            // design-lint:allow R336: the system regular material over the full-strength backdrop, Apple's tvOS media catalog sample's product page (a standard material in the content layer, HIG Materials; not glass)
                            Rectangle().fill(.regularMaterial)
                        }
                }
            }
        case .none:
            EmptyView()
        }
    }
}
