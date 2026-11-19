import SwiftUI
import AppLogic

/// The wide picture behind a movie or show page (#15 6.2 and 5.2). Fan art next to the media first, then the matched
/// online backdrop (`ArtworkEngine.backdrop`); with none, the page keeps the system background. Decorative: hidden from
/// VoiceOver. No scrim layer: docs/DESIGN_SYSTEM.md (detail page row, from the HIG Layout page) keeps hero artwork behind
/// controls to the system scroll edge effect, so the picture itself is drawn dimmed over the system background to keep
/// the text readable (OPEN_QUESTIONS R182, PROVISIONAL strengths). Fixed in code, verify in next screenshots.
struct BackdropView: View {
    let artworkKey: String
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var result: ArtworkResult = .none

    /// How much of the picture shows through. PROVISIONAL (R182).
    private var strength: Double { reduceTransparency ? 0.15 : 0.4 }

    var body: some View {
        Color.clear
            .overlay { picture }
            .clipped()
            // design-lint:allow a decorative full-bleed background picture holds no content, so it may reach the screen edges
            .ignoresSafeArea()
            .accessibilityHidden(true)
            .task(id: "\(artworkKey)|\(services.online.keyRevision)") {
                result = await services.online.backdrop(key: artworkKey)
            }
    }

    @ViewBuilder
    private var picture: some View {
        switch result {
        case .file(let url), .remote(let url):
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: .fill).opacity(strength)
                }
            }
        case .none:
            EmptyView()
        }
    }
}
