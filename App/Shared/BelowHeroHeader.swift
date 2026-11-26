import SwiftUI
import AppLogic

/// R471 item 1 (owner's frames of the Apple TV app: episode t02s, show t06s and t12s, movie t02s; PROVISIONAL): the title
/// at the top of the part below a product page's hero, centred: the clear logo when there is one (`TitleHeader`), else the
/// title text. It scrolls with the content (episode t04s shows it moving up). Not focusable.
/// R471 (120), PROVISIONAL: the second instance of the page's title (never scaled while it moves). Its logo is
/// `HeroMotion.headerLogoWidthRatio` times the hero logo's fitted size; below the hero it fades in from lower down and
/// lands (`HeroMotion`), and only then carries the accessibility label (the hero's title is hidden from accessibility).
struct BelowHeroHeader: View {
    let title: String
    /// `item-N` or `series-N` for a logo; nil for the text title (an episode page).
    let artworkKey: String?
    /// R471 (120): the page's motion state, the title kind its timings follow, and whether the page is below its hero (the
    /// animations' trigger).
    let motion: HeroMotion.Frame
    let kind: HeroMotion.Title
    let belowHero: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TitleHeader(title: title, artworkKey: artworkKey, logoScale: HeroMotion.headerLogoWidthRatio)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom)
            .accessibilityIdentifier("product.belowHeroTitle")
            // R471 (120): exactly one title instance is read out: this one only below the hero.
            .accessibilityHidden(motion.heroTitleIsAccessible)
            // R471 (120): the fade and the landing have their own timings (on Up the fade ends before the drop does).
            // Reduce Motion keeps the fade; its offsets are 0 then (`HeroMotion.frame`).
            .opacity(motion.headerOpacity)
            .animation(HeroMotion.timing(.headerFade, title: kind, belowHero: belowHero).animation, value: belowHero)
            .offset(y: CGFloat(motion.headerOffset)) // design-lint:allow R471 (120): the header's landing offset from HeroMotion (owner's measured table), not a layout value
            .animation(HeroMotion.timing(.headerOffset, title: kind, belowHero: belowHero).animation, value: belowHero)
    }
}

extension HeroMotion.Timing {
    /// R471 (120): this timing as a SwiftUI animation (the curve's control points, the length, then the delay).
    var animation: Animation {
        Animation.timingCurve(curve.c1x, curve.c1y, curve.c2x, curve.c2y, duration: duration).delay(delay)
    }
}

extension View {
    /// R471 item 1: reports whether the page's scroll view is scrolled below its hero (`ProductScroll.isBelowHero`).
    /// `heroHeight` is the hero's share of the page (the page passes `pageHeight * fraction`).
    func reportsBelowHero(_ belowHero: Binding<Bool>, heroHeight: CGFloat) -> some View {
        onScrollGeometryChange(for: Bool.self) { geometry in
            ProductScroll.isBelowHero(offset: Double(geometry.contentOffset.y + geometry.contentInsets.top), heroHeight: Double(heroHeight))
        } action: { _, now in
            if belowHero.wrappedValue != now { belowHero.wrappedValue = now }
        }
    }

    /// R471 (120): the hero text group's part of the motion: below the hero it fades out fast and waits above its place;
    /// on the way back it comes down from there as it fades in.
    func heroGroupMotion(_ motion: HeroMotion.Frame, kind: HeroMotion.Title, belowHero: Bool) -> some View {
        opacity(motion.heroOpacity)
            .offset(y: CGFloat(motion.heroOffset)) // design-lint:allow R471 (120): the hero group's offset from HeroMotion (owner's table), not a layout value
            .animation(HeroMotion.timing(.heroGroup, title: kind, belowHero: belowHero).animation, value: belowHero)
    }

    /// R471 (120): the part below the hero (the header and every row after it) rises into place below the hero.
    func belowHeroSectionMotion(_ motion: HeroMotion.Frame, kind: HeroMotion.Title, belowHero: Bool) -> some View {
        offset(y: CGFloat(motion.sectionOffset)) // design-lint:allow R471 (120): the rows' rise from HeroMotion, not a layout value
            .animation(HeroMotion.timing(.section, title: kind, belowHero: belowHero).animation, value: belowHero)
    }

    /// R471 (120), D (motion-4): below the hero, content passing under the page's top edge fades out over
    /// `HeroMotion.topFadeHeight`; at the hero nothing fades. Opacity only (the reference also blurs it). The mask reaches
    /// far past the sides and the bottom, so it never cuts a focused card that grows past the scroll view (R345); only the
    /// top edge is masked. The header is not pinned: it scrolls under this edge with the content.
    func belowHeroTopFade(_ motion: HeroMotion.Frame, kind: HeroMotion.Title, belowHero: Bool) -> some View {
        // design-lint:allow R471 (120): a mask at the top edge only (it reaches past the sides and the bottom), so the focus effect is never cut
        mask {
            ZStack(alignment: .top) {
                // design-lint:allow R471 (120): mask alpha, not a colour: the whole page shown while at the hero
                Color.black.opacity(motion.topFadeOff)
                VStack(spacing: 0) { // design-lint:allow R471 (120): the fade band and the plain mask below it must touch (a mask, no layout of content)
                    // design-lint:allow R471 (120): mask alpha, not a colour: the fade band under the top edge
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: CGFloat(HeroMotion.topFadeHeight)) // design-lint:allow R471 (120): the fade band's height from HeroMotion, a mask, not a card
                    // design-lint:allow R471 (120): mask alpha, not a colour
                    Color.black
                }
            }
            .padding(EdgeInsets(top: 0, leading: -400, bottom: -400, trailing: -400)) // design-lint:allow R471 (120): the mask reaches 400 pt past the sides and the bottom so a grown focused card is never cut
            .animation(HeroMotion.timing(.section, title: kind, belowHero: belowHero).animation, value: belowHero)
        }
    }
}
