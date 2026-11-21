import SwiftUI
import VideoPlayerCore
import AppLogic

/// The add-a-source flow: pick a type (or search the network), fill in the form, connect.
///
/// #30 (OPEN_QUESTIONS R228, PROVISIONAL): shown as a FULL-SCREEN cover (`addSourceCover`), not a sheet. The run of 20 Nov
/// showed the sheet as a card about a third of the screen wide, with only 3 to 4 rows, the Home text showing through and
/// the tab bar above it (10, 11, 17, 94). HIG Modality: a full-screen modal style suits "a multistep task", and in tvOS
/// "people expect to find a button in the main content view" to dismiss it (the Cancel rows). A full-screen cover hides
/// the tab bar and the page that opened it. scripts/design-lint.sh rule `form-sheet` fails if this flow or one of its
/// forms is presented with `.sheet` again.
struct SourceSetupFlow: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SourceKindListView(onCancel: { dismiss() })
                .navigationDestination(for: SetupRoute.self) { route in
                    switch route {
                    case .form(.plex):
                        // R302: Plex signs in with a code on another device instead of a form.
                        PlexSetupView(onFinished: { dismiss() })
                    case .form(let kind):
                        SourceFormView(draft: SourceDraft(kind: kind), onFinished: { dismiss() })
                    case .discovery:
                        DiscoveryView()
                    case .discovered(let found):
                        SourceFormView(draft: SourceDraft(discovered: found), serverID: Self.identifier(of: found), onFinished: { dismiss() })
                    }
                }
        }
    }

    /// #30 item 3: the machine identifier in a found server's advertised name (nil when it has none), shown whole in the form.
    static func identifier(of found: DiscoveredSource) -> String? {
        let kindTitle: String = SourceCatalog.info(for: found.kind).title
        return SourceSetupText.discoveredName(found.name, kindTitle: kindTitle).identifier
    }
}

extension View {
    /// #30: the one way to open Add a Source, from Home, Movies, Shows, Files and Settings > Sources: full screen.
    func addSourceCover(isPresented: Binding<Bool>) -> some View {
        taskCover(isPresented: isPresented) { SourceSetupFlow() }
    }
}
