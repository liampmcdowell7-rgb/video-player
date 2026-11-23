import SwiftUI
import AppLogic

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
/// R413 (run #27): the focus never moved from the grid up to them, so the same controls are now a row on the page (see
/// `libraryToolbar`); the rest of the reasoning above (one group, More menu, symbols) still holds.
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
        // R413 (run #27, TOOLBAR-PATH notes; R405 reopened as an app fault; PROVISIONAL): the controls are a row ON THE
        // PAGE above the grid, no longer the system toolbar. Run #27: Right along the first row, then Up, went to the
        // sidebar, never to Sort and Filter in the navigation bar; on Shows (two titles) no card is under the controls at
        // all, so a person on an Apple TV could not reach them either. `focusSection()` (tvOS 15.0+,
        // https://developer.apple.com/documentation/swiftui/view/focussection()): "the view's frame becomes capable of
        // accepting focus in order to direct it at its nearest focusable descendant in the direction of travel". The row
        // spans the full width, so Up from ANY card of the first row (whatever the number of titles) enters it and lands on
        // the nearest control. The system navigation bar is outside our views, so no section can be put around it.
        // `safeAreaInset(edge:alignment:spacing:content:)` (tvOS 15.0+,
        // https://developer.apple.com/documentation/swiftui/view/safeareainset(edge:alignment:spacing:content:)-4s51l)
        // keeps the row above the scrolling grid. Same controls, same order, same symbols and identifiers.
        // R443 (owner's device test of 23 Nov 2026, items 1 and 3): the row is the HEADER of the grid, inside its scroll view
        // (`PosterGridLayout`), not pinned above it. Before (`safeAreaInset`): "the three buttons stay pinned while posters
        // scroll under and show through them". It scrolls away with the content, as the Apple TV app's header does, and the
        // `focusSection()` of R413 is kept, so Up from any first-row card reaches the controls. The look: HIG Materials,
        // "Liquid Glass forms a distinct functional layer for controls and navigation elements"; `glass` button style,
        // "In tvOS, this button style applies a Liquid Glass effect regardless of whether the button has focus"
        // (https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass); `GlassEffectContainer` "combines
        // multiple Liquid Glass shapes into a single shape that can morph individual shapes into one another"
        // (https://developer.apple.com/documentation/swiftui/glasseffectcontainer); all tvOS 26.0+. The focus lift is the
        // system's (HIG Focus and selection: "Rely on system-provided focus effects"). UNVERIFIED on a device: how a `Menu`
        // takes `.glass`.
        let row: AnyView = AnyView(
            // design-lint:allow R443: the documented GlassEffectContainer for the three toolbar buttons (HIG Materials; recorded in OPEN_QUESTIONS R443)
            GlassEffectContainer(spacing: 24) {
                // design-lint:allow HIG Layout, 24 pt between the toolbar buttons (docs/DESIGN_SYSTEM.md section 4)
                HStack(spacing: 24) {
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
                .buttonStyle(.glass)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .focusSection()
        )
        return environment(\.libraryGridHeader, shown ? row : nil)
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
    @ScaledMetric(relativeTo: .title2) private var side: CGFloat = SymbolSlot.toolbar

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                // R443 (item 3): larger and heavier for 3 m ("thin low-contrast glyphs"): the title-2 text style in the semibold
                // weight, a system style that follows Larger Text; the symbol stays inside the one shared square below.
                .font(.title2.weight(.semibold))
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
