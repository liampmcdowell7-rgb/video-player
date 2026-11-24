import AppLogic
import SwiftUI

/// R452: the first line of a page's text reports where it begins, so the cover behind it starts there (`BackdropView.textTop`).
/// The page keeps the LARGEST value seen (the unscrolled position; scrolling down only makes it smaller), so scrolling does not drag the cover along.
struct ArtTextTopKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = value ?? nextValue() }
}

extension View {
    /// Marks the view whose top is the start of the page's text.
    func reportsArtTextTop() -> some View {
        background { GeometryReader { Color.clear.preference(key: ArtTextTopKey.self, value: $0.frame(in: .global).minY) } }
    }

    /// Keeps the largest top seen.
    func artTextTop(_ top: Binding<CGFloat?>) -> some View {
        onPreferenceChange(ArtTextTopKey.self) { (value: CGFloat?) in
            guard let value else { return }
            if top.wrappedValue == nil || value > (top.wrappedValue ?? 0) { top.wrappedValue = value }
        }
    }
}

/// R452: the small cover under a thin progress bar on a card's art (same black as the page cover, smaller:
/// `ArtReadability.progressScrim*`).
struct ProgressScrim: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.top)
            .frame(maxWidth: .infinity)
            .background {
                // design-lint:allow R452: our own cover under the bar, so a white picture cannot hide it (ArtReadabilityTests)
                LinearGradient(colors: [.black.opacity(0), .black.opacity(ArtReadability.progressScrimOpacity)], startPoint: .top, endPoint: .bottom)
            }
    }
}

extension View {
    func progressScrim() -> some View { modifier(ProgressScrim()) }
}
