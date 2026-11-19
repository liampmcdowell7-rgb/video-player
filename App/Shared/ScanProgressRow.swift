import SwiftUI
import AppLogic
import LibraryIndex

/// The running scan, with the one-time re-sort inside it (addendum #18 F), as a system ProgressView: folders done out of
/// folders known so far. Shows nothing when no scan runs. The total grows while new folders are found, so the bar can
/// step back; it never claims a time left.
struct ScanProgressRow: View {
    let progress: ScanProgress?

    var body: some View {
        if let progress {
            let total = progress.foldersDone + progress.foldersPending
            ProgressView(value: Double(progress.foldersDone), total: Double(max(total, 1))) {
                Text(SortTexts.scanningTitle)
            } currentValueLabel: {
                Text(SortTexts.scanningDetail(foldersDone: progress.foldersDone, total: total))
            }
        }
    }
}
