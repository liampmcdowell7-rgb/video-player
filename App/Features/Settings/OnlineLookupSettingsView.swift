import SwiftUI
import AppLogic

/// Settings > Online Lookup (#26 item 3): the ONLY place to enter, change or remove a key. One key per service, entered once,
/// covers the whole app: every source, every library, Discover, pictures and details. Adding a source never asks for a key.
/// States plainly what is sent and where; nothing is sent until a key is entered or Free Data Sources is turned on (D10).
/// There is no "test key" button: a key is checked the first time it is used, and a rejected key is reported on the screen
/// that used it (PROVISIONAL; alternative: a button that makes one request on an explicit press).
///
/// Layout: one row per keyed service, the name as text only with its status (On / Not set) and one short footer line; the key
/// is shown masked as text (never in a picture); a native `SecureField` takes the key, so the system text entry (and any
/// keyboard the system offers) is used. Key-free sources have no key row: they are one switch, Free Data Sources.
struct OnlineLookupSettingsView: View {
    @Environment(AppServices.self) private var services
    @AppStorage(OnlineLookupPrefs.regionKey) private var region = OnlineLookupPrefs.defaultRegion
    @AppStorage(OnlineLookupPrefs.freeSourcesKey) private var freeSources = OnlineLookupPrefs.freeSourcesDefault

    var body: some View {
        SettingsPane(title: OnlineLookupText.settingsTitle, summary: SettingsTexts.onlineSummary,
                     status: [OnlineLookupText.status(hasTMDB: services.online.hasCatalogueKey),
                              OnlineLookupText.freeSourcesStatus(freeSources)]) {
            Section {
                LearnMoreLink(title: SettingsTexts.whatIsSentTitle, text: OnlineLookupText.whatIsSent)
            } footer: {
                Text(SettingsTexts.whatIsSentShort)
            }
            KeyRow(kind: .tmdb, label: OnlineLookupText.tmdbLabel, help: OnlineLookupText.tmdbHelp)
            Section {
                LearnMoreLink(title: OnlineLookupText.getTMDBKeyTitle, text: OnlineLookupText.getTMDBKeySteps)
            }
            Section {
                SettingToggle(OnlineLookupText.freeSourcesLabel, isOn: $freeSources)
                    .accessibilityIdentifier(ControlID.freeDataSources)
                LearnMoreLink(title: OnlineLookupText.freeSourcesTitle, text: OnlineLookupText.freeSourcesAbout)
            } footer: {
                Text(OnlineLookupText.freeSourcesFooter)
            }
            Section {
                TextField(OnlineLookupText.regionLabel, text: $region)
                    .autocorrectionDisabled()
            } footer: {
                Text(OnlineLookupText.regionHelp)
            }
            Section {
                LearnMoreLink(title: SettingsTexts.aboutKeysTitle, text: SettingsTexts.aboutKeysFull)
            }
            // #26 item 7: the data providers' notices and the TMDB logo are only in Settings > About > Data Sources.
        }
        .onChange(of: region) {
            let clean = OnlineLookupPrefs.normalizedRegion(region)
            if region.count == 2 && clean != region { region = clean }
            if region.count == 2 { services.online.rebuild() }
        }
        .onChange(of: freeSources) { services.online.rebuild() }
    }
}

/// One keyed service: its name and status, the key masked when saved, Remove Key, and the native secure entry.
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
            ValueRow(label, value: saved == nil ? OnlineLookupText.keyNotSet : OnlineLookupText.keyOn)
                .accessibilityIdentifier(ControlID.keyRow(kind.rawValue))
            if let saved {
                // Masked as text, never the whole key (OnlineKeyStore.masked: dots and the last four characters).
                ValueRow("Key", value: OnlineKeyStore.masked(saved))
                    .accessibilityIdentifier(ControlID.keyValue(kind.rawValue))
                // #36 S-C (R255): bezeled, not a row.
                TaskButtonRow {
                    TaskButton("Remove Key", role: .destructive) { confirmRemove = true }
                }
            }
            SecureField(saved == nil ? OnlineLookupText.enterKey : OnlineLookupText.replaceKey, text: $entry)
                .autocorrectionDisabled()
            TaskButtonRow {
                TaskButton("Save Key", prominent: true) { Task { await save() } }
                    .disabled(entry.isEmpty || working)
            }
        } footer: {
            // L3: the result of Save or Remove is footer text, not a row.
            Text(message.map { $0 + " " + help } ?? help)
        }
        .confirmationDialog("Remove the \(label) key?", isPresented: $confirmRemove) {
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
            // The error text never contains the key (OnlineKeyError descriptions are fixed sentences).
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
