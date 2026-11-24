import SwiftUI
import UserData
import LibraryBackup
import LibraryIndex
import AppLogic

/// Settings > Sync and Backup (R457, PROVISIONAL): ONE page for what used to be two (R456's hub of Storage and iCloud and
/// Backup). The iCloud sync status and Sync Now, what is backed up, the sizes, the last backup, Back Up Now and Restore from
/// iCloud. Flat rows, one short line under each section. The texts of the old pages are kept (docs/BACKUP.md).
struct SyncAndBackupSettingsView: View {
    @Environment(AppServices.self) private var services
    @State private var counts: LibraryCounts?
    @State private var confirmRestore = false

    var body: some View {
        @Bindable var backup = services.backup
        let status = StorageStatusModel(account: services.accountStatus, secrets: services.secretState, counts: counts,
                                        passwordsNeeded: services.passwordsNeeded, cloudUnavailable: services.cloudUnavailable)
        SettingsPane(title: "Sync and Backup", summary: SyncAndBackupText.summary,
                     status: [status.accountLine, status.passwordsNeededLine ?? "", status.libraryLine ?? "", statusLine(backup) ?? "", backup.skippedLine ?? ""]) {
            Section {
                // #33 J: while sync is off the button is disabled and the footer says why. #36 S-C (R255): a prominent button.
                TaskButtonRow {
                    TaskButton("Sync Now", prominent: true) { services.sync.syncNow() }
                        .disabled(services.sync.unavailableReason != nil)
                }
            } header: {
                Text("iCloud")
            } footer: {
                Text(services.sync.line)
            }

            Section {
                SettingToggle("Library Data", isOn: $backup.settings.library)
                SettingToggle("Artwork", isOn: $backup.settings.artwork)
                if backup.settings.artwork {
                    SettingToggle("Only Artwork for Items in Your Library", isOn: $backup.settings.artworkLibraryOnly)
                }
                // R449: the pictures the user chose have their own switch; their text edits are user data like the next row.
                SettingToggle("Edits and Artwork", isOn: $backup.settings.edits)
                ValueRow("Playback Data", value: "iCloud Sync")
                ValueRow("Settings and Watch State", value: "iCloud Sync")
                LearnMoreLink(title: BackupStatusText.learnMoreTitle, text: BackupStatusText.learnMore)
            } header: {
                Text("What Is Backed Up")
            } footer: {
                Text(SyncAndBackupText.settingsFooter)
            }

            Section {
                ValueRow("Size in iCloud", value: BackupStatusText.size(backup.totalSize))
                ValueRow("Artwork in iCloud", value: BackupStatusText.size(backup.usage[.artwork] ?? 0))
                ValueRow("Edits and Artwork in iCloud", value: BackupStatusText.size(backup.usage[.userArtwork] ?? 0))
                ValueRow("Last Backup", value: backup.lastSuccess.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                // #36 S-C (R255): the page's main action, prominent.
                TaskButtonRow {
                    TaskButton("Back Up Now", prominent: true) { backup.backUpNow() }
                        .disabled(backup.isWorking || backup.unavailableReason != nil || !(backup.settings.library || backup.settings.artwork || backup.settings.edits))
                }
                Button("Restore from iCloud", role: .destructive) { confirmRestore = true }
                    .disabled(backup.isWorking || backup.unavailableReason != nil)
            } header: {
                Text("Backup")
            } footer: {
                Text(BackupStatusText.whatShort)
            }

            Section("Passwords") {
                LearnMoreLink(title: "About Resetting", text: status.resetLine)
            }
        }
        .confirmationDialog("Restore from iCloud?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore", role: .destructive) {
                backup.restoreNow(afterLibrary: { await services.reapplyUserData() })
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(BackupStatusText.restoreConfirmation)
        }
        .task(id: services.libraryRevision) {
            counts = try? await services.store.counts()
            await services.refreshCloudStatus()
            await backup.refreshUsage()
        }
    }

    /// Signed out first (from the account check), then the backup's own state, then the last problem.
    private func statusLine(_ backup: BackupHost) -> String? {
        // iCloud cannot be used at all by this copy of the app (no iCloud capability): say so, never "signed out".
        if let reason = backup.unavailableReason { return reason }
        switch services.accountStatus {
        case .noAccount, .restricted: return BackupStatusText.line(.signedOut)
        default: break
        }
        let line = BackupStatusText.line(backup.status)
        if !line.isEmpty { return line }
        return backup.lastProblem
    }
}
