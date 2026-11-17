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
                Label(row.name, systemImage: "folder")
            }
        } else {
            Button(action: onSelectFile) {
                HStack {
                    Label(row.name, systemImage: symbol)
                    Spacer()
                    if let size = row.sizeText {
                        Text(size)
                            .foregroundStyle(.secondary)
                    }
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
