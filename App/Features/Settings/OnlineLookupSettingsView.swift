import SwiftUI
import AppLogic

/// Settings > Online Lookup: the user's own keys for pictures, Fix Match, Discover, where to watch and ratings, and the region
/// for where-to-watch lists. States plainly what is sent and where, and that nothing is sent until a key is entered (D10).
/// There is no "test key" button: a key is checked the first time it is used, and a rejected key is reported on the screen
/// that used it (PROVISIONAL; alternative: a button that makes one request on an explicit press).
struct OnlineLookupSettingsView: View {
    @Environment(AppServices.self) private var services
    @AppStorage(OnlineLookupPrefs.regionKey) private var region = OnlineLookupPrefs.defaultRegion

    // #15 3.5: bounded column; the on/off state is status text (L3); the 8-line paragraph is a one-line footer plus the
    // "What Is Sent" page with the complete text unchanged (L5). The key fields and Save Key buttons come first.
    var body: some View {
        SettingsPane(title: OnlineLookupText.settingsTitle, summary: SettingsTexts.onlineSummary,
                     status: [OnlineLookupText.status(hasTMDB: services.online.hasCatalogueKey, hasOMDb: services.online.hasRatingsKey)]) {
            Section {
                LearnMoreLink(title: SettingsTexts.whatIsSentTitle, text: OnlineLookupText.whatIsSent)
            } footer: {
                Text(SettingsTexts.whatIsSentShort)
            }
            KeyRow(kind: .tmdb, label: OnlineLookupText.tmdbLabel, help: OnlineLookupText.tmdbHelp)
            KeyRow(kind: .omdb, label: OnlineLookupText.omdbLabel, help: OnlineLookupText.omdbHelp)
            Section {
                TextField(OnlineLookupText.regionLabel, text: $region)
                    .autocorrectionDisabled()
            } footer: {
                Text(OnlineLookupText.regionHelp)
            }
            Section {
                LearnMoreLink(title: SettingsTexts.aboutKeysTitle, text: SettingsTexts.aboutKeysFull)
                // The data providers' required notices (docs/ARTWORK_DISCOVER.md section 5a), complete, one press away.
                LearnMoreLink(title: Attribution.aboutHeading, text: Attribution.catalogueNotice + "\n\n" + Attribution.whereToWatchNotice)
            }
        }
        .onChange(of: region) {
            let clean = OnlineLookupPrefs.normalizedRegion(region)
            if region.count == 2 && clean != region { region = clean }
            if region.count == 2 { services.online.rebuild() }
        }
    }
}

/// One key: shows it masked when saved, lets the user replace or remove it, or enter it when there is none.
private struct KeyRow: View {
    let kind: OnlineKeyKind
    let label: String
    let help: String
    @Environment(AppServices.self) private var services
    @State private var entry = ""
    @State private var message: String?
    @State private var working = false
    @State private var confirmRemove = false

    private var saved: String? {
        _ = services.online.keyRevision
        return services.online.keys.key(kind)
    }

    var body: some View {
        Section {
            if let saved {
                LabeledContent(label, value: OnlineKeyStore.masked(saved))
                Button("Remove Key", role: .destructive) { confirmRemove = true }
            }
            SecureField(saved == nil ? label : "Replace \(label)", text: $entry)
                .autocorrectionDisabled()
            Button("Save Key") { Task { await save() } }
                .disabled(entry.isEmpty || working)
        } footer: {
            // L3: the result of Save or Remove is footer text, not a row.
            Text(message.map { $0 + " " + help } ?? help)
        }
        .confirmationDialog("Remove \(label)?", isPresented: $confirmRemove) {
            Button("Remove Key", role: .destructive) { Task { await remove() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(OnlineLookupText.removeNote)
        }
    }

    private func save() async {
        working = true
        defer { working = false }
        do {
            try await services.online.saveKey(entry, for: kind)
            entry = ""
            message = "Key saved."
            services.libraryRevision += 1
        } catch {
            message = error.localizedDescription
        }
    }

    private func remove() async {
        do {
            try await services.online.removeKey(kind)
            message = "Key removed."
            services.libraryRevision += 1
        } catch {
            message = error.localizedDescription
        }
    }
}
