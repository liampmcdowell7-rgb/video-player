import SwiftUI
import AppLogic

/// Settings > Sync and Backup (R456, PROVISIONAL): the two existing pages under one row of the top level. The pages and their
/// rows are unchanged (Storage and iCloud: sync status and Sync Now; Backup: auto backup, Save Backup Now, Restore, sizes).
struct SyncAndBackupSettingsView: View {
    var body: some View {
        SettingsPane(title: "Sync and Backup", summary: "Your sources, edits, settings and watch state sync through iCloud. Backups hold the library.") {
            Section {
                NavigationLink { StorageSettingsView() } label: { RowLabel("Storage and iCloud", systemImage: "icloud") }
                NavigationLink { BackupSettingsView() } label: { RowLabel("Backup", systemImage: "arrow.clockwise.icloud") }
            } footer: {
                Text("Passwords are never synced or backed up.")
            }
        }
    }
}
