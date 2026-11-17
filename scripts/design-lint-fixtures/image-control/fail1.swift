import SwiftUI
struct V: View {
    var body: some View {
        Button {
            go()
        } label: {
            Image("play-icon")
        }
    }
    func go() {}
}
