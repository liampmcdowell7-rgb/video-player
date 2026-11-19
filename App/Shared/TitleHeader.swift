import SwiftUI
import AppLogic

/// The title at the top of a movie page or a show page (#15 Part 9, R179). With "Show Title Logos" on and an acceptable logo
/// found (`TitleLogoLoader`), the logo is drawn in place of the text: fitted to the 640 × 200 pt box, never enlarged beyond
/// its own size, never cropped. It carries the title as its accessibility label and header trait; the text title is not drawn
/// beside it. Otherwise (no logo, setting off, still loading) the text title, under rule S1.
struct TitleHeader: View {
    let title: String
    /// `item-N` (a movie) or `series-N` (a show); nil for pages that never show a logo (an episode page).
    let artworkKey: String?
    @AppStorage(SettingsKey.showTitleLogos.rawValue) private var showLogos = true
    @Environment(AppServices.self) private var services
    @Environment(\.displayScale) private var displayScale
    @State private var logo: TitleLogoLoader.Loaded?

    var body: some View {
        Group {
            if showLogos, artworkKey != nil, let logo {
                let size = TitleLogoRules.fittedSize(pixelWidth: logo.pixels.width, pixelHeight: logo.pixels.height, scale: displayScale)
                Image(decorative: logo.image, scale: displayScale)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height) // design-lint:allow the logo's own fitted size from TitleLogoRules (never enlarged, never cropped), not a fixed card
                    .accessibilityElement()
                    .accessibilityLabel(title)
            } else {
                Text(title)
                    .font(.largeTitle)
                    .lineLimit(1)
                    // design-lint:allow rule S1 (OPEN_QUESTIONS R165): the system text style shrinks to fit, never below Apple's 23 pt minimum (HIG Typography)
                    .minimumScaleFactor(ShortLine.minimumScale(forPointSize: TVTextStyle.title1.pointSize))
            }
        }
        .accessibilityAddTraits(.isHeader)
        .task(id: "\(artworkKey ?? "")|\(showLogos)|\(services.online.keyRevision)") {
            guard showLogos, let artworkKey else { logo = nil; return }
            let candidates = await services.online.logoCandidates(key: artworkKey)
            logo = await TitleLogoLoader.firstAcceptable(candidates, session: services.online.imageSession)
        }
    }
}
