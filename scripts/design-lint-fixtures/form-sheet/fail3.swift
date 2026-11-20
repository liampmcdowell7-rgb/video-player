import SwiftUI
struct V: View {
    @State private var showDetails = false
    var body: some View {
        Text("Files")
            .sheet(isPresented: $showDetails) { FileDetailsSheet() }
    }
}
