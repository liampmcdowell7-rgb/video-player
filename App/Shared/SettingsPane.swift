import SwiftUI

/// A settings-style page or sheet (#15 rules L1, L6, D1; PROVISIONAL, OPEN_QUESTIONS R172): the page title and one sentence
/// on the left, the rows in a system `Form` on the right, so rows sit in a column of about half the screen and never run edge
/// to edge across 1920 pt. The navigation bar is hidden, so there is no dim centred duplicate title; the title stays the
/// screen's accessibility header. Used first by the sorting screens (Needs Review, Move, How This Was Sorted); #15 Part 3
/// moves the other Settings pages onto it.
struct SettingsPane<Content: View>: View {
    let title: String
    let summary: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                Text(title)
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)
                Text(summary)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            Form { content }
                .frame(maxWidth: .infinity)
        }
        .navigationTitle(title)
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
}
