import SwiftUI
import AppLogic

/// File Details: name, size, date and where the file is. The path is shown here and nowhere else (it can be long and private).
///
/// #25 B9 (74): the run on 1fe5d50 showed an empty action button in this dialog. The cause is not proven from the picture
/// alone; the sheet is rebuilt from the same parts as the other sheets: `SheetColumn` (one column, the title drawn once, no
/// navigation bar title), one-line `ValueRow`s, the long path as plain text in its own section (it is the user's own text
/// and may wrap; it is not a short label), and a single titled Done button. Fixed in code, verify in the next 74.
struct FileDetailsSheet: View {
    let row: FileRow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SheetColumn(title: "File Details") {
                Section("Name") {
                    // A file name is the user's own text: it wraps and is never cut (R172), so it is not a one-line row.
                    Text(row.name)
                }
                Section {
                    if let size = row.sizeText {
                        ValueRow("Size", value: size)
                    }
                    if let modified = row.modified {
                        ValueRow("Modified", value: modified.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                Section("Location") {
                    // #30 F, R229: the path on ONE line, scaled to the readable floor; when even that is too long the system
                    // marquee shows it whole while this row has focus. The row is a link to the whole path as a page, so it can
                    // take the focus (and the path can be read at full size).
                    NavigationLink {
                        LongTextPage(title: "Location", text: row.id)
                    } label: {
                        FittingText(row.id)
                    }
                    .accessibilityLabel("Location")
                    .accessibilityValue(row.id)
                }
                Section {
                    // #30 F: the last row is a named control with its symbol (74: a focused white bar with no visible label).
                    Button { dismiss() } label: { RowLabel("Done", systemImage: "checkmark") }
                }
            }
        }
    }
}
