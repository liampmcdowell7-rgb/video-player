import SwiftUI
import AppLogic

/// One field of the source form: a text field, a secure field for the password, or a picker when the field has fixed answers,
/// with its problem text underneath.
struct SourceFieldRow: View {
    let spec: SourceFieldSpec
    @Binding var text: String
    let problem: String?

    var body: some View {
        Section {
            if !spec.choices.isEmpty {
                Picker(spec.title, selection: choice) {
                    ForEach(spec.choices) { option in
                        Text(option.title).tag(option.value)
                    }
                }
            } else if spec.isSecret {
                SecureField(spec.title, text: $text, prompt: Text(spec.prompt))
            } else {
                TextField(spec.title, text: $text, prompt: Text(spec.prompt))
                    .autocorrectionDisabled()
            }
        } header: {
            Text(spec.title)
        } footer: {
            if let problem {
                Text(problem)
            }
        }
    }

    /// An untouched picker shows the default answer (the catalog keeps its value in `prompt`).
    private var choice: Binding<String> {
        Binding(get: { text.isEmpty ? spec.prompt : text }, set: { text = $0 })
    }
}
