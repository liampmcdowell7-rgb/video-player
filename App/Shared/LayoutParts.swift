import SwiftUI
import AppLogic

// The shared layout parts of #15 (rules L3, L5, L10, D2, D5). One place for each pattern, so every screen draws it the same
// way. docs/DESIGN_SYSTEM.md, "Shared layout parts".

/// The width of the symbol slot in labels and value columns, scaled with the text size (Larger Text grows it). PROVISIONAL
/// (OPEN_QUESTIONS R177): a symbol at the body style is about this wide, so every symbol sits in the same slot.
enum SymbolSlot {
    static let body: CGFloat = 44
}

/// L10 and D2: a symbol and a title that never touch, with the symbol in a fixed, text-scaled slot. Buttons of one kind
/// therefore have one height and their titles start at the same place, whatever the symbol's own shape (`play.fill` is
/// taller than `ellipsis`). The system lays out the row (`HStack` with the default spacing); the title follows rule S1.
struct SlotLabel: View {
    let title: String
    let systemImage: String
    var style: TVTextStyle = .body
    @ScaledMetric(relativeTo: .body) private var slot: CGFloat = SymbolSlot.body

    init(_ title: String, systemImage: String, style: TVTextStyle = .body) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
    }

    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundStyle(.primary)
                .frame(width: slot, height: slot)
                .accessibilityHidden(true)
            FittingText(title, style: style)
        }
        .accessibilityElement(children: .combine)
    }
}

/// D5: a value-column symbol (the watched check) that always takes its slot, drawn or not, so the columns of a list line up.
struct SymbolColumn: View {
    let systemImage: String
    let isShown: Bool
    let accessibilityText: String
    @ScaledMetric(relativeTo: .body) private var slot: CGFloat = SymbolSlot.body

    var body: some View {
        Image(systemName: systemImage)
            .frame(width: slot)
            .opacity(isShown ? 1 : 0)
            .accessibilityLabel(accessibilityText)
            .accessibilityHidden(!isShown)
    }
}

/// L3: a status or explanation that is plain secondary text, never a row, pill or button.
struct StatusText: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// L5: a section footer keeps one or two lines; the complete text is one press away on its own page.
/// Use it as the last row of a section: `LearnMoreLink(title: "Learn More About Backup", text: BackupTexts.full)`.
struct LearnMoreLink: View {
    let title: String
    let text: String
    var pageTitle: String? = nil

    var body: some View {
        NavigationLink {
            LongTextPage(title: pageTitle ?? title, text: text)
        } label: {
            SlotLabel(title, systemImage: "info.circle")
        }
    }
}
