import SwiftUI
struct V: View { @State private var on = false
    // design-lint:allow fixture: documented exception on the line above
    var body: some View { Button("x") { withAnimation { on.toggle() } } } }
