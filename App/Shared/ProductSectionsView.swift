import SwiftUI
import AppLogic

/// R471 item 7 (PROVISIONAL): a shelf of the title's own extra videos (Trailers, or Bonus Content), 16:9 system card
/// buttons with the file's name. R471 (24): selecting one plays it (`ExtraPlayerScreen`, from its start, nothing saved); its
/// facts (name, kind, size) are in its long-press menu. The same files stay listed in the details button's Extras menu.
struct ExtrasShelf: View {
    let heading: String
    let extras: [ExtraRow]
    /// The title whose extras these are (`ExtraFiles.find` looks each one up again before it plays).
    let itemID: Int64
    /// R471 (39): a show's own extras (the show page); `itemID` is then 0.
    var seriesID: Int64? = nil
    @State private var shown: ExtraRow?
    @State private var playing: ExtraPlayRequest?

    var body: some View {
        VStack(alignment: .leading) {
            // R471 (113): room for the lifted card under the header and under the cards, as every other shelf of lifting
            // cards (R402: Home, Discover, Related); frame show t16s spaces Bonus Content and Related alike.
            ShelfHeader(heading)
                .padding(.bottom, CGFloat(RowSpacing.shelfFocusRoom))
            ScrollView(.horizontal) {
                // design-lint:allow HIG Layout, 40 pt horizontal spacing between cards (docs/DESIGN_SYSTEM.md section 4)
                LazyHStack(alignment: .top, spacing: 40) {
                    ForEach(extras) { extra in
                        Button { playing = ExtraPlayRequest(itemID: itemID, extraID: extra.id, seriesID: seriesID) } label: {
                            VStack(alignment: .leading) {
                                Image(systemName: "film")
                                    .font(.title2)
                                    .accessibilityHidden(true)
                                FittingText(ExtraShelves.displayName(extra.name), style: .callout)
                                if let size = extra.sizeText {
                                    FittingText(size, style: .caption)
                                        .foregroundStyle(ReadableSecondary.style)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.card)
                        // design-lint:allow HIG Layout, four columns of the grid width for 16:9 cards, as the episode cards (R189)
                        .containerRelativeFrame(.horizontal, count: 4, spacing: 40)
                        .accessibilityIdentifier("product.extra.\(extra.id)")
                        .contextMenu {
                            Button("Play", systemImage: "play.fill") { playing = ExtraPlayRequest(itemID: itemID, extraID: extra.id, seriesID: seriesID) }
                            Button("File Details", systemImage: "info.circle") { shown = extra }
                        }
                    }
                }
            }
            .scrollClipDisabled()
            .padding(.bottom, CGFloat(RowSpacing.shelfFocusRoom))
        }
        .productPageRow()
        .taskCover(item: $shown) { extra in
            InfoListCover(title: ExtraShelves.displayName(extra.name),
                          values: [extra.name, extra.kindText, extra.sizeText].compactMap { $0 })
        }
        // R471 (24): the system player over the page, as a title plays (`RootView`).
        .fullScreenCover(item: $playing) { request in
            ExtraPlayerScreen(request: request)
        }
    }
}

/// R471 item 7 (PROVISIONAL): "Related": the library's own titles that share a genre (`RelatedTitles`), portrait posters
/// as on every shelf (`PosterCard`, six columns), each opening its page.
struct RelatedShelf: View {
    let cards: [ItemCard]
    /// R471 (40): the genre each movie shares with the page (`RelatedCaption.sharedGenres`), for its focus caption.
    var genres: [Int64: String] = [:]

    var body: some View {
        VStack(alignment: .leading) {
            ShelfHeader(RelatedTitles.heading)
                .padding(.bottom, CGFloat(RowSpacing.shelfFocusRoom))
            ScrollView(.horizontal) {
                // design-lint:allow HIG Layout, 40 pt horizontal spacing between posters (docs/DESIGN_SYSTEM.md section 4)
                LazyHStack(alignment: .top, spacing: 40) {
                    ForEach(cards) { card in
                        PosterCard(card: card, focusCaption: RelatedCaption.text(kind: .movie, genre: genres[card.id]))
                            // design-lint:allow HIG Layout, six columns of the grid so shelf posters line up with grid posters
                            .containerRelativeFrame(.horizontal, count: 6, spacing: 40)
                    }
                }
                .equalCaptionRow()
            }
            .scrollClipDisabled()
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, CGFloat(RowSpacing.shelfFocusRoom))
        }
        .productPageRow()
    }
}

/// R471 item 6 (PROVISIONAL; frames: show t16s, movie t06s): "About": a card with the synopsis (five lines since R471 (35); selecting it
/// opens the whole text, rule L5) and, when we hold a rating, the age guidance card (the rating in its box, where it came
/// from, and the rating's own descriptors). Both are system card buttons (`.card`); the guidance card opens the same
/// facts in full. A card without data is left out; no section without either.
struct AboutSection: View {
    let title: String
    let summary: String?
    let artworkKey: String?
    let guidance: AgeGuidance?
    /// R471 (30), PROVISIONAL (frames show t18s, t20s, movie t06s): the title's genres, one line under its name.
    var genres: [String] = []
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
                            let genreLine = AboutGenres.line(genres)
                            if let genreLine {
                                // Secondary, as the label of a fact (rule S1: one line, scaled, never cut).
                                FittingText(genreLine, style: .caption)
                                    .foregroundStyle(ReadableSecondary.style)
                            }
                            Text(summary)
                                .font(.callout)
                                // R471 (35), PROVISIONAL (frames show t18s, t20s, movie t06s): five lines, as the reference card.
                                .lineLimit(5, reservesSpace: true)
                                .multilineTextAlignment(.leading)
                        }
                        .padding()
                        .frame(maxWidth: CGFloat(RowSpacing.textColumn), maxHeight: .infinity, alignment: .topLeading)
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
                            // R471 (32), PROVISIONAL (frames show t18s, t20s): the rating itself leads the card as a large
                            // bold figure ("14+"), with no heading over it; the heading stays the card's spoken name.
                            FittingText(guidance.rating, style: .title1)
                                .fontWeight(.bold)
                            // R471 (42), PROVISIONAL (frame show t20s): the source is a primary semibold line, and the
                            // descriptors run to four lines at the synopsis's size; the whole list is one press away.
                            if let source = guidance.source {
                                FittingText(source, style: .callout)
                                    .fontWeight(.semibold)
                            }
                            if !guidance.descriptors.isEmpty {
                                Text(guidance.descriptors.joined(separator: ", "))
                                    .font(.callout)
                                    .lineLimit(4, reservesSpace: false)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .padding()
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                    }
                    .buttonStyle(.card)
                    .accessibilityLabel("\(AgeGuidance.heading), rated \(guidance.rating)")
                    .accessibilityIdentifier("product.ageGuidance")
                    .taskCover(isPresented: $showsGuidance) {
                        InfoListCover(title: AgeGuidance.heading,
                                      values: ["Rated \(guidance.rating)"] + [guidance.source].compactMap { $0 } + guidance.descriptors)
                    }
                }
            }
            // R471 (42): the two cards side by side are one height (rule: side-by-side elements are equal), the taller's.
            .fixedSize(horizontal: false, vertical: true)
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
            // R471 (27), PROVISIONAL (frames show t20s, movie t06s): the column headings are large and bold, a step above
            // the section headers; a system text style, so Larger Text still applies. Title 3 (48 pt on tvOS, about one and a
            // half times the values' size in the frames); title 2 (57 pt) was a step too large.
            Text(heading)
                .font(.title3.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            ForEach(entries) { entry in
                VStack(alignment: .leading) {
                    if let badge = entry.badge {
                        // R471 (33), PROVISIONAL (frames show t20s, movie t06s): an Accessibility entry is its outlined
                        // badge ("SDH"), the one badge drawing (`BadgeOutline`), spoken by its full name.
                        BadgeOutline(text: badge)
                            .accessibilityLabel(entry.label)
                    } else {
                        FittingText(entry.label, style: .caption)
                            .foregroundStyle(ReadableSecondary.style)
                    }
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
