import SwiftUI
import AppLogic

/// Every source type. Types that cannot be set up say why and what to do instead (nothing is hidden).
///
/// #25 B1 (OPEN_QUESTIONS R202, PROVISIONAL): one column (`SheetColumn`): the title on top, then the rows. Each type is one
/// row with its name and ONE short line (`SourceSetupText.rowLine`); what was tested, what was not, and why a type is not
/// available yet are on "About Source Types" (Learn More), one press away. Fixed in code, verify in next screenshots (10, 20,
/// 93, 99, 110).
struct SourceKindListView: View {
    var onCancel: () -> Void
    /// Built from this build's configuration: OneDrive stays blocked while no Microsoft app registration exists.
    private let kinds = SourceCatalog.catalog(oneDriveClientID: SourceConfiguration.oneDriveClientID)

    var body: some View {
        SheetColumn(title: "Add a Source", summary: SourceSetupText.listSummary) {
            Section("Find on Your Network") {
                NavigationLink(value: SetupRoute.discovery) {
                    RowLabel("Search Your Network", systemImage: "wifi")
                }
                .accessibilityIdentifier(ControlID.searchYourNetwork)
            }
            Section("Type an Address") {
                ForEach(kinds.filter(\.isAvailable)) { info in
                    NavigationLink(value: SetupRoute.form(info.kind)) {
                        SourceKindRow(info: info)
                    }
                    .accessibilityIdentifier(ControlID.sourceKind(info.kind.rawValue))
                }
            }
            Section("Not Available Yet") {
                ForEach(kinds.filter { !$0.isAvailable }) { info in
                    SourceKindRow(info: info)
                        .accessibilityIdentifier(ControlID.sourceKind(info.kind.rawValue))
                }
            }
            Section {
                LearnMoreLink(title: SourceSetupText.learnMoreTitle, text: SourceSetupText.learnMore(kinds))
                    .accessibilityIdentifier(ControlID.learnMore)
                Button("Cancel", role: .cancel, action: onCancel)
                    .accessibilityIdentifier(ControlID.sourceCancel)
            }
        }
    }
}
