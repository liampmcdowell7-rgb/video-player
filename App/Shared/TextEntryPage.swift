import SwiftUI
import UIKit
import AppLogic

/// One text value as ONE tvOS Settings row (OPEN_QUESTIONS R320, R333, PROVISIONAL): the name leading, the value trailing in
/// the Form's secondary level (`LabeledContent`), nothing when empty, eight dots for a secret (never the secret or its
/// length). Select opens `TextEntryPage`, where the system keyboard is. Used by the source forms (`SourceFieldRow`),
/// Settings > Online Lookup's key (36) and the Move cover (66).
///
/// History: before R320/R333 these screens drew the name above a system text field inside the row platter (`FieldRow`,
/// R256), a box inside a box with typing in place (compile run of 20 Nov 2026). The row is a system row, so the focus look
/// is the system's (HIG Focus and selection: "Rely on system-provided focus effects").
struct TextEntryRow: View {
    let title: String
    @Binding var value: String
    let entry: SourceFieldEntry
    let summary: String
    var example: String? = nil
    let identifier: String
    /// Called after Done on the entry page with the value before and after.
    var onDone: (_ before: String, _ after: String) -> Void = { _, _ in }

    var body: some View {
        NavigationLink {
            TextEntryPage(title: title, summary: summary, example: example, entry: entry, value: $value, onDone: onDone)
        } label: {
            // R351 (compile run of 21 Nov 2026): the value is no longer forced to `.secondary`, which stayed light grey on the
            // white focused row. `LabeledContent` gives the value the system's own value style in a Form, and the system
            // changes it with the focus (UNVERIFIED on tvOS 27 until the next -CONTRAST notes of 11 to 19, 36, 66).
            LabeledContent {
                FittingText(TextEntryRules.rowValue(value, isSecret: entry.isSecret))
            } label: {
                FittingText(title)
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue(TextEntryRules.spokenValue(value, isSecret: entry.isSecret))
        .accessibilityIdentifier(identifier)
    }
}

/// The entry page of one text value (OPEN_QUESTIONS R321, R323, R333, PROVISIONAL): the name as the heading, one sentence,
/// and ONE system text field. Select on the field shows the system keyboard (HIG Virtual keyboards: "tvOS displays a
/// linear virtual keyboard when people select a text field using the Siri Remote"); Done or Return (`onSubmit`) stores the
/// value and goes back. Back without Done keeps the old value.
///
/// R262 fix: the field's TITLE is the name and its prompt is the example. Which of the two tvOS 27 draws as the keyboard
/// screen's heading is not on Apple's pages (TextField: "Each text field style determines where and when the text field
/// uses a prompt and label"): UNVERIFIED until the `-KEYBOARD-HEADING` check of the next run.
///
/// No Form here: the one field on the page is not a row, so it is not a box inside a row platter (R320).
struct TextEntryPage: View {
    let title: String
    let summary: String
    let example: String?
    let entry: SourceFieldEntry
    @Binding var value: String
    var onDone: (_ before: String, _ after: String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var typed: String
    @FocusState private var fieldFocused: Bool

    init(title: String, summary: String, example: String? = nil, entry: SourceFieldEntry, value: Binding<String>,
         onDone: @escaping (_ before: String, _ after: String) -> Void = { _, _ in }) {
        self.title = title
        self.summary = summary
        self.example = example
        self.entry = entry
        self._value = value
        self.onDone = onDone
        self._typed = State(initialValue: value.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading) {
            FittingText(title, style: .title2)
                .accessibilityAddTraits(.isHeader)
            Text(summary)
                .foregroundStyle(ReadableSecondary.style)
                .fixedSize(horizontal: false, vertical: true)
            field
                .focused($fieldFocused)
                .frame(minHeight: TaskButtonLayout.minimumHeight)
                .padding(.top)
                .accessibilityIdentifier(ControlID.entryField)
            Spacer(minLength: 0)
        }
        .containerRelativeFrame(.horizontal) { (length: CGFloat, _: Axis) -> CGFloat in
            length * TaskPageLayout.columnFraction
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // R321: the field is the only control, so it has the focus as the page opens (`defaultFocus`, tvOS 16.0+).
        .defaultFocus($fieldFocused, true)
        .navigationTitle(title)
        .toolbarVisibility(.hidden, for: .navigationBar)
    }

    private var prompt: Text? {
        example.map { Text($0) }
    }

    @ViewBuilder
    private var field: some View {
        if entry.isSecret {
            SecureField(title, text: $typed, prompt: prompt)
                .textContentType(contentType)
                .onSubmit(done)
        } else {
            TextField(title, text: $typed, prompt: prompt)
                .keyboardType(keyboardType)
                .textContentType(contentType)
                .textInputAutocapitalization(entry.capitalizesWords ? .words : .never)
                .autocorrectionDisabled(!entry.autocorrects)
                .onSubmit(done)
        }
    }

    /// R323: UIKit's keyboard for the field (keyboardType(_:), tvOS 13.0+).
    private var keyboardType: UIKeyboardType {
        switch entry.keyboard {
        case .standard: return .default
        case .url: return .URL
        case .numberPad: return .numberPad
        }
    }

    /// R323, R330: the field's meaning, so the system can offer what it has. On tvOS: UNVERIFIED (not on the pages read).
    private var contentType: UITextContentType? {
        switch entry.content {
        case .none: return nil
        case .username: return .username
        case .password: return .password
        case .url: return .URL
        }
    }

    private func done() {
        let before: String = value
        value = typed
        dismiss()
        onDone(before, typed)
    }
}
