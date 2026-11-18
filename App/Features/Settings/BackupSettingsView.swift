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
        Form {
            Section {
                Text(BackupStatusText.intro)
            } footer: {
                Text(BackupStatusText.storageNote)
            }

            Section {
                Toggle("Library Data", isOn: $backup.settings.library)
                Text(BackupStatusText.libraryDetail)
                    .foregroundStyle(.secondary)
                Toggle("Artwork", isOn: $backup.settings.artwork)
                LabeledContent("Artwork in iCloud", value: BackupStatusText.size(backup.usage[.artwork] ?? 0))
                Text(BackupStatusText.artworkDetail)
                    .foregroundStyle(.secondary)
                if backup.settings.artwork {
                    Toggle("Only Artwork for Items in Your Library", isOn: $backup.settings.artworkLibraryOnly)
                }
                LabeledContent("Settings and Watch State", value: "Kept by iCloud Sync")
                Text(BackupStatusText.userDataDetail)
                    .foregroundStyle(.secondary)
            } header: {
                Text("What Is Backed Up")
            } footer: {
                Text(BackupStatusText.neverIncluded)
            }

            Section("iCloud") {
                LabeledContent("Size in iCloud", value: BackupStatusText.size(backup.totalSize))
                LabeledContent("Last Backup", value: backup.lastSuccess.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                if let line = statusLine(backup) {
                    Text(line)
                }
                if let skipped = backup.skippedLine {
                    Text(skipped)
                        .foregroundStyle(.secondary)
                }
                Button("Back Up Now") { backup.backUpNow() }
                    .disabled(backup.isWorking || backup.unavailableReason != nil || !(backup.settings.library || backup.settings.artwork))
                Button("Restore from iCloud", role: .destructive) { confirmRestore = true }
                    .disabled(backup.isWorking || backup.unavailableReason != nil)
            }
        }
        .navigationTitle("Backup")
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
