import SwiftUI
import AppLogic

/// One field of the source form as ONE system row: a text field, a secure field for the password, or a picker when the field
/// has fixed answers.
///
/// #30 C (OPEN_QUESTIONS R228, PROVISIONAL): at the default text size the label is on the leading side and the field on the
/// trailing side of the same row (`LabeledContent`), so a whole form fits on one screen; before, each field was a section
/// with its own header and the sheet showed only four of them (11, 17). Every field has the same width
/// (`TaskPageLayout.fieldFraction`); the label stays on one line and is never cut (`FittingText`, rules S1 and R199).
/// #30 E: at an accessibility text size the label goes above the field and both use the full row (HIG Layout: "horizontally
/// adjacent views may need to stack vertically"), so nothing is shrunk or cut. The problem texts are under the section
/// (SourceFormView).
/// #36 S-D (OPEN_QUESTIONS R256, PROVISIONAL): text and secure fields are `FieldRow`: one rounded shape (the row draws no
/// background), no placeholder in the field, the former placeholder ("Living Room", "Optional") a hint under the label.
struct SourceFieldRow: View {
    let spec: SourceFieldSpec
    @Binding var text: String

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
        } else {
            FieldRow(spec.title, hint: spec.prompt, text: $text, isSecret: spec.isSecret)
        }
    }

    /// An untouched picker shows the default answer (the catalog keeps its value in `prompt`).
    private var choice: Binding<String> {
        Binding(get: { text.isEmpty ? spec.prompt : text }, set: { text = $0 })
    }
}
