import SwiftUI
import AppLogic

/// The files that sit next to the video (subtitles, artwork, information files), listed for reference.
struct ExtrasMenu: View {
    let extras: [ExtraRow]

    var body: some View {
        Menu {
            ForEach(extras) { extra in
                Text(label(extra))
            }
        } label: {
            // #15 D2: the same symbol slot, and so the same height, as the other detail buttons.
            SlotLabel("Extras", systemImage: "doc.on.doc")
        }
    }

    private func label(_ extra: ExtraRow) -> String {
        [extra.name, extra.kindText, extra.sizeText].compactMap { $0 }.joined(separator: ", ")
    }
}
