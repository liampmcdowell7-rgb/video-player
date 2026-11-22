import SwiftUI
import AppLogic
import LibraryIndex

/// Settings > Library. #15 3.2: bounded column (`SettingsPane`); the counts stay `LabeledContent` in that column.
struct LibrarySettingsView: View {
    @Environment(AppServices.self) private var services
    @AppStorage(SettingsKey.scanOnLaunch.rawValue) private var scanOnLaunch = true
    @AppStorage(SettingsKey.showTitleLogos.rawValue) private var showTitleLogos = true
    @State private var counts: LibraryCounts?
    @State private var reviewCount: Int?

    var body: some View {
        SettingsPane(title: "Library", summary: SettingsTexts.librarySummary) {
            Section {
                SettingToggle("Scan Sources When the App Opens", isOn: $scanOnLaunch)
                // #36 S-C (R255): the page's main action, a prominent bezeled button, label centred, not a row.
                TaskButtonRow {
                    TaskButton(services.isScanning ? "Scanning" : "Scan Now", prominent: true) {
                        Task { await services.scanAll() }
                    }
                    .disabled(services.isScanning)
                }
                ScanProgressRow(progress: services.scanProgress)
            }
            // #15 3.2 and 9.4: title logos on the movie and show pages (on by default).
            Section {
                SettingToggle("Show Title Logos", isOn: $showTitleLogos)
            } footer: {
                Text(SettingsTexts.titleLogosFooter)
            }
            // docs/SORTING.md: files that are neither a clear movie nor a clear episode wait here, never in Movies or Shows.
            Section {
                NavigationLink {
                    NeedsReviewView().screenIdentifier("screen.needsReview")
                } label: {
                    ValueRow("Needs Review", value: reviewCount.map(String.init) ?? "")
                }
            }
            if let counts {
                // R389: the last section holds no control, so each count takes the focus (`readableRow`): before, the
                // focus stopped at Needs Review and the counts below it could stay out of reach.
                Section("In Your Library") {
                    ValueRow("Titles", value: String(counts.items)).readableRow()
                    ValueRow("Shows", value: String(counts.series)).readableRow()
                    ValueRow("Files", value: String(counts.files)).readableRow()
                        .accessibilityIdentifier(SettingsRowID.last)
                }
            }
        }
        .task(id: services.libraryRevision) {
            counts = try? await services.store.counts()
            reviewCount = try? await services.store.needsReviewCount()
        }
    }
}
