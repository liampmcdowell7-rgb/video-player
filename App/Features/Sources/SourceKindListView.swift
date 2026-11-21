import SwiftUI
import AppLogic

/// Every source type. Types that cannot be set up say why and what to do instead (nothing is hidden).
///
/// #25 B1 (OPEN_QUESTIONS R202, PROVISIONAL): one column (`SheetColumn`): the title on top, then the rows. Each type is one
/// row with its name and ONE short line (`SourceSetupText.rowLine`); what was tested, what was not, and why a type is not
/// available yet are on "About Source Types" (Learn More), one press away. Fixed in code, verify in next screenshots (10, 20,
/// 93, 99, 110).
///
/// #30 D (OPEN_QUESTIONS R228): a full-screen `TaskPage`, so the list shows as many rows as the screen holds and scrolls
/// the rest under the system scroll edge effect; focus scrolls rows into view (system `Form`). In the sheet only three rows
/// showed and SFTP was cut in half (10).
struct SourceKindListView: View {
    var onCancel: () -> Void
    /// Built from this build's configuration: OneDrive stays blocked while no Microsoft app registration exists.
    private let kinds = SourceCatalog.catalog(oneDriveClientID: SourceConfiguration.oneDriveClientID)

    var body: some View {
        TaskPage(title: "Add a Source", summary: SourceSetupText.listSummary) {
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
                // #33 L (OPEN_QUESTIONS R238, PROVISIONAL): each row is a focusable link (as plain text the focus could not move
                // past them: the run of 20 Nov stopped on the last row (20)). R329 (PROVISIONAL): it opens that type's own
                // About page (why it is not available, what to use instead), no longer the one long text about every type.
                ForEach(kinds.filter { !$0.isAvailable }) { info in
                    NavigationLink {
                        SourceAboutPage(info: info)
                    } label: {
                        SourceKindRow(info: info)
                    }
                    .accessibilityIdentifier(ControlID.sourceKind(info.kind.rawValue))
                }
            }
            Section {
                // R329: About Source Types is a list of the types, each opening its About page (a hierarchy of lists).
                NavigationLink {
                    SourceTypesAboutView(kinds: kinds)
                } label: {
                    SlotLabel(SourceSetupText.learnMoreTitle, systemImage: "info.circle")
                }
                .accessibilityIdentifier(ControlID.learnMore)
                // #36 S-C (R255): a bezeled button, not a row; plain bordered (nothing on this page is the main action).
                TaskButtonRow {
                    TaskButton("Cancel", role: .cancel, action: onCancel)
                        .accessibilityIdentifier(ControlID.sourceCancel)
                }
            }
        }
    }
}
