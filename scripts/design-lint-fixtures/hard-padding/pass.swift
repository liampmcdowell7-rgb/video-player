import SwiftUI
struct V: View {
    var body: some View {
        Text("x").padding().padding(.top).frame(maxWidth: .infinity).aspectRatio(2.0 / 3.0, contentMode: .fit)
    }
}
