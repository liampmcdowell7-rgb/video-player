import SwiftUI

/// The standard spinner, centred. No skeletons (docs/DESIGN_SYSTEM.md, row "Loading").
struct LoadingView: View {
    var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
