import SwiftUI
import AppLogic

/// A short one-line text that is never cut with "…" and never wrapped (rule S1, OPEN_QUESTIONS R165, PROVISIONAL).
/// It measures each candidate of the `ShortLine` (full text first, then one low-priority segment fewer each time) and shows
/// the first one that fits when scaled no smaller than `ShortLine.minimumScale(forPointSize:)`; the system then scales that
/// text to the width with `minimumScaleFactor`. VoiceOver always hears the full line.
struct FittingLine: View {
    let line: ShortLine
    var style: TVTextStyle = .caption2

    @State private var widths: [String: Double] = [:]
    @State private var available: Double = 0

    var body: some View {
        let candidates = line.candidates
        let scale = ShortLine.minimumScale(forPointSize: style.pointSize)
        let index = ShortLine.choose(idealWidths: candidates.map { widths[$0] ?? 0 }, available: available, minimumScale: scale)
        // An empty line still takes one line's height (a space), so cards with and without it are the same size.
        Text(candidates.isEmpty ? " " : candidates[min(index, candidates.count - 1)])
            .font(style.font)
            .lineLimit(1)
            // design-lint:allow rule S1 (OPEN_QUESTIONS R165): the system text style shrinks to fit, never below Apple's 23 pt minimum (HIG Typography)
            .minimumScaleFactor(scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: Double.self) { Double($0.size.width) } action: { available = $0 }
            .background(alignment: .leading) {
                // Natural one-line width of every candidate, measured off screen (hidden: not drawn, not spoken).
                ZStack(alignment: .leading) {
                    ForEach(candidates, id: \.self) { candidate in
                        Text(candidate)
                            .font(style.font)
                            .lineLimit(1) // design-lint:allow hidden measurement of the natural width, never drawn or spoken (rule S1 is applied to the visible line above)
                            .fixedSize()
                            .onGeometryChange(for: Double.self) { Double($0.size.width) } action: { widths[candidate] = $0 }
                    }
                }
                .hidden()
            }
            .accessibilityLabel(line.full)
            .accessibilityHidden(line.isEmpty)
    }
}

extension TVTextStyle {
    /// The system text style for this case (no fixed point sizes: the numbers in `pointSize` only bound the scaling).
    var font: Font {
        switch self {
        case .title1: return .title
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .callout: return .callout
        case .body: return .body
        case .caption: return .caption
        case .caption2: return .caption2
        }
    }
}

/// One short text (a name, a label, a value) on one line under rule S1: scaled down to the readable minimum, never cut,
/// never wrapped. For texts made of several segments use `FittingLine`.
///
/// #25 B4 (OPEN_QUESTIONS R199, PROVISIONAL): when the text does not fit even at the readable minimum (the run on 1fe5d50:
/// "Sample Movie 7 With A Much Longer Title Than A…" on Continue Watching, 50/51 and 80, and a Files row), the system cut
/// it with "…". Now it is scaled further, just enough to fit the line, so it is never cut and never wrapped; only such a
/// text goes below the readable minimum. The natural width is measured off screen, as `FittingLine` does.
struct FittingText: View {
    let text: String
    var style: TVTextStyle = .body
    @State private var natural: Double = 0
    @State private var available: Double = 0

    init(_ text: String, style: TVTextStyle = .body) {
        self.text = text
        self.style = style
    }

    var body: some View {
        let readable: Double = ShortLine.minimumScale(forPointSize: style.pointSize)
        let maxWidth: CGFloat? = Self.widthLimit(tooLong: Self.isTooLong(natural: natural, available: available, readable: readable))
        Text(text)
            .font(style.font)
            .lineLimit(1)
            // design-lint:allow rule S1 (OPEN_QUESTIONS R165, R199): the system text style shrinks to fit; below the readable minimum only when even that does not fit, so it is never cut
            .minimumScaleFactor(Self.scale(natural: natural, available: available, readable: readable))
            // #31 (OPEN_QUESTIONS R231): below the readable minimum the text takes the whole width it is offered, so the
            // width measured next is the space, not the text's own scaled width. Before, each measure of the shrunk text fed
            // a smaller scale (0.98 of the last width), the next layout shrank it again, and so on: a layout loop on the
            // main thread (test04 froze on the show page, run of 20 Nov) and an unreadable caption (77, "S2 E3").
            .frame(maxWidth: maxWidth, alignment: .leading)
            .onGeometryChange(for: Double.self) { Double($0.size.width) } action: { (width: Double) in
                // Only a real change is written, so equal widths never start another layout pass.
                if abs(width - available) >= 0.5 { available = width }
            }
            .background(alignment: .leading) {
                // The natural one-line width, measured off screen (hidden: not drawn, not spoken).
                Text(text)
                    .font(style.font)
                    .lineLimit(1) // design-lint:allow hidden measurement of the natural width, never drawn or spoken (rule S1 is applied to the visible text above)
                    .fixedSize()
                    .onGeometryChange(for: Double.self) { Double($0.size.width) } action: { natural = $0 }
                    .hidden()
            }
    }

    /// #31: no limit (the offered width) for a text below the readable minimum, otherwise the text's own width.
    static func widthLimit(tooLong: Bool) -> CGFloat? {
        guard tooLong else { return nil }
        return .infinity
    }

    /// True when the text does not fit its width even at the readable minimum (R199).
    static func isTooLong(natural: Double, available: Double, readable: Double) -> Bool {
        natural > 0 && available > 0 && available < natural * readable
    }

    /// The smallest scale the text may take: the readable minimum, or less when even that does not fit (R199).
    static func scale(natural: Double, available: Double, readable: Double) -> Double {
        guard isTooLong(natural: natural, available: available, readable: readable) else { return readable }
        // A little under the exact ratio, so rounding never leaves the last letter to an "…".
        return max(0.01, available / natural * 0.98)
    }
}
