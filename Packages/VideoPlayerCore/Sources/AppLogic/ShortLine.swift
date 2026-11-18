import Foundation

/// A short one-line text made of segments joined by " · " ("S2 E1 · Pilot · 41 min left", "4K · Dolby Vision · Dolby Atmos").
///
/// Rule S1 (OPEN_QUESTIONS R165, PROVISIONAL): a short text is never cut with "…" and never wrapped. It is shown on one line,
/// scaled down to `minimumScale` at most; when even that does not fit, the lowest-priority segment is left out (whole
/// segments only, never half a word), and so on. The app's `FittingLine` view measures the candidates and calls `choose`.
public struct ShortLine: Equatable, Sendable {
    public struct Segment: Equatable, Sendable {
        public var text: String
        /// Higher is kept longer. Equal priorities: the later segment goes first.
        public var priority: Int
        public init(_ text: String, priority: Int) { self.text = text; self.priority = priority }
    }

    /// The smallest scale a short text may be drawn at: still readable from the sofa (rule S1).
    public static let minimumScale = 0.7
    public static let separator = " · "

    /// In display order. Empty segments are dropped.
    public let segments: [Segment]

    public init(_ segments: [Segment]) {
        self.segments = segments.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Segments in display order, all with the same priority, dropped from the end.
    public init(ordered texts: [String]) {
        self.init(texts.enumerated().map { Segment($0.element, priority: texts.count - $0.offset) })
    }

    public var isEmpty: Bool { segments.isEmpty }
    public var full: String { segments.map(\.text).joined(separator: Self.separator) }

    /// The full line first, then one segment fewer each time (lowest priority first), down to the single most important
    /// segment. Never contains an empty string; empty when there are no segments.
    public var candidates: [String] {
        var kept = segments.indices.map { $0 }
        var out: [String] = []
        while !kept.isEmpty {
            out.append(kept.map { segments[$0].text }.joined(separator: Self.separator))
            // The lowest priority; among equals the one shown last.
            let drop = kept.enumerated().min { a, b in
                let pa = segments[a.element].priority, pb = segments[b.element].priority
                return pa != pb ? pa < pb : a.offset > b.offset
            }!.offset
            kept.remove(at: drop)
        }
        return out
    }

    /// The smallest scale for text of this point size: never below `minimumScale` (rule S1) and never below Apple's tvOS
    /// minimum text size (`TVTextStyle.minimumPointSize`). Where the two disagree Apple's minimum wins (OPEN_QUESTIONS R165):
    /// Caption 2 is already the minimum, so it is never scaled and loses segments instead.
    public static func minimumScale(forPointSize size: Double) -> Double {
        guard size > 0 else { return 1 }
        return min(1, max(minimumScale, TVTextStyle.minimumPointSize / size))
    }

    /// Which candidate to show, given each candidate's natural one-line width and the width available: the first that fits
    /// at `minimumScale` or larger. When none does, the last (shortest) one; it is then drawn at `minimumScale`.
    public static func choose(idealWidths: [Double], available: Double, minimumScale: Double = ShortLine.minimumScale) -> Int {
        guard !idealWidths.isEmpty else { return 0 }
        guard available > 0 else { return 0 }
        return idealWidths.firstIndex { $0 * minimumScale <= available + 0.5 } ?? idealWidths.count - 1
    }
}

/// The tvOS text styles the app uses, with the point sizes Apple's Typography page lists for tvOS
/// (https://developer.apple.com/design/human-interface-guidelines/typography, read 2026-11-18): default 29 pt (Body),
/// minimum 23 pt (Caption 2). The app maps each case to the matching SwiftUI `Font` text style; these numbers are only used
/// to work out how far a short line may be scaled (rule S1), never to set a font size.
public enum TVTextStyle: String, CaseIterable, Sendable {
    case title1, title2, title3, headline, callout, body, caption, caption2

    public var pointSize: Double {
        switch self {
        case .title1: return 76
        case .title2: return 57
        case .title3: return 48
        case .headline: return 38
        case .callout: return 31
        case .body: return 29
        case .caption: return 25
        case .caption2: return 23
        }
    }

    /// Apple's minimum text size on tvOS (Typography and Accessibility pages).
    public static let minimumPointSize = 23.0
}
