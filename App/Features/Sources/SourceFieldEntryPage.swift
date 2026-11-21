import SwiftUI
import AppLogic

/// The entry page of one source field (docs/SOURCE_SETUP_DESIGN.md, OPEN_QUESTIONS R321, R323, PROVISIONAL): the shared
/// `TextEntryPage` (R333) with the field's name, sentence, example and keyboard from the source catalog.
struct SourceFieldEntryPage: View {
    let spec: SourceFieldSpec
    @Binding var value: String
    var onDone: (_ before: String, _ after: String) -> Void

    var body: some View {
        TextEntryPage(title: spec.title, summary: SourceFormText.entrySummary(spec), example: SourceFormText.example(spec),
                      entry: SourceFieldEntry.of(spec), value: $value, onDone: onDone)
    }
}
