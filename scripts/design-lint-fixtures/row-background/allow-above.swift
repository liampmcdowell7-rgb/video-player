import SwiftUI
struct V: View {
    var body: some View {
        Form {
            Text("Row")

        }
        // design-lint:allow fixture: documented exception
        .listRowBackground(Color.clear)
    }
}
