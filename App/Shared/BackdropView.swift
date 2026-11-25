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
    /// R471 item 1: the page is scrolled below its hero, so the picture becomes a blurred, dimmed copy (`ProductScroll`):
    /// the system material and one uniform cover over the whole picture. Only for `.hero`.
    var belowHero: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var height: CGFloat = 0
    /// R470: this view's own top in global coordinates (the text's top is global too).
    @State private var top: CGFloat = 0
    @Environment(AppServices.self) private var services
    @State private var result: ArtworkResult = .none

    var body: some View {
        Color.clear
            .overlay { picture }
            .clipped()
            // design-lint:allow a decorative full-bleed background picture holds no content, so it may reach the screen edges
            .ignoresSafeArea()
            .accessibilityHidden(true)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { (frame: CGRect) in
                // R471 (50): written only on a change of half a point or more, so the cover's stops are not rebuilt for less.
                if abs(frame.height - height) >= 0.5 { height = frame.height }
                if abs(frame.minY - top) >= 0.5 { top = frame.minY }
            }
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
                // R470: the text's top is in global coordinates; the picture's own top (it ignores the safe area) is taken off,
                // so the share is of THIS view's height. The fade is eased (`ArtReadability.coverStops`), long, and at full
                // strength at the first line of the text column (the series line on an episode page), not at the title.
                let start: Double = ArtReadability.coverStart(textTop: textTop.map { Double($0 - top) }, height: Double(height))
                let stops: [(location: Double, alpha: Double)] = ArtReadability.coverStops(start: start)
                ZStack {
                    // design-lint:allow R349, R350: the system regular material over the lower part of the artwork only, the sample's material gradient
                    Rectangle().fill(.regularMaterial)
                        .mask {
                            // design-lint:allow R470: the mask that fades the system material in on the same eased curve as the cover (black here is mask alpha, not a colour)
                            LinearGradient(stops: stops.map { Gradient.Stop(color: .black.opacity($0.alpha / ArtReadability.scrimMaxOpacity), location: $0.location) },
                                           startPoint: .top, endPoint: .bottom)
                        }
                    // design-lint:allow R452: our own cover where the system material alone does not prove 4.5:1 (ArtReadability)
                    LinearGradient(stops: stops.map { Gradient.Stop(color: .black.opacity($0.alpha), location: $0.location) }, startPoint: .top, endPoint: .bottom)
                    // R471 item 1: below the hero, the whole picture under the material and the cover's full strength.
                    // R471 (50): in the tree only while it shows (it fades in and out as before); kept at opacity 0 it was a
                    // second full-screen material composited on every frame of the hero.
                    if belowHero {
                        ZStack {
                            // design-lint:allow R471: the system regular material over the whole picture once the page is scrolled below its hero (the blurred copy of Apple's product page)
                            Rectangle().fill(.regularMaterial)
                            // design-lint:allow R471: one uniform cover at the strength the hero cover is proved at (ProductScroll.belowHeroCoverOpacity)
                            Rectangle().fill(.black.opacity(ProductScroll.belowHeroCoverOpacity))
                        }
                        .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: ProductScroll.crossFadeSeconds), value: belowHero)
            }
    }

    @ViewBuilder
    private var picture: some View {
        switch result {
        case .file(let url), .remote(let url):
            // R471 (48): decoded at the screen's pixels (`FittedImage`): a 4K fan-art file is not held whole behind the page.
            FittedImage(url: url, session: services.online.imageSession) { image in
                image.resizable().aspectRatio(contentMode: .fill)
                    .overlay { cover }
            } placeholder: {
                EmptyView()
            }
        case .none:
            #if DEBUG
            // R452: only the readability picture (`-UITestBrightBackdrop`, debug UI-test mode): a plain white picture, no network.
            // design-lint:allow R452: a white test picture (debug UI-test mode only), the brightest artwork there can be
            if UITestMode.brightBackdrop { Color.white.overlay { cover } } else { EmptyView() }
            #else
            EmptyView() // R462: UITestMode exists only in Debug builds, so a Release build shows nothing here.
            #endif
        }
    }
}

/// R349: how the backdrop's picture is covered (see `BackdropView.style`).
enum BackdropStyle {
    case page
    /// R349, R350 (PROVISIONAL): the hero artwork is clear at the top; the material and the cover rise over its lower part.
    /// R471 (62): where they start is `ArtReadability.coverStart` (one ramp above the page's first line of text, R452 and
    /// R470), and `ArtReadability.fallbackStart` (0.35, R349's share) until the page has measured that line.
    case hero
}
