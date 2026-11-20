import SwiftUI
struct V: View {
    @State private var showSetup = false
    @State private var showDetails = false
    var body: some View {
        Text("Home")
            .addSourceCover(isPresented: $showSetup)
            .taskCover(isPresented: $showDetails) { FileDetailsSheet() }
    }
}
