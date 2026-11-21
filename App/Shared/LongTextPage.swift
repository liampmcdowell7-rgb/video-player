import SwiftUI

/// The page behind `LearnMoreLink` (and "What Is Sent"): the full text in a bounded, readable column. It has no controls,
/// so the scroll view takes focus and the remote scrolls it, as on the licence pages.
struct LongTextPage: View {
    let title: String
    let text: String

    var body: some View {
        // design-lint:allow R345: a long text holds no focusable row (the scroll view itself takes focus)
        ScrollView {
            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
        }
        // design-lint:allow a long text page has no controls, so the scroll view itself takes focus for the Siri Remote to scroll it
        .focusable()
        .pushedScreen(title)
    }
}
