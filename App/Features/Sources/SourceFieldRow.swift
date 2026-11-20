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
struct SourceFieldRow: View {
    let spec: SourceFieldSpec
    @Binding var text: String
    @Environment(\.dynamicTypeSize) private var typeSize

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
        } else if typeSize.isAccessibilitySize {
            VStack(alignment: .leading) {
                FittingText(spec.title)
                field
            }
        } else {
            LabeledContent {
                field
                    .containerRelativeFrame(.horizontal) { (length: CGFloat, _: Axis) -> CGFloat in
                        length * TaskPageLayout.fieldFraction
                    }
            } label: {
                FittingText(spec.title)
            }
        }
    }

    /// The control itself; its title stays its spoken label.
    @ViewBuilder
    private var field: some View {
        if spec.isSecret {
            SecureField(spec.title, text: $text, prompt: Text(spec.prompt))
        } else {
            TextField(spec.title, text: $text, prompt: Text(spec.prompt))
                .autocorrectionDisabled()
        }
    }

    /// An untouched picker shows the default answer (the catalog keeps its value in `prompt`).
    private var choice: Binding<String> {
        Binding(get: { text.isEmpty ? spec.prompt : text }, set: { text = $0 })
    }
}
