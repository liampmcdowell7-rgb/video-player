import SwiftUI
struct V: View {
    var body: some View {
        ScrollView {
            Text("Row")
        }
        .scrollClipDisabled()
        .clipped()
    }
}
