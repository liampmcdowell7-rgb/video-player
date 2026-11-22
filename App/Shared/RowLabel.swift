import SwiftUI

/// The title and symbol of a list row.
///
/// R391 (owner's review of the run on fd9731f, shared fault 2): the row is the system `Label` again (`SlotLabel`,
/// App/Shared/LayoutParts.swift), so the gap between the symbol and the title is the system's. History: #15 L10 had
/// replaced the `Label` with an `HStack` and a fixed 44 pt symbol slot (R177), which put the symbol 60 to 80 pt from the
/// title. A custom `LabelStyle` is not used (design-lint rule `custom-focus`).
///
/// The symbol takes the same hierarchical foreground as the title (`.primary`), so when the focused row turns light the
/// glyph turns dark with the text (screenshot review item 6). The title follows rule S1 (`FittingText`).
struct RowLabel: View {
    let title: String
    let systemImage: String
    /// #15 7.3: an optional secondary line.
    var detail: String? = nil
    /// R355 (item 6): passed to `SlotLabel`; the Files list row asks for a name that wraps at the floor instead of being
    /// cut (replaces the fade at rest of R229 (c)).
    var wrapsAtFloor: Bool = false

    init(_ title: String, systemImage: String, detail: String? = nil, wrapsAtFloor: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
        self.wrapsAtFloor = wrapsAtFloor
    }

    var body: some View {
        SlotLabel(title, systemImage: systemImage, detail: detail, wrapsAtFloor: wrapsAtFloor)
    }
}
