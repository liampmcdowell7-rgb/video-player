import SwiftUI
struct V: View {
    var body: some View {
        Form {
            Text("Row")

        }
        .scrollClipDisabled()
        .presentationDetents([.medium]) // design-lint:allow fixture: documented exception
    }
}
