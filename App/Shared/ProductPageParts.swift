import SwiftUI
import AppLogic

/// R350 (owner's device test of build 5, 21 Nov 2026, item D; PROVISIONAL): ONE metadata line of a movie or show page, as
/// the TV app's product page: the facts ("2021 · 1 h 52 min · ★ 7.4") then the format badges ("4K", "Dolby Vision",
/// "Dolby Atmos", "5.1"). Rule S1: the line is never wrapped or cut; when it does not fit, the badges are dropped from the
/// end (`ViewThatFits` tries the line with all badges, then one fewer, down to the facts alone, which shrink to fit).
/// Whether `ViewThatFits` uses its last child when none fits is not on Apple's page: UNVERIFIED (the facts alone are the
/// last child, and they shrink, so it should always fit).
struct ProductMetadataLine: View {
    let facts: String
    let badges: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: badges.count, through: 0, by: -1)), id: \.self) { (count: Int) in
                line(Array(badges.prefix(count)))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func line(_ shown: [String]) -> some View {
        HStack {
            if !facts.isEmpty {
                FittingText(facts, style: .callout)
                    .foregroundStyle(ReadableSecondary.style)
            }
            ForEach(shown, id: \.self) { (badge: String) in
                FormatBadge(text: badge)
            }
        }
    }
}

/// R350 (PROVISIONAL, alternative kept in OPEN_QUESTIONS: the real format logos): a format badge as Apple's apps draw them, a
/// rounded OUTLINED text badge spelling the format. Text only (the brandless rule, docs/NAMES.md: technology names as text,
/// no logos; the Dolby logos are licensed trademarks). The outline is the system secondary style, the corner and the side
/// inset scale with the text size. Never cut: the badge takes its natural width (`fixedSize`), and the line drops badges
/// instead (`ProductMetadataLine`).
struct FormatBadge: View {
    let text: String
    // R350: the side inset and the corner scale with the text size (ScaledMetric); no fixed size.
    @ScaledMetric(relativeTo: .caption) private var inset: CGFloat = 8
    @ScaledMetric(relativeTo: .caption) private var corner: CGFloat = 6

    var body: some View {
        Text(text)
            .font(.caption)
            .fixedSize()
            .padding(.horizontal, inset)
            .overlay {
                RoundedRectangle(cornerRadius: corner)
                    .stroke(ReadableSecondary.style)
            }
            .accessibilityLabel(text)
    }
}

/// R350 (PROVISIONAL, alternatives in OPEN_QUESTIONS): the hero area of a movie or show page fills this share of the first
/// screen, its content at the bottom, so the artwork shows above the title as on the TV app's product page and the top of
/// the next section shows below it. A share of the page's own height, not a point size; Apple publishes no number.
enum ProductPageLayout {
    static let heroFraction: CGFloat = 0.85
}

extension View {
    /// R350: the hero area of a product page: at least `ProductPageLayout.heroFraction` of the page's height, content at the
    /// bottom left. A MINIMUM height, so at Larger Text the hero grows instead of being cut (rule L7).
    func productHero(pageHeight: CGFloat) -> some View {
        frame(maxWidth: .infinity, minHeight: pageHeight * ProductPageLayout.heroFraction, alignment: .bottomLeading)
    }
}
