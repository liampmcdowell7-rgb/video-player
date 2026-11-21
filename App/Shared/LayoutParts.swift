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
    /// #34 3: nil (the system spacing). The library toolbar no longer uses `ActionRow` (#36 6: `ToolbarIconGroup`).
    var spacing: CGFloat? = nil
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: spacing) {
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

/// #34 5b (OPEN_QUESTIONS R240, PROVISIONAL): secondary text that must reach 4.5:1 (the HIG's table up to 17 pt; the tvOS
/// text here is larger but regular weight, so the 4.5:1 row is kept), used ONLY for Settings' secondary text and the Media
/// Info labels. The system primary style at 70 % opacity (`ShapeStyle.opacity(_:)`, tvOS 15): measured on the run of 20 Nov
/// (31, 78) it reaches 5.28:1 at the lowest (78 "Resolution" on #344E5D) where .secondary had 2.77 to 4.35 and 60 % had
/// 4.34; 70 % is the lowest that passes everywhere, so it keeps the most distance from the primary text (8.77 to 14.16:1).
/// The 60 % / 70 % / 80 % / 90 % table is printed by ScreenChecksTests (`testTheRunsSecondaryTextAgainstPrimaryAtLowerOpacities`),
/// and `testTheReadableSecondaryOpacityPassesOnTheRunsBackgrounds` reads `opacity` from this file.
enum ReadableSecondary {
    static let opacity: Double = 0.7
    static var style: AnyShapeStyle { AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(opacity)) }
}

/// #36 S-C (OPEN_QUESTIONS R255, PROVISIONAL): the action buttons of a task cover or a Settings page (Connect, Cancel,
/// Save, Move to Shows, Done, Check Connection, Remove Source, Save Key, Remove Key, Back Up Now, Scan Now, Sync Now).
/// Before: full-width Form rows (about 1174 or 850 pt wide) with the label at the left, which look like the rows that open
/// a page. Now: a system bezeled button, its label centred, at least the tvOS default control height (HIG Accessibility:
/// "tvOS | 66x66 pt | 56x56 pt", default and minimum control size); the most likely action `.borderedProminent`, every
/// other one `.bordered` (HIG Buttons: "use a button that has a prominent visual style for the most likely action in a
/// view"; "Keep the number of prominent buttons to one or two per view"). Both styles exist on tvOS (`borderedProminent`
/// tvOS 15.0, `bordered` tvOS 13.0, each "applies a Liquid Glass effect when the button gains focus" in tvOS). Rows that
/// open another page keep the row look.
enum TaskButtonLayout {
    /// HIG Accessibility, tvOS default control size (66 x 66 pt); the label is at least this tall, so the button is too.
    static let minimumHeight: CGFloat = 66
}

/// One action button (#36 S-C, R255): bezeled, label centred on one line (rule S1), `.borderedProminent` when `prominent`.
struct TaskButton: View {
    let title: String
    var role: ButtonRole? = nil
    var prominent: Bool = false
    let action: () -> Void

    init(_ title: String, role: ButtonRole? = nil, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var button: some View {
        Button(role: role, action: action) {
            FittingText(title)
                .frame(maxWidth: .infinity, minHeight: TaskButtonLayout.minimumHeight)
        }
        .accessibilityLabel(title)
    }
}

/// The row that holds one or more `TaskButton`s side by side (#36 S-C, R255). Each button takes an equal share of the row
/// (every label is `maxWidth: .infinity`), so buttons side by side have exactly the same width and height (the equal-size
/// rule); the system spacing between them. The row draws no background of its own: the bezels are the buttons' own.
struct TaskButtonRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack {
            content
        }
        // design-lint:allow #36 S-C (R255): the row around bezeled buttons has no background of its own; the system button bezels are the only shape
        .listRowBackground(Color.clear)
    }
}

/// One text or secure field of a form: the label above the field, the hint inside it as its prompt.
/// History: #36 S-D (R256) drew the field as ONE rounded shape with no row background; #36 group 3 (R265) gave the field
/// the system `bordered` style with a `roundedRectangle` border and still no row background. On a real Apple TV (owner's
/// TestFlight build of 20 Nov 2026, main at 8e347e0) the WebDAV form then showed NO field shapes at all (R273).
/// #36 R273 (OPEN_QUESTIONS R273, PROVISIONAL, the owner's choice of 20 Nov 2026):
/// - the row keeps the system Form row background (no `listRowBackground`), so every field row has a visible shape at rest
///   and the system focus look when focused;
/// - the field has the automatic text field style (Apple, TextFieldStyle `automatic`: "The default text field style, based on
///   the text field's context"); no `bordered`, no `textInputBorderShape`, no custom fill (R165). What the automatic style
///   draws inside a Form row on tvOS 27 is not on Apple's pages: UNVERIFIED until the screenshot check
///   11-form-webdav-FIELDS-AT-REST of the next run (fallback in R273: alternative (e), a value row with a one-field page);
/// - the label above the field at every text size (one line, rule S1, unchanged from R265); every field at least the tvOS
///   default control height (`TaskButtonLayout.minimumHeight`, 66 pt);
/// - the hint ("Living Room", "Optional", the address example) inside the field as its prompt (HIG Text fields: "Show a
///   hint in a text field"; "it can also be useful to include a separate label").
/// `focus`: when given, the field is bound to it (`focused(_:)`), so a form can put its first focus on this field
/// (`SourceFormView`, R273).
/// R262 (the keyboard screen's heading): the field's TITLE stays empty and the spoken label stays the title, exactly as
/// before. Whether tvOS shows the prompt as the keyboard screen's heading is not on Apple's pages: UNVERIFIED until the
/// keyboard picture (11-form-webdav-keyboard-name) of the next run.
struct FieldRow: View {
    let title: String
    var hint: String? = nil
    @Binding var text: String
    var isSecret: Bool = false
    var focus: FocusState<Bool>.Binding? = nil

    init(_ title: String, hint: String? = nil, text: Binding<String>, isSecret: Bool = false,
         focus: FocusState<Bool>.Binding? = nil) {
        self.title = title
        self.hint = hint
        self._text = text
        self.isSecret = isSecret
        self.focus = focus
    }

    var body: some View {
        VStack(alignment: .leading) {
            FittingText(title)
            field
                .modifier(OptionalFocus(focus: focus))
                .frame(maxWidth: .infinity, minHeight: TaskButtonLayout.minimumHeight)
        }
    }

    /// The hint as the field's prompt, when there is one.
    private var prompt: Text? {
        guard let hint, !hint.isEmpty else { return nil }
        return Text(hint)
    }

    /// The control itself: an empty title (R262, unchanged), the hint as its prompt, the title as its spoken label.
    @ViewBuilder
    private var field: some View {
        if isSecret {
            SecureField("", text: $text, prompt: prompt)
                .accessibilityLabel(title)
        } else {
            TextField("", text: $text, prompt: prompt)
                .autocorrectionDisabled()
                .accessibilityLabel(title)
        }
    }
}

/// R273: binds a view to a focus state only when one is given (the first field of a source form); otherwise unchanged.
struct OptionalFocus: ViewModifier {
    let focus: FocusState<Bool>.Binding?

    func body(content: Content) -> some View {
        if let focus {
            content.focused(focus)
        } else {
            content
        }
    }
}
