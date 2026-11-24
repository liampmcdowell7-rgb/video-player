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
