import SwiftUI
struct V: View {
    @State private var showSetup = false
    var body: some View {
        Text("Home")
            // design-lint:allow fixture: documented exception
            .sheet(isPresented: $showSetup) { SourceSetupFlow() }
    }
}
