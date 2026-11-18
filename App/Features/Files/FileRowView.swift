import SwiftUI
import AppLogic
import LibraryIndex

struct FileRowView: View {
    let sourceID: String
    let sourceName: String
    let row: FileRow
    var onSelectFile: () -> Void

    var body: some View {
        if row.isDirectory {
            NavigationLink(value: Route.folder(sourceID: sourceID, sourceName: sourceName, path: row.id)) {
                RowLabel(row.name, systemImage: "folder")
            }
        } else {
            Button(action: onSelectFile) {
                // The standard title-and-value row: the system places and spaces the size (rule S3).
                LabeledContent {
                    if let size = row.sizeText { Text(size) }
                } label: {
                    RowLabel(row.name, systemImage: symbol)
                }
            }
        }
    }

    private var symbol: String {
        switch row.kind {
        case .video: return "film"
        case .subtitle: return "captions.bubble"
        case .image: return "photo"
        case .nfo: return "doc.text"
        case .directory: return "folder"
        case .other: return "doc"
        }
    }
}
