import SwiftUI
struct V: View {
    var body: some View {
        Button("Open") { }
            .contextMenu { Button("Delete", role: .destructive) { } }
    }
}
