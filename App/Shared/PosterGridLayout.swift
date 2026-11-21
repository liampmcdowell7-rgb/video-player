import SwiftUI

/// The standard poster grid frame: five columns with the layout guidance spacing. Content is whatever tiles the caller makes.
struct PosterGridLayout<Content: View>: View {
    @ViewBuilder var content: Content

    // Top-aligned cells (screenshot review item 4): the default centres each card in its row, so posters moved up or down
    // with the amount of text under them.
    // design-lint:allow HIG Layout, five-column grid: 40 pt horizontal spacing (docs/DESIGN_SYSTEM.md section 4)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 40, alignment: .top), count: 5)

    var body: some View {
        ScrollView {
            // design-lint:allow HIG Layout, grid minimum vertical spacing 100 pt (docs/DESIGN_SYSTEM.md section 4)
            LazyVGrid(columns: columns, spacing: 100) {
                content
            }
        }
        .scrollClipDisabled()
        // R361 (compile run of 21 Nov 2026, item 8): the whole grid is one focus section. Picture 54: two show cards on the
        // left, "Jump to Letter" right of them; Down searched straight below the button, found no card and stayed. Apple,
        // `focusSection()`: "Indicates that the view's frame and cohort of focusable descendants should be used to guide
        // focus movement." A move toward the grid's frame now lands on its nearest card, whatever the column.
        .focusSection()
    }
}
