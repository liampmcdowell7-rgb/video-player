import SwiftUI
import AppLogic
import LibraryIndex

/// Says plainly where everything is kept and what a reset does.
struct StorageSettingsView: View {
    @Environment(AppServices.self) private var services
    @State private var counts: LibraryCounts?

    var body: some View {
        let status = StorageStatusModel(account: services.accountStatus, secrets: services.secretState, counts: counts,
                                        passwordsNeeded: services.passwordsNeeded, cloudUnavailable: services.cloudUnavailable)
        Form {
            Section("iCloud") {
                Text(status.accountLine)
                Text(services.sync.line)
                Button("Sync Now") { services.sync.syncNow() }
            }
            Section("Passwords") {
                Text(status.passwordsLine)
                if let needed = status.passwordsNeededLine {
                    Text(needed)
                }
                Text(status.resetLine)
                    .foregroundStyle(.secondary)
            }
            if let line = status.libraryLine {
                Section("Library Index") {
                    Text(line)
                }
            }
        }
        .pushedScreen("Storage and iCloud")
        .task(id: services.libraryRevision) {
            counts = try? await services.store.counts()
            await services.refreshCloudStatus()
        }
    }
}
