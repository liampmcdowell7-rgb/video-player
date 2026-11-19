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
            // #25 B5: the system label, the same height as the other detail buttons (ActionRow).
            ActionLabel("Extras", systemImage: "doc.on.doc")
        }
        // #25 A2: a Menu with a custom label is a Button with no label of its own (57-movie-detail-HIERARCHY.txt); name it.
        .accessibilityLabel("Extras")
        .accessibilityIdentifier(ControlID.extras)
    }

    private func label(_ extra: ExtraRow) -> String {
        [extra.name, extra.kindText, extra.sizeText].compactMap { $0 }.joined(separator: ", ")
    }
}
