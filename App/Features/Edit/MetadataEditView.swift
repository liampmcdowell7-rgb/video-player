import SwiftUI
import AppLogic
import UserData

/// R449 (owner's request of 23 Nov 2026): edit a title's metadata at movie, show, season or episode level. One screen per
/// group (General, Artwork, Cast and Crew, Tags), each with Save and Cancel; only Reset asks for a confirmation (HIG
/// Alerts). Entry fields are the system's `TextField`; a long description uses `TextField(axis: .vertical)` (tvOS 16.0+;
/// `TextEditor` has no tvOS version, Apple's page). HIG Entering data: "Be clear about the data you need ... prefill fields
/// with reasonable default values". Edits are local to the app and go to iCloud with the other user data (PROVISIONAL,
/// OPEN_QUESTIONS R449).
struct MetadataEditView: View {
    let title: String
    let keys: [UDEditKey]
    /// R455: the artwork key ("item-42") and level of the title, for the artwork galleries of Edit > Artwork; nil: no gallery.
    var artworkKey: String? = nil
    var level: ArtworkGalleryKind.Level = .movie
    /// R471 (13): open straight on one group (Manage > Change Artwork opens Artwork); nil: the list of groups.
    var startGroup: UDEditField.Group? = nil
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false
    @State private var revision = 0

    var body: some View {
        NavigationStack {
            if let startGroup {
                EditGroupScreen(group: startGroup, keys: keys, artworkKey: artworkKey, level: level, onSaved: { revision += 1 })
            } else {
                groups
            }
        }
    }

    private var groups: some View {
            List {
                Section {
                    ForEach(UDEditField.Group.allCases, id: \.self) { group in
                        NavigationLink(group.title) { EditGroupScreen(group: group, keys: keys, artworkKey: artworkKey, level: level, onSaved: { revision += 1 }) }
                            .accessibilityIdentifier("edit.group." + group.rawValue)
                    }
                } footer: {
                    Text("Your edits stay on this device and your iCloud. A rescan, Fix Match or an online refresh never changes an edited field.")
                }
                Section {
                    Button("Reset All Edits", role: .destructive) { confirmReset = true }
                        .disabled(!hasEdits)
                        .accessibilityIdentifier("edit.resetAll")
                    // `pushedScreen` hides the navigation bar, so Save, Cancel and Done are rows of the page, not toolbar items.
                    Button("Done") { dismiss() }.accessibilityIdentifier("edit.done")
                }
            }
            .scrollClipDisabled()
            .pushedScreen(title)
            .confirmationDialog("Reset all edits of this title?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset All Edits", role: .destructive) {
                    if let key = keys.first { services.ledger.resetAllEdits(key) }
                    for key in keys.dropFirst() { services.ledger.resetAllEdits(key) }
                    revision += 1
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The title shows what the files and the online data say again.")
            }
    }

    private var hasEdits: Bool {
        _ = revision
        return !services.ledger.edits(for: keys).isEmpty
    }
}

extension UDEditField.Group {
    var title: String {
        switch self {
        case .general: return "General"
        case .artwork: return "Artwork"
        case .castAndCrew: return "Cast and Crew"
        case .tags: return "Tags"
        }
    }
}

/// One group's fields. Save writes only the fields that changed; Cancel writes nothing.
struct EditGroupScreen: View {
    let group: UDEditField.Group
    let keys: [UDEditKey]
    var artworkKey: String? = nil
    var level: ArtworkGalleryKind.Level = .movie
    var onSaved: () -> Void
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var texts: [UDEditField: String] = [:]
    @State private var original: [UDEditField: String] = [:]
    @State private var problem: String?
    @State private var working = false

    private var fields: [UDEditField] { UDEditField.allCases.filter { $0.group == group } }
    /// R455: the kinds a gallery already chooses; the typed address of those is the gallery's own "Web Address" section.
    private var galleryFields: [UDEditField] { artworkKey == nil ? [] : ArtworkGalleryKind.kinds(for: level).map(\.field) }

    var body: some View {
        Form {
            if group == .artwork, let artworkKey {
                // R455: a gallery of candidate pictures per kind of this level; the typed address fields below stay.
                Section {
                    ForEach(ArtworkGalleryKind.kinds(for: level), id: \.self) { kind in
                        NavigationLink(kind.title) { ArtworkGalleryView(kind: kind, artworkKey: artworkKey, keys: keys, onChanged: onSaved) }
                            .accessibilityIdentifier("edit.gallery." + kind.rawValue)
                    }
                } header: {
                    Text("Choose a Picture")
                } footer: {
                    Text("Pictures come from online, your files, your media server or a web address. Your choice stays on this device and in your iCloud backup.")
                }
            }
            ForEach(fields.filter { artworkKey == nil || group != .artwork || galleryFields.contains($0) == false }, id: \.self) { field in
                Section {
                    if long(field) {
                        TextField(field.label, text: binding(field), axis: .vertical).lineLimit(3...8)
                    } else {
                        TextField(field.label, text: binding(field))
                    }
                    if services.ledger.edits(for: keys).isEdited(field) {
                        LabeledContent("Status", value: "Edited")
                        Button("Reset \(field.label)", role: .none) {
                            keys.forEach { services.ledger.resetEdit($0, field) }
                            texts[field] = ""; original[field] = ""
                            onSaved()
                        }
                    }
                } header: {
                    Text(field.label)
                } footer: {
                    if let hint = field.hint { Text(hint) }
                }
            }
            if let problem { Section { Text(problem) } }
            Section {
                Button("Save") { Task { await save() } }.disabled(working).accessibilityIdentifier("edit.save")
                Button("Cancel") { dismiss() }.accessibilityIdentifier("edit.cancel")
            }
        }
        .scrollClipDisabled()
        .pushedScreen(group.title)
        .task { load() }
    }

