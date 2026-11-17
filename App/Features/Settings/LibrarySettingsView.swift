import SwiftUI
import AppLogic
import LibraryIndex

struct LibrarySettingsView: View {
    @Environment(AppServices.self) private var services
    @AppStorage(SettingsKey.scanOnLaunch.rawValue) private var scanOnLaunch = true
    @State private var counts: LibraryCounts?

    var body: some View {
        Form {
            Section {
                Toggle("Scan Sources When the App Opens", isOn: $scanOnLaunch)
                Button(services.isScanning ? "Scanning" : "Scan Now", systemImage: "arrow.clockwise") {
                    Task { await services.scanAll() }
                }
                .disabled(services.isScanning)
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
        .task(id: services.libraryRevision) { counts = try? await services.store.counts() }
    }
}
