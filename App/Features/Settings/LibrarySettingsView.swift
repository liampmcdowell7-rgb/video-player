import SwiftUI
import AppLogic
import LibraryIndex

/// Settings > Library. #15 3.2: bounded column (`SettingsPane`); the counts stay `LabeledContent` in that column.
struct LibrarySettingsView: View {
    @Environment(AppServices.self) private var services
    @AppStorage(SettingsKey.scanOnLaunch.rawValue) private var scanOnLaunch = true
    @State private var counts: LibraryCounts?
    @State private var reviewCount: Int?

    var body: some View {
        SettingsPane(title: "Library", summary: SettingsTexts.librarySummary) {
            Section {
                Toggle("Scan Sources When the App Opens", isOn: $scanOnLaunch)
                Button {
                    Task { await services.scanAll() }
                } label: {
                    RowLabel(services.isScanning ? "Scanning" : "Scan Now", systemImage: "arrow.clockwise")
                }
                .disabled(services.isScanning)
                ScanProgressRow(progress: services.scanProgress)
            }
            // docs/SORTING.md: files that are neither a clear movie nor a clear episode wait here, never in Movies or Shows.
            Section {
                NavigationLink {
                    NeedsReviewView().screenIdentifier("screen.needsReview")
                } label: {
                    LabeledContent("Needs Review", value: reviewCount.map(String.init) ?? "")
                }
            }
            if let counts {
                Section("In Your Library") {
                    LabeledContent("Titles", value: String(counts.items))
                    LabeledContent("Shows", value: String(counts.series))
                    LabeledContent("Files", value: String(counts.files))
                }
            }
        }
        .task(id: services.libraryRevision) {
            counts = try? await services.store.counts()
            reviewCount = try? await services.store.needsReviewCount()
        }
    }
}
