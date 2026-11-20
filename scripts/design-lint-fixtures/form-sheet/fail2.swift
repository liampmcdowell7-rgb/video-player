import SwiftUI
struct V: View {
    @State private var kind: SourceKind?
    var body: some View {
        Text("Home")
            .sheet(item: $kind) { kind in
                NavigationStack {
                    SourceFormView(draft: SourceDraft(kind: kind), onFinished: {})
                }
            }
    }
}
