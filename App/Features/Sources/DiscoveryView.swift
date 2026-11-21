import SwiftUI
import VideoPlayerCore
import AppLogic

/// Servers the system finds by itself. From Add a Source (every type) choosing one opens its form with the found values
/// filled in; from a type's form (R326, PROVISIONAL) only that type is listed and choosing one fills that form and goes back.
struct DiscoveryView: View {
    /// The form's type, or nil on Add a Source's page (every type the search finds).
    var kind: SourceKind? = nil
    /// Set when the page was opened from a form: the chosen server goes back to that form instead of opening a new one.
    var onPick: ((DiscoveredSource) -> Void)? = nil
    @State private var browser = BonjourBrowser()
    @Environment(\.dismiss) private var dismiss

    private var shown: [DiscoveredSource] { SourceDiscoveryText.shown(browser.found, kind: kind) }

    var body: some View {
        // #30 B: the shared full-screen task layout (TaskPage), as the list and the forms. R328 (PROVISIONAL): the found
        // servers are the section's rows; what the search is doing is the section footer, never a row with a spinner (L3).
        TaskPage(title: "Your Network") {
            Section {
                ForEach(shown, id: \.self) { (found: DiscoveredSource) in
                    if let onPick {
                        Button {
                            onPick(found)
                            dismiss()
                        } label: {
                            row(found)
                        }
                    } else {
                        NavigationLink(value: SetupRoute.discovered(found)) {
                            row(found)
                        }
                    }
                }
            } footer: {
                Text(SourceDiscoveryText.footer(kind: kind, foundAny: !shown.isEmpty))
            }
        }
        .onAppear { browser.start() }
        .onDisappear { browser.stop() }
    }

    /// #15 2.3 (R188), #30 E: the readable name on one line and the type on one line (S1). The machine identifier (21: a raw
    /// ID wrapped over three lines) is not on the row; the form shows it whole under Server Details.
    private func row(_ found: DiscoveredSource) -> some View {
        let kindTitle: String = SourceCatalog.info(for: found.kind).title
        let name = SourceSetupText.discoveredName(found.name, kindTitle: kindTitle)
        return VStack(alignment: .leading) {
            FittingText(name.title)
            FittingText(kindTitle, style: .caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
