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
                RowLabel(row.name, systemImage: "folder", detail: row.detail, wrapsAtFloor: true)
            }
        } else {
            Button(action: onSelectFile) {
                // #15 7.3: the size and format as the second line (R187), replacing the size in the value column.
                RowLabel(row.name, systemImage: symbol, detail: row.detail ?? row.sizeText, wrapsAtFloor: true)
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
