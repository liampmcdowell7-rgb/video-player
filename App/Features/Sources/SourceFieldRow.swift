import SwiftUI
import AppLogic

/// One field of a source form as ONE tvOS Settings row (docs/SOURCE_SETUP_DESIGN.md, OPEN_QUESTIONS R320, PROVISIONAL).
///
/// - A text field is a system `NavigationLink` row: the field name leading, the current value trailing in the Form's
///   secondary level (`LabeledContent`), nothing when empty (R322: never "Optional" or an example in the value position),
///   eight dots for a password. Select opens the field's entry page (`SourceFieldEntryPage`, R321), where the system
///   keyboard is.
/// - A field with fixed answers (FTP Encryption) stays a system `Picker` row, which already shows its answer trailing.
///
/// History: before R320 this row drew the label above a system text field inside the row platter (R256, R265, R273), a box
/// inside a box with typing in place (compile run of 20 Nov 2026, 11 to 19). The rows are system rows, so the focus look
/// is the system's (HIG Focus and selection: "Rely on system-provided focus effects").
struct SourceFieldRow: View {
    let spec: SourceFieldSpec
    @Binding var text: String
    /// Called after Done on the entry page with the value before and after (the form decides where the focus goes, R325).
    var onDone: (_ before: String, _ after: String) -> Void = { _, _ in }

    var body: some View {
        if !spec.choices.isEmpty {
            Picker(selection: choice) {
                ForEach(spec.choices) { option in
                    Text(option.title).tag(option.value)
                }
            } label: {
                FittingText(spec.title)
            }
            .accessibilityLabel(spec.title)
            .accessibilityIdentifier(ControlID.sourceField(spec.kind.rawValue))
        } else {
            NavigationLink {
                SourceFieldEntryPage(spec: spec, value: $text, onDone: onDone)
            } label: {
                LabeledContent {
                    FittingText(SourceFormText.rowValue(spec, text))
                        .foregroundStyle(.secondary)
                } label: {
                    FittingText(spec.title)
                }
            }
            .accessibilityLabel(spec.title)
            .accessibilityValue(SourceFormText.spokenValue(spec, text))
            .accessibilityIdentifier(ControlID.sourceField(spec.kind.rawValue))
        }
    }

    /// An untouched picker shows the default answer (the catalog keeps its value in `prompt`).
    private var choice: Binding<String> {
        Binding(get: { text.isEmpty ? spec.prompt : text }, set: { text = $0 })
    }
}
