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

/// One short text (a name, a label, a value) on one line under rule S1: scaled down to the readable floor, never cut with
/// "…", never wrapped. For texts made of several segments use `FittingLine`.
///
/// #30 Part 2 (OPEN_QUESTIONS R229, PROVISIONAL; replaces the "scale further" of R199): ONE readable floor for every
/// resize-to-fit text, `ShortLine.minimumScale(forPointSize:)` = 23 pt over the style's size (23 pt is the tvOS minimum in
/// the HIG Typography table). A text that does not fit even at the floor is shown whole by the system marquee
/// (`MarqueeText`, a `UILabel` that scrolls while a containing view has focus), at the floor size, never smaller. Before,
/// R199 scaled it as far as needed (down to 1 %), which made the "S2 E3" caption unreadable (77) and, with the width fed
/// back into the scale, looped on the main thread (#31, R231).
struct FittingText: View {
    let text: String
    var style: TVTextStyle = .body
    /// R355 (compile run of 21 Nov 2026, item 6; PROVISIONAL, the owner's decision on S1 against R264 is open): a text that
    /// does not fit at the floor WRAPS at the floor size instead of being cut. Replaces the fade at rest with the marquee on
    /// focus of R229 (c): picture 72 showed the long folder name cut at rest ("… Card Is W"). Only the Files list row asks.
    var wrapsAtFloor: Bool = false
    @State private var natural: Double = 0
    @State private var available: Double = 0

    init(_ text: String, style: TVTextStyle = .body, wrapsAtFloor: Bool = false) {
        self.text = text
        self.style = style
        self.wrapsAtFloor = wrapsAtFloor
    }

    var body: some View {
        if wrapsAtFloor {
            wrapping
        } else {
            fitting
        }
    }

    /// R355: the line in its style when it fits, else one line at the 23 pt floor (Caption 2), else the floor size wrapped
    /// onto as many lines as it needs. The system `ViewThatFits` chooses in one layout pass, with no measured state (as
    /// `CardCaption`, R354), so the row takes the wrapped height in the same pass.
    /// R378: the three steps and their order are AppLogic `TextFitting.wrapLadder` (Linux tests of the choice).
    private var wrapping: some View {
        let ladder: [TextFitStep] = TextFitting.wrapLadder(style)
        return ViewThatFits(in: .horizontal) {
            fitStep(ladder[0])
            fitStep(ladder[1])
            fitStep(ladder[2])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One step of the ladder: one line offered to `ViewThatFits` only at its natural width, so it is never cut (rule S1),
    /// or the style wrapped onto as many lines as it needs.
    @ViewBuilder
    private func fitStep(_ step: TextFitStep) -> some View {
        switch step {
        case .oneLine(let lineStyle):
            Text(text)
                .font(lineStyle.font)
                .lineLimit(1) // design-lint:allow R355: offered to ViewThatFits only at its natural width, so it is never cut (rule S1)
        case .wrapped(let wrapStyle):
            Text(text)
                .font(wrapStyle.font)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var fitting: some View {
        let readable: Double = ShortLine.minimumScale(forPointSize: style.pointSize)
        let tooLong: Bool = Self.isTooLong(natural: natural, available: available, readable: readable)
        line(tooLong: tooLong, readable: readable)
            // #31 (R231): a text below the floor takes the whole width it is offered, so the width measured next is the
            // space, not the text's own width, and no measure feeds back into the next layout.
            .frame(maxWidth: Self.widthLimit(tooLong: tooLong), alignment: .leading)
            .onGeometryChange(for: Double.self) { Double($0.size.width) } action: { (width: Double) in
                // Only a real change is written, so equal widths never start another layout pass.
                if abs(width - available) >= 0.5 { available = width }
            }
            .background(alignment: .leading) {
                // The natural one-line width, measured off screen (hidden: not drawn, not spoken).
                Text(text)
                    .font(style.font)
                    .lineLimit(1) // design-lint:allow hidden measurement of the natural width, never drawn or spoken (rule S1 is applied to the visible text)
                    .fixedSize()
                    .onGeometryChange(for: Double.self) { Double($0.size.width) } action: { natural = $0 }
                    .hidden()
            }
    }

    /// The visible line: the system text scaled no lower than the floor, or the marquee at the floor when even that is too
    /// long (R229).
    @ViewBuilder
    private func line(tooLong: Bool, readable: Double) -> some View {
        if tooLong {
            MarqueeText(text: text)
                .accessibilityIdentifier(ControlID.textMarquee) // R443: tests count the titles shown by the marquee (cut at rest)
        } else {
            Text(text)
                .font(style.font)
                .lineLimit(1)
                // design-lint:allow rule S1 (OPEN_QUESTIONS R165, R229): the system text style shrinks to fit, never below the readable floor
                .minimumScaleFactor(readable)
        }
    }

    /// #31: no limit (the offered width) for a text below the floor, otherwise the text's own width.
    static func widthLimit(tooLong: Bool) -> CGFloat? {
        guard tooLong else { return nil }
        return .infinity
    }

    /// True when the text does not fit its width even at the readable floor (R229). R378: AppLogic `TextFitting.isTooLong`.
    static func isTooLong(natural: Double, available: Double, readable: Double) -> Bool {
        TextFitting.isTooLong(natural: natural, available: available, readable: readable)
    }
}

