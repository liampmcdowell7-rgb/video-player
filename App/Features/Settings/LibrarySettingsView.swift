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
    @State private var episodeCount: Int?
    @State private var confirmRefresh = false
    @State private var refreshed = false

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
                ValueRow("Last Scan", value: LastScan.text((UserDefaults.standard.object(forKey: LastScan.key) as? Double).map { Date(timeIntervalSince1970: $0) }))
                    .readableRow()
            }
            // R458: the online answers kept for titles are fetched again; edits and choices of the person stay.
            Section {
                TaskButtonRow {
                    TaskButton(refreshed ? "Refreshed" : "Refresh Metadata") { confirmRefresh = true }
                        .disabled(!services.online.hasCatalogueKey)
                }
            } footer: {
                Text(services.online.hasCatalogueKey ? MetadataRefresh.message : MetadataRefresh.needsKeyLine)
            }
            // #15 3.2 and 9.4: title logos on the movie and show pages (on by default).
            Section {
                SettingToggle("Show Title Logos", isOn: $showTitleLogos)
            } footer: {
                Text(SettingsTexts.titleLogosFooter)
            }
            // docs/SORTING.md: files that are neither a clear movie nor a clear episode wait here, never in Movies or Shows.
            // R459: Needs Review lists files by name, which the rating rule does not cover: it is left out while Restrictions are on.
            if !services.restrictionsOn {
                Section {
                    NavigationLink {
                        NeedsReviewView().screenIdentifier("screen.needsReview")
                    } label: {
                        ValueRow("Needs Review", value: reviewCount.map(String.init) ?? "")
                    }
                }
            }
            if let counts {
                // R389: the last section holds no control, so each count takes the focus (`readableRow`): before, the
                // focus stopped at Needs Review and the counts below it could stay out of reach.
                Section("In Your Library") {
                    ValueRow("Titles", value: String(counts.items)).readableRow()
                    ValueRow("Shows", value: String(counts.series)).readableRow()
                    ValueRow("Episodes", value: episodeCount.map(String.init) ?? "").readableRow()
                    ValueRow("Files", value: String(counts.files)).readableRow()
                        .accessibilityIdentifier(SettingsRowID.last)
                }
            }
        }
        .task(id: services.libraryRevision) {
            counts = try? await services.store.counts()
            reviewCount = try? await services.store.needsReviewCount()
            var episodes = ItemFilter()
            episodes.kinds = [.episode]
            episodeCount = try? await services.store.count(ItemQuery(filter: episodes))
        }
        .confirmationDialog(MetadataRefresh.confirmTitle, isPresented: $confirmRefresh, titleVisibility: .visible) {
            Button("Refresh All Sources") {
                Task { await services.refreshMetadata(sourceID: nil); refreshed = true }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(MetadataRefresh.message)
        }
    }
}
