import SwiftUI
import AppLogic

/// The loaded detail page (#15 6.2), R350 (owner's device test of build 5, item D; PROVISIONAL) as the TV app's product
/// page: the artwork full bleed behind everything, clear at the top (`BackdropStyle.hero`); the first screen is the hero
/// area, its content at the bottom: title or title logo, ONE metadata line (year · duration · rating, then the outlined
/// format badges, `ProductMetadataLine`), the description, the buttons. Below it: Cast & Crew, then "Information", every
/// technical row of the file, always fully shown, most important first. Everything reachable is a button, a menu or a
/// focusable block, so the remote can scroll to all of it.
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
    /// R350: the height of the page's scroll view, so the hero area fills the first screen (`ProductPageLayout`).
    @State private var pageHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                hero
                if let cast = details?.cast, !cast.isEmpty {
                    CastShelf(cast: cast)
                }
                if !content.mediaInfo.isEmpty {
                    MediaInfoSection(rows: MediaInfo.withRating(content.mediaInfo, details: details), badges: content.allBadges)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { (height: CGFloat) in
            if abs(height - pageHeight) >= 0.5 { pageHeight = height }
        }
        // R345: the focused buttons and rows grow past the page's scroll view; it must not clip them.
        .scrollClipDisabled()
        // R346 (item A): the scrolling page is one focus region, so Up scrolls back to its first row before it
        // can leave for the tab bar (reason and UNVERIFIED cause: PaneColumns, App/Shared/SettingsPane.swift).
        .focusSection()
        .defaultFocus($playFocused, true)
        // #25 B10: the run on 1fe5d50 (78) opened the page with the TAB BAR focused: a page pushed at launch
        // (`-UITestOpen`, a Top Shelf link) gets the focus the tab bar had, and `defaultFocus` alone only picks where the
        // focus lands when it moves INTO the page. Asking for Play once the page is on screen moves it there.
        .task(id: content.itemID) { playFocused = true }
        .background { BackdropView(artworkKey: content.artworkKey, style: .hero) }
        .task(id: "\(content.artworkKey)|\(services.online.keyRevision)") {
            details = content.kind == .movie ? await services.online.details(key: content.artworkKey) : nil
        }
        .pushedScreen(content.title)
    }

    /// R350: the hero area, the first screen of the page, its content at the bottom over the clear artwork.
    private var hero: some View {
        VStack(alignment: .leading) {
            if let series = content.seriesTitle, let seriesID = content.seriesID {
                NavigationLink(series, value: Route.series(seriesID))
            }
            // #15 Part 9: a movie's title logo when one is found and the setting is on; otherwise the text title (rule S1).
            TitleHeader(title: content.title, artworkKey: content.kind == .movie ? content.artworkKey : nil)
            // R350: ONE line, the facts then the outlined format badges (dropped from the end when it does not fit).
            if !content.facts.isEmpty || !content.badges.isEmpty || details?.contentRating != nil {
                ProductMetadataLine(facts: content.facts, rating: details?.contentRating, badges: content.badges)
            }
            ContentAdviceLine(descriptors: details?.contentDescriptors ?? [])
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
        }
        .productHero(pageHeight: pageHeight)
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
/// R377 (audit docs/AUDIT_INVENTED_UI.md #1, owner 21 Nov 2026, rule R312): the whole text is a full-screen cover, as in
/// Apple's media catalog sample (a `.plain` button whose action sets a flag that presents `fullScreenCover` with the
/// description), no longer a pushed page. The cover keeps the R365 heading and the one focusable block (LongTextPage) so
/// the remote scrolls it. `taskCover` adds what every cover here has (opaque background, modal trait, CoverPresence).
/// UNVERIFIED (not on the sample's page): that Menu closes the cover on tvOS, and how the cover looks.
struct SynopsisLink: View {
    let title: String
    let text: String
    @State private var showsWholeText = false

    var body: some View {
        Button {
            showsWholeText = true
        } label: {
            Text(text)
                .font(.callout)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the whole synopsis")
        .taskCover(isPresented: $showsWholeText) {
            LongTextPage(title: title, text: text)
        }
    }
}

/// The cast, in billing order, as a horizontal shelf of photo, name and role (#15 6.2). Shared by the movie page and the show
/// page (#22 B). R341 (Decided by the owner, 21 Nov 2026; replaces "selecting does nothing", R182): each entry is a
/// borderless lockup that opens the person's page (`PersonView`), the titles in this library with that person, as the
/// Apple TV app's cast row opens a person. The circle takes the system highlight, as on the poster cards.
///
/// #25 B7 (OPEN_QUESTIONS R201): every entry has the same circle on top: the person's photo when there is one (today only the
/// generated test photos of the sample library; online photos are not requested), otherwise the system person symbol.
struct CastShelf: View {
    let cast: [TitleDetails.CastMember]
    /// The photo circle, scaled with the text size.
    @ScaledMetric(relativeTo: .callout) private var photoSize: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading) {
            Text(ProductPage.castHeading)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                // design-lint:allow HIG Layout, 40 pt spacing as every shelf of Apple's media catalog sample (R377, audit #10)
                LazyHStack(alignment: .top, spacing: 40) {
                    ForEach(cast) { person in
                        NavigationLink(value: Route.person(person.name)) {
                            VStack {
                                CastPhoto(url: person.photo, name: person.name)
                                    .frame(width: photoSize, height: photoSize) // design-lint:allow #25 B7: one text-scaled circle for every cast photo or placeholder, so the shelf entries line up (not a fixed card)
                                    // design-lint:allow R341: Apple's tvOS media catalog sample attaches the borderless lockup's highlight by hand to a custom artwork view; the system effect, not our own
                                    .hoverEffect(.highlight)
                                FittingText(person.name, style: .callout)
                                FittingText(person.role ?? " ", style: .caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                        }
                        .buttonStyle(.borderless)
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Shows the titles with \(person.name) in your library")
                    }
                }
            }
            .scrollClipDisabled()
        }
    }
}

/// #25 B7: a cast photo in a circle. R336 (PROVISIONAL, docs/HIG_AUDIT.md T8): with no photo (or while it fails to load)
/// the person's initials in the same circle, HIG Lockups, Monograms: "If an image isn't available, the person's initials
/// appear in place of an image." The system person symbol only when the name gives no initials. SwiftUI has no monogram
/// view (the HIG names TVUIKit's `TVMonogramContentView`); the circle is the system quaternary fill and the initials system
/// text: how close this is to `TVMonogramContentView` on tvOS 27 is UNVERIFIED.
private struct CastPhoto: View {
    let url: URL?
    let name: String

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
        // design-lint:allow R345: the cast photo itself is cut to a circle (the system highlight is attached to it); it holds no focusable row
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var placeholder: some View {
        let initials: String = Monogram.initials(name)
        if initials.isEmpty {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.secondary)
        } else {
            Circle()
                .fill(.quaternary)
                .overlay {
                    // R351: `.secondary` on the quaternary fill measured 3.53 to 3.56:1 (S2, S4, S6 in the run of 21 Nov);
                    // the initials take the primary label colour, as a monogram's initials are the circle's only content.
                    FittingText(initials, style: .title2)
                        .foregroundStyle(HierarchicalShapeStyle.primary)
                }
        }
    }
}

