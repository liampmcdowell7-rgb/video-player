import SwiftUI
import AppLogic

/// One source type in the list: its name, what it is, and either why it is blocked or how well it has been tested.
struct SourceKindRow: View {
    let info: SourceKindInfo

    var body: some View {
        VStack(alignment: .leading) {
            FittingText(info.title)
            Text(info.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(info.unavailableNote ?? info.statusLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let caveat = info.caveat, info.isAvailable {
                Text(caveat)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
