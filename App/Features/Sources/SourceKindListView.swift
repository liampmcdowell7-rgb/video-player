import SwiftUI
import AppLogic

/// Every source type. Types that cannot be set up say why and what to do instead (nothing is hidden).
struct SourceKindListView: View {
    var onCancel: () -> Void
    /// Built from this build's configuration: OneDrive stays blocked while no Microsoft app registration exists.
    private let kinds = SourceCatalog.catalog(oneDriveClientID: SourceConfiguration.oneDriveClientID)

    var body: some View {
        List {
            Section("Find on Your Network") {
                NavigationLink(value: SetupRoute.discovery) {
                    RowLabel("Search Your Network", systemImage: "wifi")
                }
            }
            Section("Type an Address") {
                ForEach(kinds.filter(\.isAvailable)) { info in
                    NavigationLink(value: SetupRoute.form(info.kind)) {
                        SourceKindRow(info: info)
                    }
                }
            }
            Section("Not Available Yet") {
                ForEach(kinds.filter { !$0.isAvailable }) { info in
                    SourceKindRow(info: info)
                }
            }
            Section {
                Button("Cancel", role: .cancel, action: onCancel)
            }
        }
        .navigationTitle("Add a Source") // design-lint:allow sheet root: the title is the sheet's own heading, not a pushed page (rule D1 is for pushed pages)
    }
}
