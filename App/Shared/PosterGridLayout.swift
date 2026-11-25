import SwiftUI
import AppLogic

/// R443 (owner's device test of 23 Nov 2026, Movies and Shows): the library controls (Sort and Filter, Save View, More) are
/// the HEADER of the grid. They used to be pinned above the scroll view (`safeAreaInset`), so posters scrolled under them
/// and showed through, and rows scrolled half under the pinned row. The header now sits INSIDE the scroll view, above the
/// first row, and scrolls away with the content, so a button is never on poster art. `libraryToolbar` sets it
/// (App/Shared/GridToolbar.swift); a grid with no header (a person's titles) passes nothing.
private struct LibraryGridHeaderKey: EnvironmentKey {
    static let defaultValue: AnyView? = nil
}

/// R458 (General > List View, PROVISIONAL): the grid draws one row per title (a small poster, the title and its second line)
/// instead of five posters across. The cards read it and draw their row form.
private struct ListRowsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var listRows: Bool {
        get { self[ListRowsKey.self] }
        set { self[ListRowsKey.self] = newValue }
    }

    var libraryGridHeader: AnyView? {
        get { self[LibraryGridHeaderKey.self] }
        set { self[LibraryGridHeaderKey.self] = newValue }
    }
}

/// R471 (49), PROVISIONAL (owner's report of 25 Nov 2026: "only one row displays at a time and when i scroll down once the
/// rows scroll down at least 3 and skip several items that i cant see"): every card is drawn at every scroll position.
/// R443 item 2 hid a card less than 98 % visible (`WholeRowOnly`: opacity 0 from `onScrollVisibilityChange(threshold:
/// 0.98)`). With rows 660 pt apart (a 2:3 poster five across, its caption and the 100 pt row gap) on a 1080 pt screen only
/// one row is ever 98 % visible, so one row showed at a time. A card hidden that way is, by our reading, not a focus
/// candidate (UIKit skips views it cannot see; UNVERIFIED for SwiftUI's `opacity(0)` on tvOS 27), while a row built below
/// the screen but never yet seen kept its starting state (drawn), so one Down passed over the hidden rows to the first row
/// that had never been on screen: three rows on. R443 item 1 stays (the controls are the grid's header and scroll away
/// with it), so no row can sit under them; rows now meet the screen's edges as on any tvOS grid, and the focus engine
/// scrolls the focused row fully into view (`GridScrollRules.focusedRowWhole`, `downReachesNextRow`).

/// The standard poster grid frame: five columns with the layout guidance spacing. Content is whatever tiles the caller makes.
struct PosterGridLayout<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.libraryGridHeader) private var header
    @AppStorage(AppPreference.listView.rawValue) private var listView = false

    // Top-aligned cells (screenshot review item 4): the default centres each card in its row, so posters moved up or down
    // with the amount of text under them.
    // design-lint:allow HIG Layout, five-column grid: 40 pt horizontal spacing (docs/DESIGN_SYSTEM.md section 4)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 40, alignment: .top), count: 5)

    var body: some View {
        ScrollView {
            // design-lint:allow HIG Layout, grid minimum vertical spacing 100 pt (docs/DESIGN_SYSTEM.md section 4)
            VStack(spacing: 100) {
                if let header { header }
                // design-lint:allow HIG Layout, grid minimum vertical spacing 100 pt (docs/DESIGN_SYSTEM.md section 4)
                LazyVGrid(columns: listView ? [GridItem(.flexible())] : columns, spacing: listView ? 40 : 100) { // design-lint:allow R458: the list's row gap, the layout guidance's 40 pt spacing
                    content
                }
                .environment(\.listRows, listView)
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
