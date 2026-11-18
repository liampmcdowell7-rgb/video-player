import SwiftUI

/// The title and symbol of a list row: the system `Label` (the system lays out and spaces icon and title, rule S3).
///
/// The symbol takes the same hierarchical foreground as the title (`.primary`), so when the focused row turns light the
/// glyph turns dark with the text. Screenshot review item 6: the "Search Your Network" glyph stayed white on the white focus
/// pill. The title follows rule S1 (`FittingText`).
struct RowLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            FittingText(title)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.primary)
        }
    }
}
