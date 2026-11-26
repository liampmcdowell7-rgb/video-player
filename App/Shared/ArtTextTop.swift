import AppLogic
import SwiftUI

/// R452: the first line of a page's text reports where it begins, so the cover behind it starts there (`BackdropView.textTop`).
///
/// R470 (owner's photo of build 202611250008: the series line and the title over the bright picture, the cover starting
/// under the title):
/// - The report comes from the WHOLE text column (`reportsArtTextTop` on the stack that holds the series line, the title,
///   the lines under it and the buttons), not from the title alone: on an episode page the series line sits above the title.
/// - It is measured in the scroll CONTENT's own coordinate space (`artTextContent`), which does not move when the page
///   scrolls, and the scroll view's own top is added. R452 kept the LARGEST global value seen instead, to ignore scrolling;
///   but the column is bottom-aligned and grows UPWARD when the description, the genres or the title logo arrive, so the
///   largest value was the column's top BEFORE they arrived, and the cover stayed under the title. Now the latest value
///   counts, so the cover follows the column as it grows and never moves when the page scrolls.
enum ArtTextSpace {
    static let content = "artTextContent"
}

struct ArtTextTopKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    /// The topmost of the reports (a page has one column; the smallest y is its first line).
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        guard let next = nextValue() else { return }
        value = min(value ?? next, next)
    }
}

extension View {
    /// Marks the text column whose top is the start of the page's text (its first line, whatever it is).
    func reportsArtTextTop() -> some View {
        background {
            GeometryReader { Color.clear.preference(key: ArtTextTopKey.self, value: $0.frame(in: .named(ArtTextSpace.content)).minY) }
        }
    }

    /// On the scroll view's content stack: the coordinate space the column reports in (it scrolls with the content, so the
    /// column's place in it never changes when the page scrolls).
    func artTextContent() -> some View {
        coordinateSpace(.named(ArtTextSpace.content))
    }

    /// On the scroll view: the column's top in global coordinates at rest (the scroll view's top, its top content inset and
    /// the column's place in the content), kept current. UNVERIFIED on a device: that the content stack's origin sits at
    /// the top content inset at rest (ScrollGeometry's page names `contentInsets` but does not describe this).
    func artTextTop(_ top: Binding<CGFloat?>) -> some View { modifier(ArtTextTopReader(top: top)) }
}

private struct ArtTextTopReader: ViewModifier {
    @Binding var top: CGFloat?
    @State private var pageTop: CGFloat = 0
    /// The scroll view's top content inset (the safe area it keeps above the content): at rest the content starts there.
    @State private var insetTop: CGFloat = 0
    @State private var contentTop: CGFloat?

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { (y: CGFloat) in
                pageTop = y
                publish()
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentInsets.top } action: { (_: CGFloat, inset: CGFloat) in
                insetTop = inset
                publish()
            }
            .onPreferenceChange(ArtTextTopKey.self) { (value: CGFloat?) in
                contentTop = value
                publish()
            }
    }

    private func publish() {
        guard let contentTop else { return }
        let value: CGFloat = pageTop + insetTop + contentTop
        if top.map({ abs($0 - value) >= 0.5 }) ?? true { top = value }
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
