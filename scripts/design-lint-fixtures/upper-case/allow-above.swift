import SwiftUI
struct V: View {
    var body: some View {
        Form {
            Text("Row")

        }
        .scrollClipDisabled()
        // design-lint:allow fixture: documented exception
        .textCase(.uppercase)
    }
}
