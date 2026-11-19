import SwiftUI
struct V: View {
    var body: some View {
        Form {
            Section("Storage") {
                Button("Sync Now") { }
            } footer: {
                Text("Last synced")
            }
        }
    }
}
