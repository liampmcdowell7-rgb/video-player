import SwiftUI
struct V: View { @Environment(\.isFocused) private var focused; var body: some View { Text("x").scaleEffect(focused ? 1.2 : 1) } }
