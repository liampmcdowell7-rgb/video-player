import SwiftUI
import AppLogic

/// R471 item 3 (PROVISIONAL): the capsule Play button of a product page (`PlayCapsule`): the play glyph, then either
/// "Play" or a mini progress bar and the time left ("18m"). The system bordered button in the capsule shape, so it is a
/// light fill when focused and the dark material when not, as in the frames (episode t00s focused, show t10s not).
struct PlayCapsuleButton: View {
    let capsule: PlayCapsule
    let action: () -> Void
    /// The mini bar's width, scaled with the text size. Our measure of the frames (about two letters wide).
    @ScaledMetric(relativeTo: .callout) private var barWidth: CGFloat = 44

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "play.fill")
                    .accessibilityHidden(true)
                if let progress = capsule.progress {
                    ProgressView(value: progress)
                        // design-lint:allow R471: the mini progress bar inside the Play button, the frames' size (episode t00s, show t08s), scaled with the text
                        .frame(width: barWidth)
                        .accessibilityHidden(true)
                    if let left = capsule.timeLeft {
                        Text(left)
                    }
                } else {
                    Text(capsule.title)
                }
            }
            .padding(.horizontal)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .accessibilityLabel(capsule.spoken)
    }
}
