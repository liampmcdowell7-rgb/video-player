import SwiftUI
import AppLogic

/// R471 item 2 (PROVISIONAL): the kind line of a product page's hero (`HeroLines.kindLine`): the source glyph, "Movie" or
/// "TV Show", the genres joined by " · ", the age rating in its outlined box. One line (rule S1): it shrinks to the caption
/// size, then drops genres from the end, never cut. Callout in the primary colour, as the frames' line reads (about 29 pt).
struct HeroKindLineView: View {
    let segments: [HeroLines.Segment]

    var body: some View {
        if !segments.isEmpty {
            ViewThatFits(in: .horizontal) {
                row(.callout, dropping: 0)
                row(.caption, dropping: 0)
                ForEach(1..<max(textCount, 1), id: \.self) { n in row(.caption, dropping: n) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityIdentifier("product.kindLine")
        }
    }

    private var textCount: Int { segments.filter { if case .text = $0 { return true } else { return false } }.count }

    /// The line with the last `dropping` text parts (genres first, never the kind word) left out.
    private func row(_ font: Font, dropping: Int) -> some View {
        let shown: [HeroLines.Segment] = Self.drop(segments, texts: dropping)
        return HStack(spacing: CGFloat(BadgeSpacing.afterText)) {
            ForEach(Array(shown.enumerated()), id: \.offset) { (index: Int, segment: HeroLines.Segment) in
                switch segment {
                case .glyph(let symbol, _):
                    Image(systemName: symbol)
                        .font(font)
                        .accessibilityHidden(true)
                case .text(let text):
                    // " · " between two texts, as the frames' line.
                    let previousIsText: Bool = index > 0 && { if case .text = shown[index - 1] { return true } else { return false } }()
                    Text(previousIsText ? "· " + text : text)
                        .font(font)
                        .fixedSize()
                case .ratingBox(let rating):
                    RatingBadge(rating: rating)
                }
            }
        }
    }

    static func drop(_ segments: [HeroLines.Segment], texts n: Int) -> [HeroLines.Segment] {
        guard n > 0 else { return segments }
        var out = segments
        var left = n
        for i in out.indices.reversed() where left > 0 {
            if case .text = out[i], i > 1 { out.remove(at: i); left -= 1 }
        }
        return out
    }

    private var spoken: String {
        segments.map { segment -> String in
            switch segment {
            case .glyph(_, let spoken): return spoken
            case .text(let t): return t
            case .ratingBox(let r): return "Rated " + r
            }
        }.joined(separator: ", ")
    }
}

/// R471 item 2: the facts line: "Aug 26, 2026 · 43m", then the glyph badges. One line: badges are dropped from the end
/// before anything would be cut (rule S1).
struct HeroFactsLineView: View {
    let texts: [String]
    let badges: [HeroBadge]

    var body: some View {
        if !texts.isEmpty || !badges.isEmpty {
            ViewThatFits(in: .horizontal) {
                ForEach(Array(stride(from: badges.count, through: 0, by: -1)), id: \.self) { (count: Int) in
                    line(Array(badges.prefix(count)))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((texts + badges.map(\.spoken)).joined(separator: ", "))
            .accessibilityIdentifier("product.factsLine")
        }
    }

    private func line(_ shown: [HeroBadge]) -> some View {
        HStack(spacing: CGFloat(BadgeSpacing.afterText)) {
            if !texts.isEmpty {
                Text(texts.joined(separator: " · "))
                    .font(.callout)
                    .fixedSize()
            }
            HStack(spacing: CGFloat(BadgeSpacing.inGroup)) {
                ForEach(shown, id: \.self) { HeroGlyphBadge(badge: $0) }
            }
        }
    }
}

/// R471 item 2 (e): one small outlined glyph badge. A two-word name is two lines of the smallest system text style, so the
/// badge is about one caption line tall, like the frames' glyphs; the names are text, never a logo.
struct HeroGlyphBadge: View {
    let badge: HeroBadge
    @ScaledMetric(relativeTo: .caption2) private var inset: CGFloat = 6
    @ScaledMetric(relativeTo: .caption2) private var corner: CGFloat = 5

    var body: some View {
        Group {
            if badge.lines.count > 1 {
                // design-lint:allow R471: the two lines of a two-word badge sit tight, one glyph (the frames' Dolby Vision, Dolby Atmos glyphs)
                VStack(spacing: 0) {
                    ForEach(badge.lines, id: \.self) { line in
                        Text(line.uppercased())
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                }
            } else {
                Text(badge.lines.first ?? "")
                    .font(.caption.weight(.semibold))
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, inset)
        .overlay {
            RoundedRectangle(cornerRadius: corner)
                .stroke(ReadableSecondary.style)
        }
        .accessibilityLabel(badge.spoken)
    }
}

/// R471 item 2 (Part 2, episode page): the description with its prefix ("S4, E4:") in the semibold weight, three lines,
/// the whole text one press away (rule L5, `SynopsisLink`).
struct HeroDescription: View {
    let prefix: String?
    let text: String
    let title: String
    let artworkKey: String?
    var prefersEpisodeStill = false

    var body: some View {
        SynopsisLink(title: title, text: text, artworkKey: artworkKey, prefersEpisodeStill: prefersEpisodeStill, prefix: prefix)
    }
}
