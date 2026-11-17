import SwiftUI

/// Shown while the library is being scanned or rebuilt. The text says what is happening and that nothing is lost.
struct RebuildingBanner: View {
    var body: some View {
        HStack {
            ProgressView()
            Text("Rebuilding your library. Your watch history is not affected.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
