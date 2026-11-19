import SwiftUI
struct V: View {
    var body: some View {
        Form {
            Section("Rows") {
                Toggle("Next Up", isOn: .constant(true))
            }
            Section {
                Button("Sync Now") { }
            } header: {
                Text("Storage")
            } footer: {
                Text("Section(\"x\") { } footer: in a string is not code")
            }
            Section(isExpanded: .constant(true)) { Text("a") } header: { Text("b") }
        }
    }
}
