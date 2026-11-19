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
                }
                // #15 D3: how much is left, as text, instead of a full-width bar. Fixed in code, verify in next screenshots.
                if let timeLeft = content.timeLeft {
                    StatusText(timeLeft)
                }
                actions
                if let cast = details?.cast, !cast.isEmpty {
                    CastShelf(cast: cast)
                }
                if !content.mediaInfo.isEmpty {
                    MediaInfoSection(rows: content.mediaInfo)
                }
            }
        }
        .defaultFocus($playFocused, true)
        .background { BackdropView(artworkKey: content.artworkKey) }
        .task(id: "\(content.artworkKey)|\(services.online.keyRevision)") {
            details = content.kind == .movie ? await services.online.details(key: content.artworkKey) : nil
        }
        .pushedScreen(content.title)
    }

    private var actions: some View {
        // #15 D2: every button in the row uses `SlotLabel`, so the symbol slot, and with it the button height, is the same.
        HStack {
            Button { onPlay(false) } label: { SlotLabel(content.playTitle, systemImage: "play.fill") }
                .buttonStyle(.borderedProminent)
                .focused($playFocused)
            if content.canStartOver {
                Button { onPlay(true) } label: { SlotLabel("Start Over", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(.bordered)
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
            SlotLabel("More", systemImage: "ellipsis")
        }
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

/// The cast, in billing order, as a horizontal shelf of name and role (#15 6.2). Each entry takes focus so the remote can
/// move along the shelf; there is no person page, so selecting does nothing (OPEN_QUESTIONS R182). Shared by the movie page
/// and the show page (#22 B).
struct CastShelf: View {
    let cast: [TitleDetails.CastMember]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Cast")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top) {
                    ForEach(cast) { person in
                        VStack(alignment: .leading) {
                            FittingText(person.name, style: .callout)
                            if let role = person.role {
                                FittingText(role, style: .caption)
                                    .foregroundStyle(.secondary)
                            }
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

/// "Media Info" (#15 6.2): every row shown, never collapsed. The block takes focus as one piece so the remote scrolls the
/// page down to it.
private struct MediaInfoSection: View {
    let rows: [MediaInfoRow]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Media Info")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ForEach(rows) { row in
                LabeledContent(row.label, value: row.value)
                    .font(.callout)
            }
        }
        // design-lint:allow the section has no controls, so it takes focus as one block for the remote to scroll to it
        .focusable()
    }
}
