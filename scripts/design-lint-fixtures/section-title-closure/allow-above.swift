import SwiftUI
struct V: View {
    var body: some View {
        Form {
            // design-lint:allow fixture: an allowed instance
            Section("Storage") { Text("a") } footer: { Text("b") }
        }
    }
}
