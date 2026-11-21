import SwiftUI
struct V: View {
    var body: some View {
        // design-lint:allow a long text with no focusable rows
        ScrollView {
            Text("Long text")
        }
    }
}
