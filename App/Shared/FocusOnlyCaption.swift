import SwiftUI
import AppLogic

/// R471 (40), PROVISIONAL (frame show t16s): a lockup's one-line caption that shows only while its button has focus. It
/// keeps its space when hidden (opacity, not removal), so the row does not move as focus passes along it. Inside a
/// `.borderless` lockup's label, `isFocused` is the button's own focus. Secondary text under the poster, on the page's
/// blurred backdrop like every shelf caption (R470); VoiceOver reads the card's own label instead.
struct FocusOnlyCaption: View {
    let text: String
    // design-lint:allow R471 (40): reads focus only to show a line of text on the focused Related card (frame show t16s); the lift and highlight stay the system's
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        FittingText(text, style: .caption)
            .foregroundStyle(ReadableSecondary.style)
            .opacity(isFocused ? 1 : 0)
            .accessibilityHidden(true)
    }
}
