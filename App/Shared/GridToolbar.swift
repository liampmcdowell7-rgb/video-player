import SwiftUI

/// The row above the Movies and Shows grids (#15 4.5), in one place and one size on both screens, so both grids start at the
/// same height. Each screen passes the controls it has.
///
/// #32 D (OPEN_QUESTIONS R233, PROVISIONAL, pick (b)): two groups and the count.
/// - View controls (Sort, Filter, Saved Views) first, as symbols only (`ToolbarSymbol`): HIG Toolbars, "Prefer simple,
///   recognizable symbols for items instead of text", and "Group toolbar items logically by function and frequency of use".
/// - Tools with text labels (Needs Review, Jump to Letter) as a second group, apart from the symbols: "Keep actions with
///   text labels separate" (side by side they "can create the illusion of a single action").
/// - The count last, as plain secondary text pushed to the trailing edge (rule L3: status text is never a control).
/// - Two groups, within the HIG's "aim for a maximum of three". #33 G: the run of 20 Nov measured 60 pt between the controls
///   of a group and only 76 pt between the groups (row spacing plus the system padding; notes 07-*-GROUPS, default size and
///   Larger Text), which did not read as two groups. The gap between the groups is now `GridToolbarLayout.groupGap`.
///
/// #25 B2 (R200, kept): one line at every size, every control the same height (`ActionRow`). `ViewThatFits` tries the full
/// row first; when it does not fit on one line, Saved Views, Needs Review and Jump to Letter move into one More menu
/// (`collapsed`), and Sort, Filter, More and the count stay on the line.
struct GridToolbar<ViewControls: View, SavedViews: View, Tools: View, Collapsed: View>: View {
    let count: String?
    /// Always on the line: Sort and Filter.
    @ViewBuilder var viewControls: ViewControls
    /// On the line, after Filter, when the row fits: the Saved Views menu or button.
    @ViewBuilder var savedViews: SavedViews
    /// The second group when the row fits: Needs Review, Jump to Letter.
    @ViewBuilder var tools: Tools
    /// Saved Views, Needs Review and Jump to Letter as menu items, for the More menu when the row does not fit.
    @ViewBuilder var collapsed: Collapsed

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row {
                // #33 G: one explicit gap between the groups (`GridToolbarLayout.groupGap`).
                HStack(spacing: GridToolbarLayout.groupGap) {
                    ActionRow {
                        viewControls
                        savedViews
                    }
                    ActionRow { tools }
                }
            }
            row {
                ActionRow {
                    viewControls
                    Menu {
                        collapsed
                    } label: {
                        ToolbarSymbol("More", systemImage: "ellipsis")
                    }
                    .accessibilityLabel("More")
                    .accessibilityIdentifier(ControlID.moreControls)
                }
            }
        }
        // #33 I (OPEN_QUESTIONS R239, PROVISIONAL): room between the toolbar and the first row of cards, so a focused card
        // that grows does not reach the toolbar.
        .padding(.bottom, GridToolbarLayout.belowToolbar)
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            content()
            Spacer(minLength: 0)
            if let count {
                FittingText(count)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(ControlID.gridCount)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// #32 D (R233): a toolbar control shown as its SF Symbol only. The title is still the label's text, so VoiceOver and the
/// UI tests find the control by name; `.iconOnly` hides it on screen. One height with the text-labelled controls of the row
/// (`ActionRow`, rule D2).
struct ToolbarSymbol: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .frame(maxHeight: .infinity)
    }
}

/// #33 G (OPEN_QUESTIONS R233, PROVISIONAL): the gap between the toolbar's two groups. 140 pt is our choice, not an Apple
/// number (the HIG Toolbars page gives no gap): at least twice the 60 pt the system puts between the controls of one group
/// (`ActionRow`, measured at the default size and at Larger Text in the run of 20 Nov) plus 20 pt so the ratio (2.33) stays
/// above 2 if that spacing grows by a few points. UI test `checkToolbarGroups` (07-*-GROUPS notes) fails below 2 times.
enum GridToolbarLayout {
    static let groupGap: CGFloat = 140
    /// #33 I (R239): at least 60 pt between the toolbar and the first card row, the owner's number in #33 (not Apple's).
    static let belowToolbar: CGFloat = 60
}
