import SwiftUI
import UserData
import LibraryBackup

/// "Restoring your library from iCloud", with the progress the engine reports (shown over the tabs while it runs).
struct RestoreBanner: View {
    let status: BackupStatus

    var body: some View {
        if case .restoring(let progress) = status {
            ProgressView(BackupStatusText.restoringBanner, value: progress.fraction)
        } else {
            ProgressView(BackupStatusText.restoringBanner)
        }
    }
}

/// Settings > Backup: the iCloud backup of what the app built from the user's videos (docs/BACKUP.md). Says what is
/// included, what never is, how much iCloud storage it uses, when it last finished and what went wrong.
struct BackupSettingsView: View {
    @Environment(AppServices.self) private var services
    @State private var confirmRestore = false

    var body: some View {
        @Bindable var backup = services.backup
        // #15 3.9 and #17 D: bounded column (`SettingsPane`); one summary sentence and a short "what" line; the complete
        // text (intro, storage note, what each part holds, never included) on "About Backup" (L5); status as text (L3).
        SettingsPane(title: "Backup", summary: BackupStatusText.summary,
                     status: [statusLine(backup) ?? "", backup.skippedLine ?? ""]) {
            Section {
                SettingToggle("Library Data", isOn: $backup.settings.library)
                SettingToggle("Artwork", isOn: $backup.settings.artwork)
                ValueRow("Artwork in iCloud", value: BackupStatusText.size(backup.usage[.artwork] ?? 0))
                if backup.settings.artwork {
                    SettingToggle("Only Artwork for Items in Your Library", isOn: $backup.settings.artworkLibraryOnly)
                }
                // R449: the pictures the user chose have their own switch; their text edits are user data like the next row.
                SettingToggle("Edits and Artwork", isOn: $backup.settings.edits)
                ValueRow("Edits and Artwork in iCloud", value: BackupStatusText.size(backup.usage[.userArtwork] ?? 0))
                ValueRow("Playback Data", value: "iCloud Sync")
                ValueRow("Settings and Watch State", value: "iCloud Sync")
                LearnMoreLink(title: BackupStatusText.learnMoreTitle, text: BackupStatusText.learnMore)
            } header: {
                Text("What Is Backed Up")
            } footer: {
                Text(BackupStatusText.whatShort + " " + BackupStatusText.settingsNote)
            }

            Section("iCloud") {
                ValueRow("Size in iCloud", value: BackupStatusText.size(backup.totalSize))
                ValueRow("Last Backup", value: backup.lastSuccess.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                // #36 S-C (R255): the page's main action, prominent. Restore from iCloud below is not in #36's list and
                // stays a row (not changed: rule "do not extend any fix to a screen not named").
                TaskButtonRow {
                    TaskButton("Back Up Now", prominent: true) { backup.backUpNow() }
                        .disabled(backup.isWorking || backup.unavailableReason != nil || !(backup.settings.library || backup.settings.artwork || backup.settings.edits))
                }
                Button("Restore from iCloud", role: .destructive) { confirmRestore = true }
                    .disabled(backup.isWorking || backup.unavailableReason != nil)
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
        .task {
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
