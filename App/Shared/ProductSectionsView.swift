import SwiftUI
import AppLogic

/// R471 item 4 (PROVISIONAL; frames: episode t02s, movie t04s and t06s): the "How to Watch" card. One system card button
/// (`.card`, the system's focus lift): the source kind's symbol, the source's name, then the action and what is left.
/// Selecting it plays, as the Play button does.
struct HowToWatchCard: View {
    let card: HowToWatch
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            ShelfHeader(HowToWatch.heading)
            Button(action: action) {
                HStack {
                    Image(systemName: card.symbol)
                        .font(.title2)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading) {
                        FittingText(card.sourceName, style: .headline)
                        FittingText([card.action, card.detail].compactMap { $0 }.joined(separator: " · "), style: .callout)
                            .foregroundStyle(ReadableSecondary.style)
                    }
                }
                .padding()
            }
            .buttonStyle(.card)
            .accessibilityLabel([card.action, card.sourceName, card.spokenKind, card.detail].compactMap { $0 }.joined(separator: ", "))
            .accessibilityIdentifier("product.howToWatch")
        }
        // R424: a focus section the page's whole width, so Up and Down reach it from any column.
        .productPageRow()
    }
}

/// R471 item 6 (PROVISIONAL; frames: show t16s, movie t06s): "About": a card with the synopsis (four lines; selecting it
/// opens the whole text, rule L5) and, when we hold a rating, the age guidance card (the rating in its box, where it came
/// from, and the rating's own descriptors). Both are system card buttons (`.card`); the guidance card opens the same
/// facts in full. A card without data is left out; no section without either.
struct AboutSection: View {
    let title: String
    let summary: String?
    let artworkKey: String?
    let guidance: AgeGuidance?
    @State private var showsSummary = false
    @State private var showsGuidance = false

    var body: some View {
        VStack(alignment: .leading) {
            ShelfHeader("About")
            HStack(alignment: .top) {
                if let summary {
                    Button { showsSummary = true } label: {
                        VStack(alignment: .leading) {
                            FittingText(title, style: .headline)
                            Text(summary)
                                .font(.callout)
                                .lineLimit(4, reservesSpace: true)
                                .multilineTextAlignment(.leading)
                        }
                        .padding()
                        .frame(maxWidth: CGFloat(RowSpacing.textColumn), alignment: .leading)
                    }
                    .buttonStyle(.card)
                    .accessibilityHint("Shows the whole synopsis")
                    .accessibilityIdentifier("product.about")
                    .taskCover(isPresented: $showsSummary) {
                        SynopsisCover(title: title, text: summary, artworkKey: artworkKey, prefersEpisodeStill: false)
                    }
                }
                if let guidance {
                    Button { showsGuidance = true } label: {
                        VStack(alignment: .leading) {
                            FittingText(AgeGuidance.heading, style: .headline)
                            RatingBadge(rating: guidance.rating)
                            if let source = guidance.source {
                                FittingText(source, style: .caption)
                                    .foregroundStyle(ReadableSecondary.style)
                            }
                            if !guidance.descriptors.isEmpty {
                                Text(guidance.descriptors.joined(separator: ", "))
                                    .font(.caption)
                                    .lineLimit(2, reservesSpace: false)
                            }
                        }
                        .padding()
                    }
                    .buttonStyle(.card)
                    .accessibilityIdentifier("product.ageGuidance")
                    .taskCover(isPresented: $showsGuidance) {
                        InfoListCover(title: AgeGuidance.heading,
                                      values: ["Rated \(guidance.rating)"] + [guidance.source].compactMap { $0 } + guidance.descriptors)
                    }
                }
            }
        }
        .productPageRow()
    }
}

/// R471 item 4: the three columns under How to Watch: Information, Languages, Accessibility. Each column is a system
/// `VStack` of label (secondary) over value; columns of equal width (rule: elements side by side have equal size); a
/// column with no rows is left out. A shortened list ends with a "More" button that opens the whole list in a cover.
/// A column without such a button takes focus as one block, so the remote scrolls the page down to it.
struct ProductInfoColumns: View {
    let information: [InfoEntry]
    let languages: [InfoEntry]
    let accessibility: [InfoEntry]

    var body: some View {
        HStack(alignment: .top) {
            if !information.isEmpty { InfoColumn(heading: ProductInfo.informationHeading, entries: information) }
            if !languages.isEmpty { InfoColumn(heading: ProductInfo.languagesHeading, entries: languages) }
            if !accessibility.isEmpty { InfoColumn(heading: ProductInfo.accessibilityHeading, entries: accessibility) }
        }
        // The Information block is one accessibility container with its own name (R424, the UI tests' Down path).
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ProductInfo.informationHeading)
        .accessibilityIdentifier("product.information")
        .productPageRow()
    }
}

private struct InfoColumn: View {
    let heading: String
    let entries: [InfoEntry]
    @State private var shownList: InfoEntry?

    private var hasMore: Bool { entries.contains { $0.full != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(ProductPageSpacing.informationRows)) {
            Text(heading)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ForEach(entries) { entry in
                VStack(alignment: .leading) {
                    FittingText(entry.label, style: .caption)
                        .foregroundStyle(ReadableSecondary.style)
                    Text(entry.value)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    if entry.full != nil {
                        Button("More") { shownList = entry }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .accessibilityLabel("All \(entry.label)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .modifier(BlockFocus(enabled: !hasMore))
        .taskCover(item: $shownList) { entry in
            InfoListCover(title: entry.label, values: entry.full ?? [])
        }
    }
}

/// A column with no button of its own takes focus as one block (as Information did, R424); one with "More" leaves the
/// focus to that button.
private struct BlockFocus: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            // design-lint:allow the column has no controls, so it takes focus as one block for the remote to scroll to it
            content.focusable()
        } else {
            content
        }
    }
}

/// The whole list behind "More" (every audio or subtitle language), a system List in a full-screen cover (R228).
struct InfoListCover: View {
    let title: String
    let values: [String]

    var body: some View {
        List {
            Section {
                ForEach(values, id: \.self) { value in
                    Text(value)
                }
            } header: {
                Text(title)
            }
        }
        .scrollClipDisabled()
        .pushedScreen(title)
    }
}