    private func long(_ field: UDEditField) -> Bool { field == .overview || field == .cast || field == .crew }

    private func binding(_ field: UDEditField) -> Binding<String> {
        Binding(get: { texts[field] ?? "" }, set: { texts[field] = $0 })
    }

    private func load() {
        let edits = services.ledger.edits(for: keys)
        for field in fields where texts[field] == nil {
            let text = EditText.text(for: edits[field])
            texts[field] = text; original[field] = text
        }
    }

    private func save() async {
        working = true; problem = nil
        let primary = keys[0]
        for field in fields {
            let now = (texts[field] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard now != (original[field] ?? "") else { continue }
            if now.isEmpty { keys.forEach { services.ledger.resetEdit($0, field) }; continue }
            if field.group == .artwork, let a = await artwork(now) { services.ledger.setEdit(primary, field, .artwork(a)); continue }
            else if field.group == .artwork { working = false; return }
            services.ledger.setEdit(primary, field, EditText.value(from: now, field: field))
        }
        working = false
        onSaved(); dismiss()
    }

    /// A typed address becomes a file of the user-artwork folder; anything else stays as typed ("online:/path" for an online
    /// candidate). On a problem the screen stays open with the reason.
    private func artwork(_ text: String) async -> UDEditArtwork? {
        if text.hasPrefix("online:") || text.hasPrefix("file:") { return UDEditArtwork(stored: text) }
        let result = await UserArtworkFolder.download(text)
        if let name = result.name { return .file(name) }
        problem = result.problem
        return nil
    }
}

/// How a field's value is shown and read in a text field.
enum EditText {
    static func text(for value: UDEditValue?) -> String {
        switch value {
        case let .text(s)?: return s
        case let .number(n)?: return String(n)
        case let .list(l)?: return l.joined(separator: ", ")
        case let .people(p)?: return p.map { $0.role.isEmpty ? $0.name : "\($0.name) — \($0.role)" }.joined(separator: "\n")
        case let .artwork(a)?: return a.stored
        case nil: return ""
        }
    }

    static func value(from text: String, field: UDEditField) -> UDEditValue {
        switch field {
        case .runtime, .year, .seasonNumber, .episodeNumber: return .number(Int64(text.filter(\.isNumber)) ?? 0)
        case .genres, .collections, .labels:
            return .list(text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        case .cast, .crew:
            return .people(text.split(separator: "\n").map { line in
                let parts = line.components(separatedBy: " — ")
                return UDEditPerson(name: parts[0].trimmingCharacters(in: .whitespaces), role: parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : "")
            }.filter { !$0.name.isEmpty })
        default: return .text(text)
        }
    }
}

extension UDEditField {
    var label: String {
        switch self {
        case .title: return "Title"
        case .sortTitle: return "Sort Title"
        case .originalTitle: return "Original Title"
        case .tagline: return "Tagline"
        case .overview: return "Description"
        case .releaseDate: return "Release Date"
        case .year: return "Year"
        case .certification: return "Content Rating"
        case .studio: return "Studio or Network"
        case .runtime: return "Runtime in Minutes"
        case .seasonNumber: return "Season Number"
        case .episodeNumber: return "Episode Number"
        case .episodeTitle: return "Episode Title"
        case .airDate: return "Episode Air Date"
        case .genres: return "Genres"
        case .collections: return "Collections"
        case .labels: return "Labels"
        case .cast: return "Cast"
        case .crew: return "Crew"
        case .poster: return "Poster"
        case .backdrop: return "Background"
        case .logo: return "Logo"
        case .seasonPoster: return "Season Poster"
        case .episodeStill: return "Episode Still"
        }
    }

    var hint: String? {
        switch self {
        case .releaseDate, .airDate: return "Year, month and day as 2024-05-31."
        case .genres, .collections, .labels: return "Separate entries with commas."
        case .cast: return "One person per line: Name — role."
        case .crew: return "One person per line: Name — role, for example director or writer."
        case .poster, .backdrop, .logo, .seasonPoster, .episodeStill:
            return "A web address of a picture. It is saved on this device and in your iCloud backup."
        default: return nil
        }
    }
}
