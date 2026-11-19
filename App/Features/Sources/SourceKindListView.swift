import SwiftUI
import AppLogic

/// Every source type. Types that cannot be set up say why and what to do instead (nothing is hidden).
///
/// #15 2.1 (OPEN_QUESTIONS R188, PROVISIONAL): the rows sit in the system `Form` of `SettingsPane`, which scrolls with the
/// system edge effect instead of a fixed-height card that cut off "NFS"; the section headers are the system's; the rows keep
/// the Form's side insets, so they no longer touch the sheet's edges. Fixed in code, verify in next screenshots (10, 20, 21).
struct SourceKindListView: View {
    var onCancel: () -> Void
    /// Built from this build's configuration: OneDrive stays blocked while no Microsoft app registration exists.
    private let kinds = SourceCatalog.catalog(oneDriveClientID: SourceConfiguration.oneDriveClientID)

    var body: some View {
        SettingsPane(title: "Add a Source", summary: SourceSetupText.listSummary) {
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
    }
}
