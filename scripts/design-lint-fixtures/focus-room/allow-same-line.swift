import SwiftUI
struct V: View {
    var body: some View {
        ScrollView { // design-lint:allow a long text with no focusable rows
            Text("Long text")
        }
    }
}
