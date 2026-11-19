import SwiftUI
struct V: View {
    let cardHeight: CGFloat
    var body: some View {
        List {
            Text("Types")
        }
        .frame(maxHeight: cardHeight)
    }
}
