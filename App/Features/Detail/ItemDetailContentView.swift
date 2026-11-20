import SwiftUI
import AppLogic

/// The loaded detail page (#15 6.2): backdrop with scrim; title or title logo; "year · duration · rating"; the format line;
/// the synopsis; the buttons; the cast; then "Media Info", always fully shown. Everything reachable is a button, a menu or
/// a focusable block, so the remote can scroll to all of it.
struct ItemDetailContentView: View {
    let content: ItemDetailContent
    let model: ScreenModel<ItemDetailViewModel>
    var onPlay: (Bool) -> Void
    var onFixMatch: () -> Void
    var onSortInfo: () -> Void = {}
    @Environment(AppServices.self) private var services
    @State private var details: TitleDetails?
    /// #15 6.2: Play (or Resume) has focus when the page opens, although the synopsis sits above it.
    @FocusState private var playFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                if let series = content.seriesTitle, let seriesID = content.seriesID {
                    NavigationLink(series, value: Route.series(seriesID))
                }
                // #15 Part 9: a movie's title logo when one is found and the setting is on; otherwise the text title (rule S1).
                TitleHeader(title: content.title, artworkKey: content.kind == .movie ? content.artworkKey : nil)
                if !content.facts.isEmpty {
                    FittingText(content.facts, style: .body)
                        .foregroundStyle(.secondary)
                }
                if !content.badges.isEmpty {
                    FittingLine(line: CardBuilder.badgeLine(content.badges), style: .callout)
                        .foregroundStyle(.secondary)
                }
                if let overview = details?.overview {
                    SynopsisLink(title: content.title, text: overview)
                } else if content.kind == .movie, !services.online.hasCatalogueKey {
                    // #26 item 4: one short line saying the synopsis needs the key and where to add it.
                    StatusText(OnlineLookupText.detailsNeedKey)
                }
                // #15 D3: how much is left, as text, instead of a full-width bar. Fixed in code, verify in next screenshots.
                if let timeLeft = content.timeLeft {
                    StatusText(timeLeft)
                }
                actions
                    // #33 I (OPEN_QUESTIONS R239, PROVISIONAL): room between the button row and the next heading.
                    .padding(.bottom, DetailPageLayout.belowActions)
                if let cast = details?.cast, !cast.isEmpty {
                    CastShelf(cast: cast)
                }
                if !content.mediaInfo.isEmpty {
                    MediaInfoSection(rows: content.mediaInfo)
                }
            }
        }
        .defaultFocus($playFocused, true)
        // #25 B10: the run on 1fe5d50 (78) opened the page with the TAB BAR focused: a page pushed at launch
        // (`-UITestOpen`, a Top Shelf link) gets the focus the tab bar had, and `defaultFocus` alone only picks where the
        // focus lands when it moves INTO the page. Asking for Play once the page is on screen moves it there.
        .task(id: content.itemID) { playFocused = true }
        .background { BackdropView(artworkKey: content.artworkKey) }
        .task(id: "\(content.artworkKey)|\(services.online.keyRevision)") {
            details = content.kind == .movie ? await services.online.details(key: content.artworkKey) : nil
        }
        .pushedScreen(content.title)
    }

    private var actions: some View {
        // #25 B5: every button in the row uses the system `Label` (`ActionLabel`), one height for the row (`ActionRow`), and
        // each button as wide as its content.
        ActionRow {
            Button { onPlay(false) } label: { ActionLabel(content.playTitle, systemImage: "play.fill") }
                .buttonStyle(.borderedProminent)
                .focused($playFocused)
                .accessibilityIdentifier(ControlID.play)
            if content.canStartOver {
                Button { onPlay(true) } label: { ActionLabel("Start Over", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(ControlID.startOver)
            }
            if content.versions.count > 1 {
                VersionsMenu(versions: content.versions, model: model)
            }
            if !content.extras.isEmpty {
                ExtrasMenu(extras: content.extras)
            }
            moreMenu
        }
    }

    private var moreMenu: some View {
        Menu {
            Button(content.isWatched ? "Mark as Unwatched" : "Mark as Watched", systemImage: content.isWatched ? "eye.slash" : "eye") {
                Task { await model.run { await $0.setWatched(!content.isWatched) } }
            }
            Button(content.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: content.isFavorite ? "heart.slash" : "heart") {
                Task { await model.run { await $0.toggleFavorite() } }
            }
            Button("Fix Match", systemImage: "magnifyingglass", action: onFixMatch)
            // docs/SORTING.md: which rule put this title in Movies or Shows, with Move and Sort Automatically.
            Button("How This Was Sorted", systemImage: "arrow.up.arrow.down", action: onSortInfo)
        } label: {
            ActionLabel("More", systemImage: "ellipsis")
        }
        // #25 A2: the Menu is a Button with no label of its own (57-movie-detail-HIERARCHY.txt); name it once, here.
        .accessibilityLabel("More")
        .accessibilityIdentifier(ControlID.more)
    }
}

/// Three lines of the synopsis; selecting it opens the whole text (rule L5: the complete text one press away, so nothing is
/// cut off for good). Shared by the movie page and the show page (#22 B).
struct SynopsisLink: View {
    let title: String
    let text: String

    var body: some View {
        NavigationLink {
            LongTextPage(title: title, text: text)
        } label: {
            Text(text)
                .font(.callout)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the whole synopsis")
    }
}

/// The cast, in billing order, as a horizontal shelf of photo, name and role (#15 6.2). Each entry takes focus so the remote
/// can move along the shelf; there is no person page, so selecting does nothing (OPEN_QUESTIONS R182). Shared by the movie
/// page and the show page (#22 B).
///
/// #25 B7 (OPEN_QUESTIONS R201): every entry has the same circle on top: the person's photo when there is one (today only the
/// generated test photos of the sample library; online photos are not requested), otherwise the system person symbol.
struct CastShelf: View {
    let cast: [TitleDetails.CastMember]
    /// The photo circle, scaled with the text size.
    @ScaledMetric(relativeTo: .callout) private var photoSize: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading) {
            Text("Cast")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top) {
                    ForEach(cast) { person in
                        VStack {
                            CastPhoto(url: person.photo)
                                .frame(width: photoSize, height: photoSize) // design-lint:allow #25 B7: one text-scaled circle for every cast photo or placeholder, so the shelf entries line up (not a fixed card)
                            FittingText(person.name, style: .callout)
                            FittingText(person.role ?? " ", style: .caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        // design-lint:allow a cast entry has no action (no person page), but it must take focus so the remote can move along the shelf
                        .focusable()
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }
}

/// #25 B7: a cast photo in a circle, or the system person symbol in the same circle while there is none (or it fails to load).
private struct CastPhoto: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(.secondary)
    }
}

/// "Media Info" (#15 6.2): every row shown, never collapsed, most important first (MediaInfo.rows). The block takes focus
/// as one piece so the remote scrolls the page down to it.
///
/// #25 B6: the run on 1fe5d50 (57, 58, 61) drew `LabeledContent`, which puts the value at the far right of the page, too far
/// from its label to follow. Now a two-column `Grid`: the value starts right after the longest label, and a system
/// `Divider` separates the rows, like the separators of a system list. A long value (the path, the subtitles) wraps inside
/// its column; labels stay on one line (rule S1).
private struct MediaInfoSection: View {
    let rows: [MediaInfoRow]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Media Info")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Grid(alignment: .leadingFirstTextBaseline) {
                ForEach(rows) { row in
                    GridRow {
                        // #33 K (R240, PROVISIONAL): the labels in the primary system colour; the run of 20 Nov measured them
                        // at 3.56:1 and 4.24:1 in .secondary (78). Label and value are told apart by their column.
                        FittingText(row.label, style: .callout)
                            .foregroundStyle(.primary)
                        Text(row.value)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if row.id != rows.last?.id {
                        Divider()
                    }
                }
            }
        }
        // design-lint:allow the section has no controls, so it takes focus as one block for the remote to scroll to it
        .focusable()
    }
}
