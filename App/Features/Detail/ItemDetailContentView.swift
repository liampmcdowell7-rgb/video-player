import SwiftUI
import AppLogic
import UserData

/// The loaded detail page (#15 6.2), R350 (owner's device test of build 5, item D; PROVISIONAL) as the TV app's product
/// page: the artwork full bleed behind everything, clear at the top (`BackdropStyle.hero`); the first screen is the hero
/// area, its content at the bottom: title or title logo, ONE metadata line (year · duration · rating, then the outlined
/// format badges, `ProductMetadataLine`), the description, the buttons. Below it: Cast & Crew, then "Information", every
/// technical row of the file, always fully shown, most important first. Everything reachable is a button, a menu or a
/// focusable block, so the remote can scroll to all of it.
///
/// R387 (PROVISIONAL; owner's device test, item A): an episode gets the same page, not a second design: the episode's own
/// still as the hero picture (the show's backdrop only without one), the show's name, "S1, E3" (R358's form) above the
/// episode's title, the metadata line (runtime, the source's rating, the episode's rating or else the show's, the format
/// badges), the source's synopsis in the same cover, the same buttons, then a row of the season's other episodes (the show
/// page's shelf), the cast when the source gives one, and Information. A part with no data is left out.
struct ItemDetailContentView: View {
    let content: ItemDetailContent
    let model: ScreenModel<ItemDetailViewModel>
    var onPlay: (Bool) -> Void
    var onFixMatch: () -> Void
    var onSortInfo: () -> Void = {}
    /// R449: the edit screens (title, artwork, cast and crew, tags).
    var onEdit: () -> Void = {}
    @Environment(AppServices.self) private var services
    @State private var details: TitleDetails?
    /// R457: Hide Spoilers covers the episode page's own picture and description.
    @AppStorage(AppPreference.hideSpoilers.rawValue) private var hideSpoilers = false
    /// #15 6.2: Play (or Resume) has focus when the page opens, although the synopsis sits above it.
    @FocusState private var playFocused: Bool
    /// R350: the height of the page's scroll view, so the hero area fills the first screen (`ProductPageLayout`).
    @State private var pageHeight: CGFloat = 0
    /// R452: where the title (the first line of text) begins, for the cover behind it.
    @State private var textTop: CGFloat?
    /// R387: the show's age rating, asked for only when an episode has none of its own (`EpisodePage.needsSeriesRating`).
    @State private var seriesRating: String?
    /// R387: the episode's show, for the row of the season's other episodes (the show page's model, so a card's context
    /// menu marks it watched as on the show page). Nil for a movie.
    @State private var seasonModel: ScreenModel<SeasonsViewModel>?

    /// R387: the rating on the metadata line: the title's own, else (an episode) its show's.
    private var rating: String? { EpisodePage.rating(episode: details?.contentRating, series: seriesRating) }

