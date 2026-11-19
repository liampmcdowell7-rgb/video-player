import SwiftUI
struct V: View {
    let title: String
    var body: some View {
        Form {
            Section(title) { Text("a") } header: { Text("b") }
        }
    }
}
