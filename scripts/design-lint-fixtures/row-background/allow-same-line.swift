import SwiftUI
struct V: View {
    var body: some View {
        Form {
            Text("Row")

        }
        .listRowBackground(Color.clear) // design-lint:allow fixture: documented exception
    }
}
