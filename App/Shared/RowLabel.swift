import SwiftUI

/// The title and symbol of a list row.
///
/// #15 L10: the screenshots showed the symbol touching the title with the system `Label` in these rows, so the row now uses
/// `SlotLabel` (App/Shared/LayoutParts.swift): the system `HStack` spacing between symbol and title, and the symbol in a
/// fixed, text-scaled slot so every row's title starts at the same place. A custom `LabelStyle` is not used (design-lint
/// rule `custom-focus`). PROVISIONAL, OPEN_QUESTIONS R177. Fixed in code, verify in next screenshots.
///
/// The symbol takes the same hierarchical foreground as the title (`.primary`), so when the focused row turns light the
/// glyph turns dark with the text (screenshot review item 6). The title follows rule S1 (`FittingText`).
struct RowLabel: View {
    let title: String
    let systemImage: String
    /// #15 7.3: an optional secondary line.
    var detail: String? = nil
    /// #33 E: passed to `SlotLabel`; the Files list row asks for the fade at rest and the marquee on focus (R229 (c)).
    var fadesAtRest: Bool = false

    init(_ title: String, systemImage: String, detail: String? = nil, fadesAtRest: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
        self.fadesAtRest = fadesAtRest
    }

    var body: some View {
        SlotLabel(title, systemImage: systemImage, detail: detail, fadesAtRest: fadesAtRest)
    }
}
