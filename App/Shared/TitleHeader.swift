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
    /// R471 (120), PROVISIONAL: the logo's size as a multiple of its fitted size (`HeroMotion.headerLogoWidthRatio` for the
    /// header below the hero); 1 everywhere else. Above 1 a small logo file can be drawn larger than its own pixels.
    var logoScale: Double = 1
    /// R471 (120): told whether the logo is drawn (true) or the text title (false), so the page picks the motion's values.
    var logoShown: Binding<Bool>? = nil
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
                    .frame(width: size.width * logoScale, height: size.height * logoScale) // design-lint:allow the logo's own fitted size from TitleLogoRules (never cropped; enlarged only by logoScale, R471 (120)), not a fixed card
                    .accessibilityElement()
                    .accessibilityLabel(title)
            } else {
                // R393 (item 9 of the owner's review of the run on fd9731f): the title is never cut with "…". Picture
                // 80-larger-text-home showed the featured title cut: a text at its `minimumScaleFactor` floor is
                // truncated by the system. Now the system picks the first that fits (`ViewThatFits`): one line in Large
                // Title, Title 1, Title 2, Title 3, and last Title 3 wrapped onto as many lines as it needs.
                ViewThatFits(in: .horizontal) {
                    oneLine(.largeTitle)
                    oneLine(.title)
                    oneLine(.title2)
                    oneLine(.title3)
                    Text(title)
                        .font(.title3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityAddTraits(.isHeader)
        // R404: found by the -TITLE-GAP note of the UI tests.
        .accessibilityIdentifier("product.title")
        .task(id: "\(artworkKey ?? "")|\(showLogos)|\(services.online.keyRevision)") {
            guard showLogos, let artworkKey else {
                logo = nil
                logoShown?.wrappedValue = false
                return
            }
            let candidates = await services.online.logoCandidates(key: artworkKey)
            logo = await TitleLogoLoader.firstAcceptable(candidates, session: services.online.imageSession)
            logoShown?.wrappedValue = logo != nil
        }
    }

    /// One line in `font`; `ViewThatFits` uses it only when its natural width fits, so it is never cut (rule S1).
    private func oneLine(_ font: Font) -> some View {
        Text(title)
            .font(font)
            .lineLimit(1) // design-lint:allow R393: offered to ViewThatFits only at its natural width, so it is never cut (rule S1)
    }
}
