import SwiftUI

/// The row above the Movies and Shows grids (#15 4.5): the controls, then the count ("6 movies", "2 shows"), in one place
/// and one size on both screens, so both grids start at the same height. Each screen passes the controls it has.
///
/// #25 B2 (OPEN_QUESTIONS R200, PROVISIONAL): one line, every control the same height (`ActionRow`). The run on 1fe5d50
/// (81, Larger Text) wrapped the five controls onto three lines with different heights. `ViewThatFits` tries the full row
/// first; when it does not fit on one line, Saved Views, Needs Review and Jump to Letter move into one More menu
/// (`collapsed`), and Sort, Filter, More and the count stay on the line.
struct GridToolbar<Primary: View, Secondary: View, Collapsed: View>: View {
    let count: String?
    /// Always on the line: Sort and Filter.
    @ViewBuilder var primary: Primary
    /// On the line when it fits: Saved Views, Needs Review, Jump to Letter.
    @ViewBuilder var secondary: Secondary
    /// The same three as menu items, for the More menu when the line does not fit.
    @ViewBuilder var collapsed: Collapsed

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row {
                primary
                secondary
            }
            row {
                primary
                Menu {
                    collapsed
                } label: {
                    ActionLabel("More", systemImage: "ellipsis")
                }
                .accessibilityLabel("More")
                .accessibilityIdentifier(ControlID.moreControls)
            }
        }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ActionRow {
            content()
            if let count {
                FittingText(count)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
