import SwiftUI
struct V: View {
    var body: some View {
        Text("4K · Dolby Vision")
            .font(.caption)
            .lineLimit(1)
            // design-lint:allow rule S1 test fixture: shrinks to fit
            .minimumScaleFactor(0.8)
    }
}
