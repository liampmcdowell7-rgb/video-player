import SwiftUI
import AppLogic

/// The files that sit next to the video (subtitles, artwork, information files), listed for reference.
struct ExtrasMenu: View {
    let extras: [ExtraRow]

    var body: some View {
        Menu("Extras", systemImage: "doc.on.doc") {
            ForEach(extras) { extra in
                Text(label(extra))
            }
        }
    }

    private func label(_ extra: ExtraRow) -> String {
        [extra.name, extra.kindText, extra.sizeText].compactMap { $0 }.joined(separator: ", ")
    }
}
