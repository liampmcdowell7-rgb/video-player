import SwiftUI
import AppLogic

/// R453 (owner's recording IMG_1427.mov of 23 Nov 2026, rule R312; PROVISIONAL): the typed metadata line. Plain text for
/// runtime, date, resolution and audio, and the content rating as the line's ONLY box (`RatingBadge`). One line: it shrinks
/// (callout, then caption), then drops the last parts (audio, resolution) before it would be cut; each part keeps its natural
/// width (`fixedSize`), so a date never breaks across lines.
struct InfoLineView: View {
    let line: InfoLine

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(.callout, dropping: 0)
            row(.caption, dropping: 0)
            row(.caption, dropping: 1)
            row(.caption, dropping: 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.plain)
        .accessibilityIdentifier("product.metadataLine")
    }

    private func row(_ font: Font, dropping: Int) -> some View {
        HStack(spacing: CGFloat(BadgeSpacing.afterText)) {
            ForEach(Array(line.segments.dropLast(dropping).enumerated()), id: \.offset) { (_: Int, segment: InfoLine.Segment) in
                switch segment {
                case .text(let text):
                    Text(text)
                        .font(font)
                        .foregroundStyle(ReadableSecondary.style)
                        .fixedSize()
                case .ratingBox(let rating):
                    RatingBadge(rating: rating)
                }
            }
        }
    }
}

/// R453: the block of a show page's first screen (and the facts of a movie or episode page): an optional title line
/// ("S1 - E3 - Title"), the typed metadata line, the genres on their own line, the ratings row (a system symbol and a number per
/// source) and the synopsis in three reserved lines. A part with no data draws nothing but, when `fixedHeight`, keeps its
/// line's height, so the block never changes size when the focus moves from one episode to another. A change is a cross-fade of
/// the text only (none under Reduce Motion) and is announced to VoiceOver.
struct InfoBlockView: View {
    let block: InfoBlock
    /// With a value, the show's own synopsis is the page's whole-text button (rule L5); an episode's is plain text.
    var fullText: (title: String, artworkKey: String?, prefersEpisodeStill: Bool)? = nil
    /// The show page reserves every line (the block must not change size); the movie and episode pages draw what they have.
    var fixedHeight: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .id(block)
                .transition(.opacity)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: InfoBlockLayout.crossFadeSeconds), value: block)
        .frame(maxWidth: CGFloat(RowSpacing.textColumn), alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("product.infoBlock")
        .onChange(of: block) { _, new in
            if !new.spoken.isEmpty { AccessibilityNotification.Announcement(new.spoken).post() }
        }
    }

    private var content: some View {
        VStack(alignment: .leading) {
            if let titleLine = block.titleLine {
                FittingText(titleLine, style: .headline)
                    .accessibilityIdentifier("product.infoBlock.title")
            } else if fixedHeight {
                reserved(.headline)
            }
            if !block.line.isEmpty {
                InfoLineView(line: block.line)
            } else if fixedHeight {
                reserved(.callout)
            }
            if let genres = block.genreLine {
                FittingText(genres, style: .callout)
                    .foregroundStyle(ReadableSecondary.style)
                    .accessibilityIdentifier("product.infoBlock.genres")
            } else if fixedHeight {
                reserved(.callout)
            }
            if !block.ratings.isEmpty {
                HStack(spacing: CGFloat(BadgeSpacing.afterText)) {
                    ForEach(block.ratings) { rating in
                        Label(rating.value, systemImage: rating.symbol)
                            .font(.callout)
                            .foregroundStyle(ReadableSecondary.style)
                            .fixedSize()
                    }
                }
                .accessibilityIdentifier("product.infoBlock.ratings")
            } else if fixedHeight {
                reserved(.callout)
            }
            synopsis
        }
    }

    @ViewBuilder
    private var synopsis: some View {
        if let text = block.synopsis {
            if block.titleLine == nil, let fullText {
                SynopsisLink(title: fullText.title, text: text, artworkKey: fullText.artworkKey,
                             prefersEpisodeStill: fullText.prefersEpisodeStill, reservesSpace: fixedHeight)
            } else {
                Text(text)
                    .font(.callout)
                    .lineLimit(InfoBlockLayout.synopsisLines, reservesSpace: fixedHeight)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("product.infoBlock.synopsis")
            }
        } else if fixedHeight {
            Text(" ")
                .font(.callout)
                .lineLimit(InfoBlockLayout.synopsisLines, reservesSpace: true)
                .accessibilityHidden(true)
        }
    }

    /// An empty line that keeps the height of a text line of this style, hidden from VoiceOver.
    private func reserved(_ style: Font) -> some View {
        Text(" ")
            .font(style)
            .accessibilityHidden(true)
    }
}
