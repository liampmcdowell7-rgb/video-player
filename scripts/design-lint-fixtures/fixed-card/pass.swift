import SwiftUI
struct V: View {
    var body: some View {
        List {
            Text("Types")
        }
        .scrollClipDisabled()
        .frame(maxHeight: .infinity)
    }
}
