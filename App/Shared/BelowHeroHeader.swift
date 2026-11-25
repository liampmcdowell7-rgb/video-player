import SwiftUI
import AppLogic

/// R471 item 1 (owner's frames of the Apple TV app: episode t02s, show t06s and t12s, movie t02s; PROVISIONAL): the title
/// at the top of the part below a product page's hero, centred: the clear logo when there is one (`TitleHeader`), else the
/// title text. It scrolls with the content (episode t04s shows it moving up). Not focusable.
struct BelowHeroHeader: View {
    let title: String
    /// `item-N` or `series-N` for a logo; nil for the text title (an episode page).
    let artworkKey: String?

    var body: some View {
        TitleHeader(title: title, artworkKey: artworkKey)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom)
            .accessibilityIdentifier("product.belowHeroTitle")
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
}
