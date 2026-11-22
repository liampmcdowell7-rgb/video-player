import SwiftUI

/// The page behind `LearnMoreLink` (and "What Is Sent"), and the whole synopsis in its full-screen cover (R377): the full
/// text in a bounded, readable column. It has no controls,
/// so the scroll view takes focus and the remote scrolls it, as on the licence pages.
struct LongTextPage: View {
    let title: String
    let text: String

    var body: some View {
        // design-lint:allow R345: a long text holds no focusable row (the scroll view itself takes focus)
        ScrollView {
            VStack(alignment: .leading) {
                // R365 (compile run of 21 Nov 2026, item 13): the title is the page's visible heading, as on every other
                // pushed page (Full Licence Texts, #33 J). Picture 77-movie-long-synopsis-page showed the text alone, with
                // nothing saying whose synopsis it was (the navigation bar is hidden, rule D1). One line, rule S1.
                FittingText(title, style: .title2)
                    .accessibilityAddTraits(.isHeader)
                Text(text)
                    .font(.body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        }
        // design-lint:allow a long text page has no controls, so the scroll view itself takes focus for the Siri Remote to scroll it
        .focusable()
        .pushedScreen(title)
    }
}
