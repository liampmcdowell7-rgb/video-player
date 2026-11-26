import SwiftUI
import AppLogic
import UserData

/// R455 (owner's request of 23 Nov 2026, "choices of artwork"; PROVISIONAL): one gallery per picture kind, reached from
/// Edit > Artwork. Follows Apple's TV app (R312) and the HIG pages Collections (a grid of equal items that scrolls; focus lifts
/// the item), Focus and selection (the focused item is the one Select acts on) and Menus (the language filter is a system
/// menu). Poster tiles are 2:3, backgrounds, stills and logos 16:9; every tile shows its language in words and its pixel
/// size as text, and a system check on the current choice. Thumbnails are the small sizes; the full size is fetched only for
/// the chosen picture. The grid is lazy, so 100 or more candidates cost no more than the visible ones.
struct ArtworkGalleryView: View {
    let kind: ArtworkGalleryKind
    let artworkKey: String
    let keys: [UDEditKey]
    var onChanged: () -> Void = {}
    @Environment(AppServices.self) private var services
    @State private var gallery: ArtworkGallery?
    @State private var filter: ArtworkLanguageFilter = .all
    @State private var chosenID: String?
    @State private var working = false
    /// R471 (73): each choice and Automatic take a new number; a fetch sets its picture only if none was made while it waited.
    @State private var choiceGeneration = 0
    @State private var problem: String?
    @State private var webAddress = ""
    @State private var revision = 0

    private static let userLanguage = Locale.preferredLanguages.first
    private var originKey: String { "artworkChoice|" + (keys.first?.recordID ?? artworkKey) + "|" + kind.field.rawValue }
    private var hasChoice: Bool { _ = revision; return services.ledger.edits(for: keys)[kind.field]?.artwork != nil }

    private var columns: [GridItem] {
        // Equal tiles (S1, "side by side equal"): the same width in every column, five posters or three wide pictures a row.
        let count = kind.aspectRatio < 1 ? 5 : 3
        return Array(repeating: GridItem(.flexible()), count: count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                controls
                // R471 (36): what this kind of picture is used for, in one line of our own.
                Text(kind.purpose)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("artwork.purpose")
                if let gallery {
                    if gallery.onlineSwitchOff { onlineOffNote }
                    if gallery.isEmpty { Text(gallery.emptyText).foregroundStyle(.secondary) }
                    else { grid(gallery) }
                } else {
                    ProgressView()
                }
                webAddressSection
                if let problem { Text(problem).foregroundStyle(.secondary).accessibilityIdentifier("artwork.problem") }
            }
        }
        .scrollClipDisabled()
        .pushedScreen(kind.title)
        .task { await load() }
    }

    // MARK: Parts

    /// "Automatic" first and always visible, then the language filter (a system menu).
    private var controls: some View {
        HStack {
            Button { automatic() } label: {
                Label("Automatic", systemImage: hasChoice ? "arrow.uturn.backward" : "checkmark")
            }
            .accessibilityIdentifier("artwork.automatic")
            if let gallery, !gallery.isEmpty {
                let filters = ArtworkCandidates.filters(for: gallery.candidates, userLanguage: Self.userLanguage)
                Picker("Language", selection: $filter) {
                    ForEach(filters, id: \.self) { Text($0.title()).tag($0) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("artwork.language")
            }
        }
    }

    private var onlineOffNote: some View {
        VStack(alignment: .leading) {
            Text(ArtworkGallery.onlineOffLine).foregroundStyle(.secondary)
            NavigationLink("Open Online Lookup") { OnlineLookupSettingsView() }
                .accessibilityIdentifier("artwork.openOnlineLookup")
        }
    }

    private func grid(_ gallery: ArtworkGallery) -> some View {
        let shown = ArtworkCandidates.filtered(gallery.candidates, by: filter)
        return LazyVGrid(columns: columns, alignment: .leading) {
            ForEach(shown) { candidate in
                ArtworkCandidateTile(candidate: candidate, kind: kind, artworkKey: artworkKey, isChosen: candidate.id == chosenID) {
                    Task { await choose(candidate) }
                }
            }
        }
        .accessibilityIdentifier("artwork.grid")
    }

    /// A picture from a typed web address (the system text field), stored by its content like every other choice.
    private var webAddressSection: some View {
        VStack(alignment: .leading) {
            Text(ArtworkSourceKind.webAddress.title).font(.headline)
            TextField("Web Address of a Picture", text: $webAddress)
                .textContentType(.URL)
                .accessibilityIdentifier("artwork.webAddress")
            Button("Use This Picture") { Task { await chooseWebAddress() } }
                .disabled(working || webAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("artwork.useWebAddress")
        }
    }

    // MARK: Actions

    private func load() async {
        let found = await services.online.artworkGallery(key: artworkKey, kind: kind)
        gallery = found
        filter = ArtworkCandidates.defaultFilter(for: found.candidates, userLanguage: Self.userLanguage)
        chosenID = hasChoice ? UserDefaults.standard.string(forKey: originKey) : nil
    }

    private func choose(_ candidate: ArtworkCandidate) async {
        guard !working, let primary = keys.first else { return }
        working = true; problem = nil
        choiceGeneration += 1
        let generation = choiceGeneration
        let result = await services.online.storeChosenPicture(candidate, key: artworkKey, kind: kind)
        guard generation == choiceGeneration else { working = false; return }
        if let name = result.name {
            services.ledger.setEdit(primary, kind.field, .artwork(.file(name)))
            UserDefaults.standard.set(candidate.id, forKey: originKey)
            chosenID = candidate.id
            changed()
        } else {
            problem = result.problem
        }
        working = false
    }

    private func chooseWebAddress() async {
        guard !working, let primary = keys.first else { return }
        working = true; problem = nil
        choiceGeneration += 1
        let generation = choiceGeneration
        let result = await UserArtworkFolder.download(webAddress)
        guard generation == choiceGeneration else { working = false; return }
        if let name = result.name {
            services.ledger.setEdit(primary, kind.field, .artwork(.file(name)))
            UserDefaults.standard.removeObject(forKey: originKey)
            chosenID = nil
            webAddress = ""
            changed()
        } else {
            problem = result.problem
        }
        working = false
    }

    /// Automatic: the choice is removed and today's rule shows again.
    private func automatic() {
        choiceGeneration += 1                     // R471 (73): a picture still being fetched is not set when it arrives
        keys.forEach { services.ledger.resetEdit($0, kind.field) }
        UserDefaults.standard.removeObject(forKey: originKey)
        chosenID = nil
        problem = nil
        changed()
    }

    private func changed() {
        revision += 1
        services.online.artworkChanged()
        onChanged()
    }
}
