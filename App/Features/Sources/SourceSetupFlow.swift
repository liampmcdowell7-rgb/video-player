import SwiftUI
import VideoPlayerCore
import AppLogic

/// The add-a-source flow: pick a type (or search the network), fill in the form, connect. Shown as a sheet.
struct SourceSetupFlow: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SourceKindListView(onCancel: { dismiss() })
                .navigationDestination(for: SetupRoute.self) { route in
                    switch route {
                    case .form(let kind):
                        SourceFormView(draft: SourceDraft(kind: kind), onFinished: { dismiss() })
                    case .discovery:
                        DiscoveryView()
                    case .discovered(let found):
                        SourceFormView(draft: SourceDraft(discovered: found), onFinished: { dismiss() })
                    }
                }
        }
    }
}
