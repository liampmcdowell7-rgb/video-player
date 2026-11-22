/// R355 (compile run of 21 Nov 2026, item 6; PROVISIONAL, the owner's decision on S1 against R264 is open as R356; made
/// testable by R378): how `FittingText` (App/Shared/FittingLine.swift) fits a short text that is allowed to wrap at the
/// floor. Only the Files list row asks for it (`RowLabel` and `SlotLabel` pass `wrapsAtFloor`). The view offers the
/// steps of `wrapLadder` to the system `ViewThatFits` in this order; `step(for:naturalWidth:available:)` is the same
/// choice written out, so a Linux test can check it.
public enum TextFitStep: Equatable, Sendable {
    /// One line in this style, offered only at its natural width, so it is never cut (rule S1).
    case oneLine(TVTextStyle)
    /// This style wrapped onto as many lines as it needs.
    case wrapped(TVTextStyle)
}

public enum TextFitting {
    /// The 23 pt floor of the HIG Typography table is the size of Caption 2 (TVTextStyle.minimumPointSize).
    public static let floorStyle: TVTextStyle = .caption2

    /// The steps in order: the text in its own style, then one line at the floor, then the floor size wrapped.
    public static func wrapLadder(_ style: TVTextStyle) -> [TextFitStep] {
        [.oneLine(style), .oneLine(floorStyle), .wrapped(floorStyle)]
    }

    /// The first one-line step whose natural width fits the width offered, else the wrapped step (what `ViewThatFits`
    /// picks along the horizontal axis).
    public static func step(for style: TVTextStyle, naturalWidth: (TVTextStyle) -> Double, available: Double) -> TextFitStep {
        for step in wrapLadder(style) {
            switch step {
            case .oneLine(let lineStyle):
                if naturalWidth(lineStyle) <= available { return step }
            case .wrapped:
                return step
            }
        }
        return .wrapped(floorStyle)
    }

    /// For a text that may not wrap (R229): true when it does not fit its width even scaled to the readable floor, so the
    /// view shows it with the system marquee instead. False until both widths are measured.
    public static func isTooLong(natural: Double, available: Double, readable: Double) -> Bool {
        natural > 0 && available > 0 && available < natural * readable
    }
}
