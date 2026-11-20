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
    /// #15 7.3: an optional secondary line under the title, aligned with the title, not the symbol.
    var detail: String? = nil
    @ScaledMetric(relativeTo: .body) private var slot: CGFloat = SymbolSlot.body

    /// #33 E: the Files list row asks for the fade at rest and the marquee on focus (R229 (c)); other rows do not.
    var fadesAtRest: Bool = false

    init(_ title: String, systemImage: String, style: TVTextStyle = .body, detail: String? = nil, fadesAtRest: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.detail = detail
        self.fadesAtRest = fadesAtRest
    }

    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundStyle(.primary)
                .frame(width: slot, height: slot)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                FittingText(title, style: style, fadesAtRest: fadesAtRest)
                if let detail {
                    FittingText(detail, style: .caption, fadesAtRest: fadesAtRest)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// #25 B5: the label of an action button on a movie or show page (Play, Start Over, Versions, Extras, More). The system
/// `Label`, so the gap between the symbol and the title is the system's own, the same in every button; the run on 1fe5d50
/// (57, 60, 61) showed the symbol far left and a wide gap with `SlotLabel` inside these buttons. The title follows rule S1
/// (`FittingText`). The label fills the row's height, so every button in an `ActionRow` has the same height; each button
/// stays as wide as its content.
struct ActionLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            FittingText(title)
        } icon: {
            Image(systemName: systemImage)
        }
        .frame(maxHeight: .infinity)
    }
}

/// #25 B5: a row of action buttons of one height (L10): each button hugs its content, the tallest sets the row's height.
struct ActionRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack {
            content
        }
        .fixedSize(horizontal: false, vertical: true)
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

/// #33 I (OPEN_QUESTIONS R239, PROVISIONAL): the movie and show pages. 40 pt extra below the button row, the owner's
/// minimum in #33 (not an Apple number: the HIG Layout page names 100 pt only for the row spacing of a grid). The run of 20
/// Nov measured 10 pt between the buttons and the next heading on both pages (notes 55-show-page and 57-movie-detail).
enum DetailPageLayout {
    static let belowActions: CGFloat = 40
}
