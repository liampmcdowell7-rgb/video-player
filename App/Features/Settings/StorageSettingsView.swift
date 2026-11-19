import SwiftUI
import AppLogic
import LibraryIndex

/// Says plainly where everything is kept and what a reset does. #15 3.6: the status sentences are plain text in the left
/// column (L3), not pills; the only control, Sync Now, sits in the bounded column.
struct StorageSettingsView: View {
    @Environment(AppServices.self) private var services
    @State private var counts: LibraryCounts?

    var body: some View {
        let status = StorageStatusModel(account: services.accountStatus, secrets: services.secretState, counts: counts,
                                        passwordsNeeded: services.passwordsNeeded, cloudUnavailable: services.cloudUnavailable)
        SettingsPane(title: "Storage and iCloud", summary: SettingsTexts.storageSummary,
                     status: [status.accountLine, status.passwordsLine, status.passwordsNeededLine ?? "", status.libraryLine ?? ""]) {
            Section("iCloud") {
                Button("Sync Now") { services.sync.syncNow() }
            } footer: {
                Text(services.sync.line)
            }
            Section("Passwords") {
                LearnMoreLink(title: "About Resetting", text: status.resetLine)
            }
        }
        .task(id: services.libraryRevision) {
            counts = try? await services.store.counts()
            await services.refreshCloudStatus()
        }
    }
}
