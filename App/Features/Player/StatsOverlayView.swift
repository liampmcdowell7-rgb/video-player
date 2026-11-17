import SwiftUI
import PlaybackStatus

/// The Playback Stats overlay: every stat at once, small, over the video. Off by default; toggled from the transport bar.
struct StatsOverlayView: View {
    let model: StatsOverlayModel

    var body: some View {
        VStack(alignment: .leading) {
            ForEach(model.statusLines, id: \.self) { line in
                Text(line)
                    .font(.caption2)
            }
            ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.label)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(row.value)
                        .foregroundStyle(row.tone == .warning ? Color.orange : Color.primary)
                }
                .font(.caption2)
            }
        }
        .padding()
        // design-lint:allow content over video: a translucent standard material, never glass (docs/DESIGN_SYSTEM.md rows "Playback Stats overlay" and D-DS9)
        .background(.regularMaterial)
    }
}
