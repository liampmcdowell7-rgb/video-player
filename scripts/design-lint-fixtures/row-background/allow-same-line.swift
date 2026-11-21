import SwiftUI
struct V: View {
    var body: some View {
        Form {
            Text("Row")

        }
        .scrollClipDisabled()
        .listRowBackground(Color.clear) // design-lint:allow fixture: documented exception
    }
}
