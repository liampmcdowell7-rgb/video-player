import SwiftUI
import UIKit
import AppLogic

/// The entry page of one source field (docs/SOURCE_SETUP_DESIGN.md, OPEN_QUESTIONS R321, R323, PROVISIONAL): the field
/// name as the heading, one sentence, and ONE system text field. Select on the field shows the system keyboard (HIG Virtual
/// keyboards: "tvOS displays a linear virtual keyboard when people select a text field using the Siri Remote"); Done or
/// Return (`onSubmit`) stores the value and goes back to the form. Back without Done keeps the old value.
///
/// R262 fix: the field's TITLE is the field name and its prompt is the example. Before, the title was empty and the
/// keyboard screen showed the prompt "Living Room" as its heading (11-form-webdav-keyboard-name, run of 20 Nov 2026).
/// Which of the two tvOS 27 draws as the heading is not on Apple's pages (TextField: "Each text field style determines where
/// and when the text field uses a prompt and label"): UNVERIFIED until the `-KEYBOARD-HEADING` check of the next run.
///
/// No Form here: the one field on the page is not a row, so it is not a box inside a row platter (R320).
struct SourceFieldEntryPage: View {
    let spec: SourceFieldSpec
    @Binding var value: String
    var onDone: (_ before: String, _ after: String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var typed: String
    @FocusState private var fieldFocused: Bool

    init(spec: SourceFieldSpec, value: Binding<String>, onDone: @escaping (_ before: String, _ after: String) -> Void) {
        self.spec = spec
        self._value = value
        self.onDone = onDone
        self._typed = State(initialValue: value.wrappedValue)
    }

    private var entry: SourceFieldEntry { SourceFieldEntry.of(spec) }

    var body: some View {
        VStack(alignment: .leading) {
            FittingText(spec.title, style: .title2)
                .accessibilityAddTraits(.isHeader)
            Text(SourceFormText.entrySummary(spec))
                .foregroundStyle(ReadableSecondary.style)
                .fixedSize(horizontal: false, vertical: true)
            field
                .focused($fieldFocused)
                .frame(minHeight: TaskButtonLayout.minimumHeight)
                .padding(.top)
                .accessibilityIdentifier(ControlID.sourceEntryField)
            Spacer(minLength: 0)
        }
        .containerRelativeFrame(.horizontal) { (length: CGFloat, _: Axis) -> CGFloat in
            length * TaskPageLayout.columnFraction
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // R321: the field is the only control, so it has the focus as the page opens (`defaultFocus`, tvOS 16.0+).
        .defaultFocus($fieldFocused, true)
        .navigationTitle(spec.title)
        .toolbarVisibility(.hidden, for: .navigationBar)
    }

    private var prompt: Text? {
        SourceFormText.example(spec).map { Text($0) }
    }

    @ViewBuilder
    private var field: some View {
        if entry.isSecret {
            SecureField(spec.title, text: $typed, prompt: prompt)
                .textContentType(.password)
                .onSubmit(done)
        } else {
            TextField(spec.title, text: $typed, prompt: prompt)
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