    /// R387: the season's other episodes; nil (no row) for a movie, before the show is loaded, or for a lone episode.
    private var otherEpisodes: SeasonSection? {
        guard content.kind == .episode, let seasons = seasonModel?.screen.state.content?.seasons else { return nil }
        return EpisodePage.otherEpisodes(in: seasons, season: content.season, currentID: content.itemID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                hero
                // R387: as on the show page, the episodes right after the hero, then the cast.
                if let other = otherEpisodes, let seasonModel {
                    VStack(alignment: .leading) {
                        ShelfHeader(other.title)
                        EpisodeShelfRow(episodes: other.episodes, model: seasonModel)
                    }
                    // R424: Up or Down from any card of the row next to it reaches this row.
                    .productPageRow()
                }
                if let cast = details?.cast, !cast.isEmpty {
                    CastShelf(cast: cast)
                }
                if !content.mediaInfo.isEmpty {
                    // R392 (items 5 d and 7): when Information is the first section under the hero, its heading and
                    // badge row fill the rest of the first screen, so the table of specs starts below the fold.
                    let firstBelowHero: Bool = otherEpisodes == nil && (details?.cast ?? []).isEmpty
                    MediaInfoSection(rows: MediaInfo.withRating(content.mediaInfo, details: details), badges: content.allBadges,
                                     headerMinHeight: firstBelowHero ? pageHeight * (1 - ProductPageLayout.heroFraction) : 0)
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
        .artTextTop($textTop)
        .background {
            BackdropView(artworkKey: content.artworkKey, style: .hero, prefersEpisodeStill: content.kind == .episode, textTop: textTop)
                .blur(radius: content.kind == .episode && SpoilerRules.hidesStill(watched: content.isWatched, hideSpoilers: hideSpoilers) ? 30 : 0) // design-lint:allow R457: the spoiler blur of an unwatched episode's still, only while Hide Spoilers is on; not a glass or scrim
        }
        .task(id: "\(content.artworkKey)|\(services.online.keyRevision)|\(hideSpoilers)|\(content.isWatched)") {
            // R387: an episode asks too; only the source's own layer answers for one (Wikidata and TMDB give nothing).
            var own = await services.online.details(key: content.artworkKey)
            // R449: the user's edits (description, cast, content rating) on top of every layer, read each time the page loads.
            if let item = try? await services.store.item(id: content.itemID) {
                let files = (try? await services.store.versions(of: content.itemID)) ?? []
                own = EditTarget.apply(services.ledger.edits(for: EditTarget.keys(for: item, files: files)), to: own)
            }
            // R456: Hide Spoilers replaces the description of an unwatched episode (the user's own edit is hidden too: it is a description).
            if content.kind == .episode, var hidden = own, hideSpoilers {
                hidden.overview = SpoilerRules.synopsis(hidden.overview, watched: content.isWatched, hideSpoilers: hideSpoilers)
                own = hidden
            }
            details = own
            if EpisodePage.needsSeriesRating(kind: content.kind, seriesID: content.seriesID, ownRating: own?.contentRating),
               let seriesID = content.seriesID {
                seriesRating = await services.online.details(key: "series-\(seriesID)")?.contentRating
            } else {
                seriesRating = nil
            }
        }
        // R387: the show's seasons for the row of other episodes, again when the library or this episode's mark changes.
        .task(id: "\(content.seriesID ?? 0)|\(services.libraryRevision)|\(content.isWatched)") {
            guard content.kind == .episode, let seriesID = content.seriesID else { seasonModel = nil; return }
            if seasonModel == nil { seasonModel = ScreenModel(SeasonsViewModel(store: services.store, seriesID: seriesID)) }
            await seasonModel?.run { await $0.load() }
        }
        .pushedScreen(content.title)
    }

    /// R350: the hero area, the first screen of the page, its content at the bottom over the clear artwork.
    /// R396 (docs/AUDIT_VISUAL_TVAPP.md, Apple's pictures B1 and A4 of the TV app's product pages): the order is Apple's:
    /// title, synopsis, the info line with the badges, the buttons; at the trailing edge, level with the buttons, the
    /// "Starring" block (M7). An episode (E1, E2): the large title is the EPISODE's own title; the show's name and
    /// "S1, E3" are one small line above it, plain text, no longer a button (Go to Show is in More).
    private var hero: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading) {
                if let overline = ProductPage.episodeOverline(show: content.seriesTitle, code: content.episodeCode) {
                    FittingText(overline, style: .headline)
                        .foregroundStyle(ReadableSecondary.style)
                        .accessibilityIdentifier("product.episodeOverline")
                }
                // #15 Part 9: a movie's title logo when one is found and the setting is on; otherwise the text title.
                TitleHeader(title: content.episodeTitle ?? content.title, artworkKey: content.kind == .movie ? content.artworkKey : nil)
                // R404 (owner's review of the run on f0a67d3, item 6 b): nothing at all in the stack when there is no
                // content advice. Picture 106 showed a blank band of about 60 pt between the title and the synopsis;
                // the advice line is the only part between them that can draw nothing (Sample Movie 1 has none). Whether
                // an empty child took the stack's spacing is UNVERIFIED: the new -TITLE-GAP note of 57 and 55 measures it.
                if let advice = details?.contentDescriptors, !advice.isEmpty {
                    ContentAdviceLine(descriptors: advice)
                }
                // R453 (PROVISIONAL): the typed info (runtime, release date, the rating box, resolution, audio; the genres; the
                // synopsis) as on the show page, parts with no data left out. The synopsis stays the whole-text button (L5).
                let block: InfoBlock = InfoBlock.show(InfoFacts(content: content, details: details, contentRating: rating))
                InfoBlockView(block: block, fullText: (title: content.episodeTitle ?? content.title, artworkKey: content.artworkKey,
                                                       prefersEpisodeStill: content.kind == .episode))
                if details?.overview == nil, content.kind == .movie, !services.online.hasCatalogueKey {
                    // #26 item 4: one short line saying the synopsis needs the key and where to add it.
                    StatusText(OnlineLookupText.detailsNeedKey)
                }
                // R392 (item 5 b; audit M3): the time left ("29 min left", #15 D3), plain text under the block. Apple's product
                // pages show no progress line at all (B1, A4), so there is no Apple place to move it to.
                if let timeLeft = content.timeLeft {
                    Text(timeLeft)
                        .font(.callout)
                        .foregroundStyle(ReadableSecondary.style)
                        .accessibilityIdentifier("product.timeLeft")
                }
                actions
            }
            Spacer(minLength: 0)
            if let starring = ProductPage.starring((details?.cast ?? []).map(\.name)) {
                StarringBlock(names: starring)
            }
        }
        // #33 I (OPEN_QUESTIONS R239, PROVISIONAL): room between the button row and the next heading.
        .padding(.bottom, DetailPageLayout.belowActions)
        .productHero(pageHeight: pageHeight)
        // R424 (run #28, 58-movie-detail-SCROLL-UP): the hero is a focus section the page's whole width, so Up from any
        // entry of the row below (the cast, the season's episodes) climbs back into it, and Play (or Resume) takes the
        // focus then, not the button nearest to where the focus came from (`defaultFocus`, priority `.userInitiated`:
        // Apple's page, "use the client's preferred default focus in response to user-driven focus navigation").
        .focusSection()
        .defaultFocus($playFocused, true, priority: .userInitiated)
    }

    private var actions: some View {
        // #25 B5: every button in the row uses the system `Label` (`ActionLabel`), one height for the row (`ActionRow`), and
        // each button as wide as its content.
        ActionRow {
            Button { onPlay(false) } label: { ActionLabel(content.playTitle, systemImage: "play.fill") }
                .buttonStyle(.borderedProminent)
                .focused($playFocused)
                .accessibilityIdentifier(ControlID.play)
            // R396 (audit SF2, M4): one prominent Play or Resume, then round icon buttons (Apple's pictures B1, A4).
            // Every action is still here: Start Over, Versions, Extras and More, each named for VoiceOver.
            if content.canStartOver {
                Button { onPlay(true) } label: { ActionLabel("Start Over", systemImage: "arrow.counterclockwise", iconOnly: true) }
                    .roundAction()
                    .accessibilityLabel("Start Over")
                    .accessibilityIdentifier(ControlID.startOver)
            }
            if content.versions.count > 1 {
                VersionsMenu(versions: content.versions, model: model)
            }
            if !content.extras.isEmpty {
                ExtrasMenu(extras: content.extras)
            }
            // R453 (PROVISIONAL): round icon-only buttons of one size, in the owner's order: Watched (the check when watched,
            // the eye when not), Favourite, More. No Watchlist or Add to List: the library has neither (docs in R453).
            Button { Task { await model.run { await $0.setWatched(!content.isWatched) } } } label: {
                ActionLabel("Watched", systemImage: PageButtonSymbols.watched(content.isWatched), iconOnly: true)
            }
            .roundAction()
            // The More menu keeps the "Mark as Watched" items (the existing pictures 44 to 46), so this one is named by its state.
            .accessibilityLabel("Watched")
            .accessibilityValue(content.isWatched ? "On" : "Off")
            .accessibilityHint(content.isWatched ? "Marks it as unwatched" : "Marks it as watched")
            .accessibilityIdentifier(ControlID.watched)
            Button { Task { await model.run { await $0.toggleFavorite() } } } label: {
                ActionLabel("Favorite", systemImage: PageButtonSymbols.favourite(content.isFavorite), iconOnly: true)
            }
            .roundAction()
            .accessibilityLabel("Favorite")
            .accessibilityValue(content.isFavorite ? "On" : "Off")
            .accessibilityHint(content.isFavorite ? "Removes it from your favorites" : "Adds it to your favorites")
            .accessibilityIdentifier(ControlID.favorite)
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
            Button("Edit", systemImage: "pencil", action: onEdit)
                .accessibilityIdentifier(ControlID.editMetadata)
            // R460: Fix Match lists catalogue titles that are not in the library, so it is off while Restrictions are on.
            if OnlineTitleSurface.fixMatchCandidates.isAvailable(restricted: services.restrictionsOn) {
                Button("Fix Match", systemImage: "magnifyingglass", action: onFixMatch)
            }
            // docs/SORTING.md: which rule put this title in Movies or Shows, with Move and Sort Automatically.
            Button("How This Was Sorted", systemImage: "arrow.up.arrow.down", action: onSortInfo)
            // R396 (audit E2): the show's page, reached from here now that the show's name above the title is text.
            if let seriesID = content.seriesID {
                Button("Go to Show", systemImage: "tv") { services.openRequest = Route.series(seriesID) }
            }
        } label: {
            ActionLabel("More", systemImage: "ellipsis", iconOnly: true)
        }
        .roundAction()
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
///
/// R392 (owner's review of the run on fd9731f, items 5 a and 8; PROVISIONAL):
/// - On the page the three lines ran the full 1,750 pt width. They now take half the page (`ProductPageSpacing`
///   `synopsisColumns`: HIG Layout's two-column grid, 860 pt on a 1920 pt screen), at the leading edge of the hero. The
///   sample shows its description as one column of three on the product page but gives no width for it.
/// - The cover was a plain black screen with the title touching the text and the text edge to edge. It is now the sample's
///   cover: the text in a column of at most 600 pt (`Text(loremIpsum).frame(maxWidth: 600)`, "Provide product highlight
///   pages"), centred, over the title's own artwork under the system material (`BackdropView`, style `.page`: the sample's
///   "showcase image, with a suitable blur, as a background"). The title and the text are a system `VStack` at the
///   system's spacing.
struct SynopsisLink: View {
    let title: String
    let text: String
    /// The artwork behind the cover ("item-N" or "series-N"); nil keeps the plain system background.
    var artworkKey: String? = nil
    var prefersEpisodeStill: Bool = false
    /// R453: the three lines are reserved even for a shorter text (the show page's info block keeps one height).
    var reservesSpace: Bool = false
    @State private var showsWholeText = false

    var body: some View {
        Button {
            showsWholeText = true
        } label: {
            Text(text)
                .font(.callout)
                .lineLimit(3, reservesSpace: reservesSpace)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        // R396 (audit SF3, M2): at most 650 pt wide (`RowSpacing.textColumn`), as on Apple's product pages (B1 about
        // 650 pt, A4 about 658 pt). R392 had half the page (860 pt).
        .frame(maxWidth: CGFloat(RowSpacing.textColumn), alignment: .leading)
        .accessibilityHint("Shows the whole synopsis")
        // R404: found by the -TITLE-GAP note of the UI tests.
        .accessibilityIdentifier("product.synopsis")
        .taskCover(isPresented: $showsWholeText) {
            SynopsisCover(title: title, text: text, artworkKey: artworkKey, prefersEpisodeStill: prefersEpisodeStill)
        }
    }
}

/// R396 (audit M7): the "Starring" block at the trailing edge of a product page's first screen, level with the buttons,
/// as on Apple's movie page (picture B1: "Starring" in the secondary colour, the names after it, at most about 330 pt
/// wide). Text only; the cast shelf below opens each person's page. No "Director" line: the library holds none.
struct StarringBlock: View {
    let names: String

    var body: some View {
        // R398: one `Text` with the label interpolated in the secondary style (Apple deprecates `Text` + `Text`: "Use
        // string interpolation on Text instead").
        Text("\(Text(ProductPage.starringLabel).foregroundStyle(.secondary)) \(names)")
            .font(.caption)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            // R404 (item 6 a): the lines break only between names (`ProductPage.starring` keeps each name whole).
            .frame(maxWidth: CGFloat(RowSpacing.creditsWidth), alignment: .leading)
            .accessibilityLabel(ProductPage.starringLabel + ": " + names)
            .accessibilityIdentifier("product.starring")
    }
}

/// R392 (item 8): the whole synopsis, as the cover of Apple's media catalog sample. It has no controls, so the scroll
/// view takes the focus and the remote scrolls a long text (as `LongTextPage`); Menu closes it (UNVERIFIED, R377).
struct SynopsisCover: View {
    let title: String
    let text: String
    let artworkKey: String?
    let prefersEpisodeStill: Bool

    var body: some View {
        // design-lint:allow R345: a long text holds no focusable row (the scroll view itself takes focus)
        ScrollView {
            VStack(alignment: .leading) {
                // R365: the title says whose synopsis this is. One line, rule S1.
                FittingText(title, style: .title2)
                    .accessibilityAddTraits(.isHeader)
                Text(text)
                    .font(.body)
            }
            // R396 (audit SF3, F1): the same text column as on the page (650 pt, Apple's pictures); the sample's own
            // cover has `.frame(maxWidth: 600)`.
            .frame(maxWidth: CGFloat(RowSpacing.textColumn), alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        // design-lint:allow the cover has no controls, so the scroll view itself takes focus for the Siri Remote to scroll it
        .focusable()
        .background {
            if let artworkKey {
                BackdropView(artworkKey: artworkKey, style: .page, prefersEpisodeStill: prefersEpisodeStill)
            }
        }
        .pushedScreen(title)
    }
}

/// The cast, in billing order, as a horizontal shelf of photo, name and role (#15 6.2). Shared by the movie page and the show
/// page (#22 B). R341 (Decided by the owner, 21 Nov 2026; replaces "selecting does nothing", R182): each entry is a
/// borderless lockup that opens the person's page (`PersonView`), the titles in this library with that person, as the
/// Apple TV app's cast row opens a person. The circle takes the system highlight, as on the poster cards.
///
/// #25 B7 (OPEN_QUESTIONS R201): every entry has the same circle on top: the person's photo when there is one (today only the
/// generated test photos of the sample library; online photos are not requested), otherwise the system person symbol.
///
/// R392 (owner's review of the run on fd9731f, item 5 c; PROVISIONAL): the entry is the sample's "Shaped" lockup ("Create
/// content lockups": the image and the text as SIBLINGS in the label, the highlight on the image, and
/// `.buttonBorderShape(.circle)` on the button), sized as the sample sizes a shelf's lockups ("attach the modifier to the
/// `Image` instance within the button's label closure to make the image the source of the frame calculations":
/// `containerRelativeFrame(.horizontal, count:spacing:)`). Cause of the fault: the label was ONE `VStack` with a padding of
/// ours, so the system's highlight and outline took that padded square, not the circle (a square behind each circle, a
/// square highlight cutting it); the circle had a fixed 120 pt frame while each entry was as wide as its name, so the
/// circles stood 282 pt apart although the row's spacing was 40. Now the circle is the width of one of eight columns
/// (184 pt, HIG Layout's eight-column grid) and the names wrap inside that width, so the circles are 40 pt apart.
struct CastShelf: View {
    let cast: [TitleDetails.CastMember]

    var body: some View {
        VStack(alignment: .leading) {
            ShelfHeader(ProductPage.castHeading)
            ScrollView(.horizontal) {
                // design-lint:allow HIG Layout, 40 pt spacing as every shelf of Apple's media catalog sample (R377, audit #10)
                LazyHStack(alignment: .top, spacing: 40) {
                    ForEach(cast) { person in
                        NavigationLink(value: Route.person(person.name)) {
                            CastPhoto(url: person.photo, name: person.name)
                                .aspectRatio(1, contentMode: .fit)
                                // design-lint:allow R392: HIG Layout's eight-column grid (184 pt, 40 pt spacing); the circle sets the entry's width, as the sample's lockups
                                .containerRelativeFrame(.horizontal, count: ProductPageSpacing.castColumns, spacing: 40)
                                // design-lint:allow R341: Apple's tvOS media catalog sample attaches the borderless lockup's highlight by hand to a custom artwork view; the system effect, not our own
                                .hoverEffect(.highlight)
                            CastCaption(text: person.name, style: .caption)
                            if let role = person.role {
                                CastCaption(text: role, style: .caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.borderless)
                        .buttonBorderShape(.circle)
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Shows the titles with \(person.name) in your library")
                    }
                }
            }
            .scrollClipDisabled()
        }
        // R424: the cast row is a focus section the page's whole width (show, movie and episode pages).
        .productPageRow()
    }
}

/// R392: a name or role under a cast circle: centred, as wide as the circle, wrapped onto as many lines as it needs,
/// never cut and never scaled (every entry at the same size).
private struct CastCaption: View {
    let text: String
    let style: TVTextStyle

    var body: some View {
        Text(text)
            .font(style.font)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            // design-lint:allow R392: the same eight-column width as the circle above it, so a long name wraps under its own circle
            .containerRelativeFrame(.horizontal, count: ProductPageSpacing.castColumns, spacing: 40)
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
    /// R392 (items 5 d and 7): the least height of the heading and badge row. The page passes the part of the first
    /// screen under the hero when Information comes right after it, so the table starts below the fold; 0 otherwise.
    var headerMinHeight: CGFloat = 0

    var body: some View {
        // R392 (item 5 d): one given spacing between the heading, the badge row and the table (`informationRows`).
        // Before, the stack gave none and took the system's default, which is wide on tvOS.
        VStack(alignment: .leading, spacing: CGFloat(ProductPageSpacing.informationRows)) {
            VStack(alignment: .leading, spacing: CGFloat(ProductPageSpacing.informationRows)) {
                Text(ProductPage.informationHeading)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if !badges.isEmpty {
                    // R373: one line, dropped from the end, never wrapped; every badge is also a row below.
                    BadgeRow(badges: badges, separate: true)
                        .accessibilityIdentifier("badges.all")
                }
            }
            .frame(minHeight: headerMinHeight, alignment: .topLeading)
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
        // R424 (run #28, item 1): the block as one accessibility container with its own name, its rows still read one by
        // one. Run #28's note named the focused block "PG-13" (324, 158): the first value of the table (Rating is its first
        // row), because the focusable block was no accessibility element of its own (UNVERIFIED how XCTest picked that
        // text; the rating badge on the metadata line is not focusable).
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ProductPage.informationHeading)
        .accessibilityIdentifier("product.information")
    }
}
