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
struct FittingText: View {
    let text: String
    var style: TVTextStyle = .body

    init(_ text: String, style: TVTextStyle = .body) {
        self.text = text
        self.style = style
    }

    var body: some View {
        Text(text)
            .font(style.font)
            .lineLimit(1)
            // design-lint:allow rule S1 (OPEN_QUESTIONS R165): the system text style shrinks to fit, never below Apple's 23 pt minimum (HIG Typography)
            .minimumScaleFactor(ShortLine.minimumScale(forPointSize: style.pointSize))
    }
}
