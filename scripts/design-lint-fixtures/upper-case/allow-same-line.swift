import SwiftUI
struct V: View {
    var body: some View {
        Form {
            Text("Row")

        }
        .scrollClipDisabled()
        .textCase(.uppercase) // design-lint:allow fixture: documented exception
    }
}
