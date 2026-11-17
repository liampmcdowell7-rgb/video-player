import SwiftUI
struct V: View { @State private var on = false; var body: some View { Text("x").animation(.default, value: on) } }
