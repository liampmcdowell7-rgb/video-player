import SwiftUI
import AppLogic

/// File Details: name, size, date and where the file is. The path is shown here and nowhere else (it can be long and private).
struct FileDetailsSheet: View {
    let row: FileRow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Name", value: row.name)
                if let size = row.sizeText {
                    LabeledContent("Size", value: size)
                }
                if let modified = row.modified {
                    LabeledContent("Modified") { Text(modified, format: .dateTime) }
                }
                LabeledContent("Location", value: row.id)
                Button("Done") { dismiss() }
            }
            .navigationTitle("File Details") // design-lint:allow sheet root: the title is the sheet's own heading, not a pushed page (rule D1 is for pushed pages)
        }
    }
}