/// "Information" (#15 6.2; R350: named as the TV app names it, at the bottom of the page, formerly "Media Info"): every row shown, never collapsed, most important first (MediaInfo.rows). The block takes focus
/// as one piece so the remote scrolls the page down to it.
///
/// #25 B6: the run on 1fe5d50 (57, 58, 61) drew `LabeledContent`, which puts the value at the far right of the page, too far
/// from its label to follow. Now a two-column `Grid`: the value starts right after the longest label, and a system
/// `Divider` separates the rows, like the separators of a system list. A long value (the path, the subtitles) wraps inside
/// its column; labels stay on one line (rule S1).
private struct MediaInfoSection: View {
    let rows: [MediaInfoRow]
    /// R370: every format badge of the file, above the rows that say the same in full.
    var badges: [FormatBadgeItem] = []

    var body: some View {
        VStack(alignment: .leading) {
            Text(ProductPage.informationHeading)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if !badges.isEmpty {
                // R373: one line, dropped from the end, never wrapped; every badge is also a row below.
                BadgeRow(badges: badges, separate: true)
                    .accessibilityIdentifier("badges.all")
            }
            Grid(alignment: .leadingFirstTextBaseline) {
                ForEach(rows) { row in
                    GridRow {
                        // #33 K / #34 5b (R240, PROVISIONAL): the labels in primary at `ReadableSecondary.opacity`; the run of
                        // 20 Nov measured them at 3.56:1 and 4.24:1 in .secondary (78). Below the values, told apart by column too.
                        FittingText(row.label, style: .callout)
                            .foregroundStyle(ReadableSecondary.style)
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
