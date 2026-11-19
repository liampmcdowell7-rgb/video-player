import SwiftUI
struct V: View {
    var body: some View {
        Form {
            Section("Storage") { Text("a") } footer: { Text("b") } // design-lint:allow fixture: an allowed instance
        }
    }
}
