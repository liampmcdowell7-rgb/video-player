import SwiftUI
import AppLogic

/// One source type in the list (#15 2.1, rule L9): its name, one short description line, and one badge line (how well it
/// has been tested). The full status sentence and any caveat are on the type's form. A type that cannot be set up keeps
/// its whole reason (nothing may disappear), under the "Not Available Yet" header.
struct SourceKindRow: View {
    let info: SourceKindInfo

    var body: some View {
        VStack(alignment: .leading) {
            FittingText(info.title)
            FittingText(info.summary, style: .caption)
                .foregroundStyle(.secondary)
            if let note = info.unavailableNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                FittingText(SourceSetupText.statusBadge(info.kind), style: .caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
