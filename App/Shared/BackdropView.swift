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
    /// R349, R350: `.hero` (Home's featured area and, since R350, the movie and show pages: the picture clear at the top,
    /// the material rising over its lower part, where the title and buttons are) or `.page` (the material over the whole
    /// picture, R336; no screen uses it since R350, kept as R350's alternative (a)).
    var style: BackdropStyle = .page
    /// R387: the episode page's hero is the episode's own still (`OnlineServices.episodeStill`), not the show's backdrop;
    /// the show's backdrop only when the episode has no still, never its poster.
    var prefersEpisodeStill = false
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
                result = await load()
            }
    }

    private func load() async -> ArtworkResult {
        if prefersEpisodeStill {
            let still = await services.online.episodeStill(key: artworkKey)
            switch still {
            case .file, .remote: return still
            case .none: break
            }
        }
        return await services.online.backdrop(key: artworkKey)
    }

    @ViewBuilder
    private var picture: some View {
        switch result {
        case .file(let url), .remote(let url):
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: .fill)
                        .overlay {
                            switch style {
                            case .page:
                                // design-lint:allow R336: the system regular material over the full-strength backdrop, Apple's tvOS media catalog sample's product page (a standard material in the content layer, HIG Materials; not glass)
                                Rectangle().fill(.regularMaterial)
                            case .hero:
                                // design-lint:allow R349, R350: the system regular material over the lower part of the artwork only (Home's featured area, the movie and show pages), so the title, metadata and buttons stay readable while the top of the picture stays clear (the TV app's featured area and product pages); the mask is the material's shape, not a colour of ours
                                Rectangle().fill(.regularMaterial)
                                    .mask {
                                        LinearGradient(stops: [.init(color: .clear, location: BackdropStyle.heroClearTop),
                                                               .init(color: .primary, location: 1)],
                                                       startPoint: .top, endPoint: .bottom)
                                    }
                            }
                        }
                }
            }
        case .none:
            EmptyView()
        }
    }
}

/// R349: how the backdrop's picture is covered (see `BackdropView.style`).
enum BackdropStyle {
    case page
    case hero

    /// R349, R350 (PROVISIONAL): the hero artwork is fully clear above this share of its height; the material rises from
    /// there to the bottom edge. Our choice (Apple publishes none); the owner's photos of the TV app decide.
    static let heroClearTop: CGFloat = 0.35
}
