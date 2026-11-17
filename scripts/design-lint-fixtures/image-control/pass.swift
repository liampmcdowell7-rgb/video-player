import SwiftUI
struct V: View {
    var body: some View {
        VStack {
            Button {
                go()
            } label: {
                Image(systemName: "play.fill")
            }
            AsyncImage(url: nil)
            Image("poster-art")
        }
    }
    func go() {}
}
