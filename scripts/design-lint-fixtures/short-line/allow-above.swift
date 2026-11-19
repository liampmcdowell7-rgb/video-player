import SwiftUI
struct V: View {
    var body: some View {
        Text("Row")
            // design-lint:allow fixture: documented exception
            .lineLimit(1)
    }
}
