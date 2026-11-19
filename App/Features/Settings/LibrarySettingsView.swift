import SwiftUI
import AppLogic
import LibraryIndex

struct LibrarySettingsView: View {
    @Environment(AppServices.self) private var services
    @AppStorage(SettingsKey.scanOnLaunch.rawValue) private var scanOnLaunch = true
    @State private var counts: LibraryCounts?
    @State private var reviewCount: Int?

    var body: some View {
        Form {
            Section {
                Toggle("Scan Sources When the App Opens", isOn: $scanOnLaunch)
                Button(services.isScanning ? "Scanning" : "Scan Now", systemImage: "arrow.clockwise") {
                    Task { await services.scanAll() }
                }
                .disabled(services.isScanning)
            }
            // docs/SORTING.md: files that are neither a clear movie nor a clear episode wait here, never in Movies or Shows.
            Section {
                NavigationLink {
                    NeedsReviewView()
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
        .navigationTitle("Library")
        .task(id: services.libraryRevision) {
            counts = try? await services.store.counts()
            reviewCount = try? await services.store.needsReviewCount()
        }
    }
}
