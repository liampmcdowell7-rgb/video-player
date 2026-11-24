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
    /// R452: where the page's first line of text begins (global y, from `ArtTextTop`); the cover starts one ramp above it
    /// (`ArtReadability.coverStart`), not at a fixed share of the picture. Nil until the page has measured it.
    var textTop: CGFloat? = nil
    @State private var height: CGFloat = 0
    @Environment(AppServices.self) private var services
    @State private var result: ArtworkResult = .none

    var body: some View {
        Color.clear
            .overlay { picture }
            .clipped()
            // design-lint:allow a decorative full-bleed background picture holds no content, so it may reach the screen edges
            .ignoresSafeArea()
            .accessibilityHidden(true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
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

    /// The cover over the picture (see `BackdropStyle`).
    @ViewBuilder
    private var cover: some View {
            switch style {
            case .page:
                // design-lint:allow R336: the system regular material over the full-strength backdrop, Apple's tvOS media catalog sample's product page (a standard material in the content layer, HIG Materials; not glass)
                Rectangle().fill(.regularMaterial)
            case .hero:
                // R452: the system material under a masked gradient (Apple's sample), plus our black cover under
                // the text: Apple states no darkening for a material, so the contrast proof (ArtReadabilityTests)
                // counts none and needs the cover. Both start where the text starts (`ArtReadability.coverStart`).
                let start: Double = ArtReadability.coverStart(textTop: textTop.map { Double($0) }, height: Double(height))
                let full: Double = min(start + ArtReadability.rampFraction, 1)
                ZStack {
                    // design-lint:allow R349, R350: the system regular material over the lower part of the artwork only, the sample's material gradient
                    Rectangle().fill(.regularMaterial)
                        .mask {
                            LinearGradient(stops: [.init(color: .clear, location: start), .init(color: .primary, location: full)],
                                           startPoint: .top, endPoint: .bottom)
                        }
                    // design-lint:allow R452: our own cover where the system material alone does not prove 4.5:1 (ArtReadability)
                    LinearGradient(stops: [.init(color: .black.opacity(0), location: start), .init(color: .black.opacity(ArtReadability.scrimMaxOpacity), location: full)], startPoint: .top, endPoint: .bottom)
                }
            }
    }

    @ViewBuilder
    private var picture: some View {
        switch result {
        case .file(let url), .remote(let url):
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: .fill)
                        .overlay { cover }
                }
            }
        case .none:
            // R452: only the readability picture (`-UITestBrightBackdrop`, debug UI-test mode): a plain white picture, no network.
            // design-lint:allow R452: a white test picture (debug UI-test mode only), the brightest artwork there can be
            if UITestMode.brightBackdrop { Color.white.overlay { cover } } else { EmptyView() }
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
