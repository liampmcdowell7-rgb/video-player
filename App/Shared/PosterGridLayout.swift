import SwiftUI

/// The standard poster grid frame: five columns with the layout guidance spacing. Content is whatever tiles the caller makes.
struct PosterGridLayout<Content: View>: View {
    @ViewBuilder var content: Content

    // design-lint:allow HIG Layout, five-column grid: 40 pt horizontal spacing (docs/DESIGN_SYSTEM.md section 4)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 40), count: 5)

    var body: some View {
        ScrollView {
            // design-lint:allow HIG Layout, grid minimum vertical spacing 100 pt (docs/DESIGN_SYSTEM.md section 4)
            LazyVGrid(columns: columns, spacing: 100) {
                content
            }
        }
        .scrollClipDisabled()
    }
}
