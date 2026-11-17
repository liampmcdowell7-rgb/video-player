import SwiftUI
struct V: View { @State private var on = false; var body: some View { Button("x") { withAnimation { on.toggle() } } } } // design-lint:allow fixture: documented exception
