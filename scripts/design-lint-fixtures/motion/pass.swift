import SwiftUI
struct V: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    var body: some View { Button("x") { withAnimation(reduceMotion ? nil : .default) { on.toggle() } } }
}
