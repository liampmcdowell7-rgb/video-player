import SwiftUI

/// A settings-style page or sheet (#15 rules L1, L3, L6, D1; PROVISIONAL, OPEN_QUESTIONS R172): the page title and one sentence
/// on the left, the rows in a system `Form` on the right, so rows sit in a column of about half the screen and never run edge
/// to edge across 1920 pt. The navigation bar is hidden, so there is no dim centred duplicate title; the title stays the
/// screen's accessibility header. Status sentences ("Signed in to iCloud", "Reduce Motion: Off") go in `status`: plain
/// secondary text under the summary, never rows or pills (L3). Used by every Settings page (#15 Part 3) and the sorting
/// screens.
struct SettingsPane<Content: View>: View {
    let title: String
    let summary: String
    var status: [String] = []
    @ViewBuilder var content: Content

    var body: some View {
        PaneColumns(title: title, summary: summary, status: status) {
            Form { content }
        }
        .navigationTitle(title)
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
}

/// The two columns of `SettingsPane` without the `Form`: the title (when the screen has none of its own) and the summary on
/// the left, any rows (a `List`) in the right half. #15 7.1: the Files screens use it, so their rows sit in a bounded column
/// like the Settings rows (L1, L2). Fixed in code, verify in next screenshots.
struct PaneColumns<Content: View>: View {
    var title: String? = nil
    let summary: String
    var status: [String] = []
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                if let title {
                    Text(title)
                        .font(.title2)
                        .accessibilityAddTraits(.isHeader)
                }
                Text(summary)
                    .foregroundStyle(.secondary)
                ForEach(status.filter { !$0.isEmpty }, id: \.self) { line in
                    StatusText(line)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            content
                .frame(maxWidth: .infinity)
        }
    }
}
