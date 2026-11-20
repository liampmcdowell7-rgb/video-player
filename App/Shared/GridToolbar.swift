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
/// - #36 6 (OPEN_QUESTIONS R258, PROVISIONAL): the symbol controls are ONE group (`ToolbarIconGroup`): one shared glass
///   container, every symbol control the same width and height (`EqualWidthHStack`). The text controls are the second group,
///   apart (Liquid Glass overview: "don't mix text and icons across items that share a background"). Every control of the
///   line has the height of the tallest (one vertically fixed row, every label fills it): the run of 20 Nov had 87 pt
///   symbols beside 85 pt text controls at Larger Text (68 and 66 at the default size).
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
                    ToolbarIconGroup {
                        viewControls
                        savedViews
                    }
                    // #36 6: no `ActionRow` (its own vertical fixedSize kept the text controls 2 pt lower than the symbols);
                    // the row's fixedSize gives every control the tallest height.
                    HStack(spacing: GridToolbarLayout.inGroup) { tools }
                }
            }
            row {
                ToolbarIconGroup {
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
        // #34 3: explicit spacing, so the width the row needs is known (OPEN_QUESTIONS R233): no system spacing here, the
        // count stays at least `countGap` from the controls.
        // design-lint:allow #34 3 (R233): no system spacing in this row, so its width is computable from GridToolbarLayout; the gap before the count is the spacer's countGap
        HStack(spacing: 0) {
            content()
            Spacer(minLength: GridToolbarLayout.countGap)
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
            // #36 6 (R258): fills the width `EqualWidthHStack` gives it, so every symbol control is the same size.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// #36 6 (OPEN_QUESTIONS R258, PROVISIONAL): the toolbar's symbol controls (Sort, Filter, Saved Views or More) as one group:
/// one `GlassEffectContainer` (SwiftUI, tvOS 26; the app targets tvOS 27) around equal-size controls. No `glassEffect` is
/// added: the controls keep their system style, whose Liquid Glass (on focus, on tvOS) the container lets blend as one group.
/// Whether system controls' glass joins the container is not on any page read: unverified until the next 07 pictures.
/// `ToolbarSpacer` (the system's fixed space between toolbar groups) is not available on tvOS, so the spacings stay
/// `GridToolbarLayout`'s.
struct ToolbarIconGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        // design-lint:allow #36 6 (R258): one shared glass container for the toolbar's symbol group, as the owner decided; no glassEffect of our own
        GlassEffectContainer(spacing: GridToolbarLayout.inGroup) {
            EqualWidthHStack(spacing: GridToolbarLayout.inGroup) {
                content
            }
        }
    }
}

/// #36 6 (R258): a row whose items all get the width of the widest and the height of the tallest (a SwiftUI `Layout`; no
/// system stack gives equal widths), with one explicit spacing between items. Its height follows
/// the row's proposal when that is taller, so the symbols match the text controls beside them.
struct EqualWidthHStack: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let cell: CGSize = cellSize(subviews)
        let count: CGFloat = CGFloat(subviews.count)
        var height: CGFloat = cell.height
        if let proposed = proposal.height, proposed.isFinite { height = max(proposed, cell.height) }
        return CGSize(width: cell.width * count + spacing * (count - 1), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cell: CGSize = cellSize(subviews)
        var x: CGFloat = bounds.minX
        for subview in subviews {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: cell.width, height: bounds.height))
            x += cell.width + spacing
        }
    }

    /// The widest ideal width and the tallest ideal height of the items.
    private func cellSize(_ subviews: Subviews) -> CGSize {
        subviews.reduce(CGSize.zero) { (size: CGSize, subview: LayoutSubview) -> CGSize in
            let ideal: CGSize = subview.sizeThatFits(.unspecified)
            return CGSize(width: max(size.width, ideal.width), height: max(size.height, ideal.height))
        }
    }
}

/// #33 G / #34 3 (OPEN_QUESTIONS R233, PROVISIONAL): the toolbar's spacings, our numbers (the HIG Toolbars page gives none).
/// #33 set 140 pt between the groups against the system's 60 pt inside a group. #34 computed the Larger Text row from the
/// run's notes (07-*-larger-text-GROUPS: controls 125 + 114 + 107 and 476 + 448 pt; the count "7 movies" 171 pt of glyphs,
/// measured on the picture): 1,270 pt of controls + 3 × 60 + 140 + 179 for the count = 1,769 of the 1,760 pt between the
/// 80 pt margins, before the system's space before the count (unknown, 0 to 60 pt), so the Movies row would fold into More.
/// With 60 inside a group a 120 pt gap fits only if that space is under 12 pt, which no Apple page gives. #34: 48 inside a
/// group, 100 between, 40 before the count (1,733 of 1,760 pt at Larger Text, Movies).
/// #36 6 (R258): every symbol control now has the width of the widest (125 pt at Larger Text, 102 at the default size), so
/// the symbol group needs 375 pt instead of 346: with 48 inside a group the Movies row would need 1,762 of 1,760 pt and fold
/// into More. Inside a group is now 40 pt, the horizontal spacing the HIG Layout page gives for tvOS grids (the Toolbars page
/// gives no number); 100 between the groups (ours, ratio 2.5) and 40 before the count (the same Layout number):
/// 1,738 of 1,760 pt at Larger Text (Movies), 1,339 at the default size. Proven on the run's notes by ScreenChecksTests
/// (`testTheToolbarRowFitsAtLargerTextWithTheseGaps`), which reads these constants from this file.
enum GridToolbarLayout {
    static let inGroup: CGFloat = 40
    static let groupGap: CGFloat = 100
    static let countGap: CGFloat = 40
    /// #33 I (R239): at least 60 pt between the toolbar and the first card row, the owner's number in #33 (not Apple's).
    static let belowToolbar: CGFloat = 60
}
