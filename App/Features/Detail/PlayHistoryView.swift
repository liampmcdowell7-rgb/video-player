import SwiftUI
import AppLogic
import UserData

/// R471 (20), PROVISIONAL: Play History in a cover. Each playback of the title, newest first: when it started (a row's
/// title) and how far it went (its value). Read-only; Clear Play History at the end asks first and removes the entries here
/// and on the user's other devices; the watch state stays. Layout: `SettingsPane`, system rows.
struct PlayHistoryView: View {
    let itemID: Int64
    let title: String
    @Environment(AppServices.self) private var services
    @State private var entries: [UDPlayRecord] = []
    @State private var itemKey: String?
    @State private var askClear = false

    var body: some View {
        SettingsPane(title: PlayHistoryText.title, summary: title, status: entries.isEmpty ? [PlayHistoryText.empty] : []) {
            if !entries.isEmpty {
                Section {
                    ForEach(entries, id: \.self) { entry in
                        LabeledContent(PlayHistoryText.started(entry), value: PlayHistoryText.progress(entry))
                    }
                } footer: {
                    Text(PlayHistoryText.summary)
                }
                Section {
                    Button(PlayHistoryText.clear, systemImage: "trash", role: .destructive) { askClear = true }
                }
            }
        }
        .task {
            itemKey = try? await services.sqlite.userDataKey(forItem: itemID)
            reload()
        }
        .confirmationDialog(PlayHistoryText.clearTitle, isPresented: $askClear, titleVisibility: .visible) {
            Button(PlayHistoryText.clear, role: .destructive) {
                if let itemKey { services.ledger.clearPlayHistory(itemKey: itemKey) }
                reload()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(PlayHistoryText.clearMessage)
        }
    }

    private func reload() {
        entries = itemKey.map { services.ledger.playHistory(itemKey: $0) } ?? []
    }
}
