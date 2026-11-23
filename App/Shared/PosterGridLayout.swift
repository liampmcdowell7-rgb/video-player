import SwiftUI

/// R443 (owner's device test of 23 Nov 2026, Movies and Shows): the library controls (Sort and Filter, Save View, More) are
/// the HEADER of the grid. They used to be pinned above the scroll view (`safeAreaInset`), so posters scrolled under them
/// and showed through, and rows scrolled half under the pinned row. The header now sits INSIDE the scroll view, above the
/// first row, and scrolls away with the content, so a button is never on poster art. `libraryToolbar` sets it
/// (App/Shared/GridToolbar.swift); a grid with no header (a person's titles) passes nothing.
private struct LibraryGridHeaderKey: EnvironmentKey {
    static let defaultValue: AnyView? = nil
}

/// The grid draws a row only when it is fully visible (`WholeRowOnly`): on by default in `PosterGridLayout`, off for the
/// horizontal rows of Home, which show their last card cut on purpose.
private struct GridWholeRowsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var libraryGridHeader: AnyView? {
        get { self[LibraryGridHeaderKey.self] }
        set { self[LibraryGridHeaderKey.self] = newValue }
    }

    var gridWholeRows: Bool {
        get { self[GridWholeRowsKey.self] }
        set { self[GridWholeRowsKey.self] = newValue }
    }
}

/// R443 item 2: "a row is fully visible or not drawn under the header area; scrolling moves by whole rows". A card that
/// is less than 98 % visible in its scroll view is not drawn (opacity 0, still focusable, so a move of the focus onto it
/// scrolls it into view and it appears whole). Every card of a row has the same top and height, so a row appears and
/// disappears as one. `onScrollVisibilityChange(threshold:action:)`: tvOS 18.0+ (https://developer.apple.com/documentation/swiftui/view/onscrollvisibilitychange(threshold:_:)).
/// UNVERIFIED on a device: that the focus engine scrolls to an undrawn card, and the 98 % threshold at the lifted size.
struct WholeRowOnly: ViewModifier {
    @Environment(\.gridWholeRows) private var active
    @State private var whole = true

    @ViewBuilder
    func body(content: Content) -> some View {
        if active {
            content
                .opacity(whole ? 1 : 0)
                .onScrollVisibilityChange(threshold: 0.98) { (visible: Bool) in whole = visible }
        } else {
            content
        }
    }
}

extension View {
    func wholeRowOnly() -> some View { modifier(WholeRowOnly()) }
}

/// The standard poster grid frame: five columns with the layout guidance spacing. Content is whatever tiles the caller makes.
struct PosterGridLayout<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.libraryGridHeader) private var header

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
                LazyVGrid(columns: columns, spacing: 100) {
                    content
                }
                .environment(\.gridWholeRows, true)
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
