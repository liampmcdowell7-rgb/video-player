import SwiftUI

/// R375 (owner's feedback on build 5, 21 Nov 2026; decided by the owner's standing rule R312: design follows Apple's TV
/// app): the Movies and Shows controls are the SYSTEM toolbar, not a row of our own. History: #15 4.5 to #36 6 and R344
/// built `GridToolbar`, an `HStack` row in the content with our own spacings (`GridToolbarLayout`: 40 pt inside a group,
/// 100 pt between groups, 40 pt before the count, 60 pt below), a `GlassEffectContainer` of our own (`ToolbarIconGroup`), an
/// equal-width `Layout` (`EqualWidthHStack`) and a `ViewThatFits` fold into More (OPEN_QUESTIONS R200, R233, R239, R258,
/// R344). All of that is gone: the system places and spaces the items.
///
/// What the pages read on 21 Nov 2026 say, and what follows from them:
/// - `toolbar(content:)`: wrapping related items in a `ToolbarItemGroup` "provides a one-to-one mapping between controls and
///   toolbar items which results in the correct layout and spacing on each platform".
/// - `ToolbarItemPlacement.primaryAction`: "In iOS, iPadOS, and tvOS, the location for the primary action is the trailing
///   edge of the navigation bar." (`.automatic` is placed there too on tvOS.)
/// - HIG Toolbars: "Prefer simple, recognizable symbols for items instead of text"; "Add a More menu to contain additional
///   actions"; "Minimize the number of groups ... aim for a maximum of three"; "Keep actions with text labels separate";
///   "Platform considerations: No additional considerations for tvOS."
/// - `ToolbarSpacer` is listed for iOS, iPadOS, Mac Catalyst and macOS 26 only, not tvOS, so the text-labelled actions
///   (Needs Review, Jump to Letter) cannot be set apart with the system's fixed space: they go into the More menu, and the
///   toolbar holds ONE group of symbols (Sort and Filter, Saved Views, More). tvOS draws no overflow menu of its own (the
///   `ToolbarItemPlacement` page names iOS, iPadOS and macOS for that).
/// - No tvOS release note from 26 to 27.3 beta 2 mentions toolbar layout.
/// UNVERIFIED (nothing is compiled or run here, R318): how tvOS 27 draws these items in the navigation bar of a tab with the
/// sidebar-adaptable tab view, its spacing, and how the focus moves from the grid up to them.
extension View {
    /// The library toolbar of Movies and Shows: `shown` is false over "No Sources" and "Nothing Here Yet".
    func libraryToolbar<ViewControls: View, SavedViews: View, MoreItems: View>(
        shown: Bool,
        hasMore: Bool,
        @ViewBuilder viewControls: () -> ViewControls,
        @ViewBuilder savedViews: () -> SavedViews,
        @ViewBuilder more: () -> MoreItems
    ) -> some View {
        let controls: ViewControls = viewControls()
        let saved: SavedViews = savedViews()
        let moreItems: MoreItems = more()
        return toolbar {
            if shown {
                ToolbarItemGroup(placement: .primaryAction) {
                    controls
                    saved
                    if hasMore {
                        // HIG Toolbars: "Add a More menu to contain additional actions." Needs Review and Jump to Letter.
                        Menu {
                            moreItems
                        } label: {
                            ToolbarSymbol("More", systemImage: "ellipsis")
                        }
                        .accessibilityLabel("More")
                        .accessibilityIdentifier(ControlID.moreControls)
                    }
                }
            }
        }
    }
}

/// #32 D (R233), R375: a toolbar control shown as its SF Symbol only, the system's own icon-only label style. The title is
/// still the label's text, so VoiceOver and the UI tests find the control by name.
/// R391 (owner's review of the run on fd9731f, shared fault 3; PROVISIONAL): every toolbar control draws its symbol in the
/// SAME text-scaled square (`SymbolSlot.body`), so the three controls have one size. Cause of the fault: each control was
/// as large as its own symbol, and the three symbols have different shapes (the run measured 108 x 66, 98 x 81 and
/// 100 x 63, further apart at Larger Text). The square is the one frame of ours here; no Apple page gives a way to make
/// toolbar items equal, and the app's own rule is "elements side by side have equal size". The spacing between the
/// controls and their place stay the system's (`ToolbarItemGroup`, `.primaryAction`); the 60 pt between them in the run
/// is the system's own spacing.
struct ToolbarSymbol: View {
    let title: String
    let systemImage: String
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = SymbolSlot.body

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .frame(width: side, height: side) // design-lint:allow R391: one text-scaled square for every toolbar symbol, so controls side by side are the same size (the equal-size rule)
        }
        .labelStyle(.iconOnly)
    }
}

/// R375 (PROVISIONAL): the count ("7 movies") as one line of plain secondary text above the grid (rule L3: status text is
/// never a control). tvOS has no system home for it: `navigationSubtitle` and the `.subtitle` placement are iOS, iPadOS and
/// macOS only, and `.status` on tvOS works "only ... from within the sidebar of a NavigationSplitView".
struct GridCountLine: View {
    let count: String?

    var body: some View {
        if let count {
            FittingText(count)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(ControlID.gridCount)
                // R392 (item 4 of the owner's review of the run on fd9731f): room under the count for the focused card
                // of the first row, which grew over it. No Apple page gives this gap; AppLogic
                // `ProductPageSpacing.aboveFirstGridRow` derives it from HIG Layout's 100 pt between grid rows.
                .padding(.bottom, CGFloat(ProductPageSpacing.aboveFirstGridRow))
        }
    }
}
