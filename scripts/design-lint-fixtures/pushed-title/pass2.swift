import SwiftUI
struct V: View {
    var body: some View {
        Form {
            Text("Row")
        }
        .scrollClipDisabled()
        .navigationTitle("Playback")
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
}
