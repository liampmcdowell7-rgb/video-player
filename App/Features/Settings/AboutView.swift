import SwiftUI
import VideoPlayerCore
import AppLogic

struct AboutView: View {
    // Height of the TMDB logo: caption-sized and scaled with the text size, so it stays smaller than the screen title and
    // the app's own name (TMDB API terms section 3: less prominent than the marks that identify the app).
    @ScaledMetric(relativeTo: .caption) private var tmdbLogoHeight: CGFloat = 28

    var body: some View {
        // #15 3.8: bounded column with the title on the left (L1, L6).
        SettingsPane(title: "About", summary: SettingsTexts.aboutSummary) {
            Section {
                LabeledContent("Version", value: AppInfo.version).readableRow()
            }
            Section("Your Data") {
                Text(AboutText.dataNote).readableRow()
            }
            Section("Open Source") {
                Text("This app is open source and free. It plays videos you own from servers you set up.").readableRow()
                Text(LicenseNotices.sourceOffer).readableRow()
                ForEach(LicenseNotices.sourceLinks) { link in
                    VStack(alignment: .leading) {
                        Text(link.library)
                        Text(link.upstream)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .readableRow()
                }
                Text(LicenseNotices.repositoryLine).readableRow()
            }
            Section(Attribution.aboutHeading) {
                Text(Attribution.aboutNote).readableRow()
                // The one logo in the app (user decision, OPEN_QUESTIONS R148): TMDB's logo exactly as TMDB publishes it
                // (docs/NAMES.md section 4), next to the notice TMDB requires. Not recoloured: the original colours are kept.
                VStack(alignment: .leading) {
                    Image("TMDBAttributionLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: tmdbLogoHeight) // design-lint:allow the TMDB logo's own image height inside a scrolling list, not a fixed-height card (rule L7)
                        .accessibilityLabel("TMDB")
                    Text(Attribution.catalogueNotice)
                }
                .readableRow()
                Text(Attribution.whereToWatchNotice).readableRow()
            }
            // Trademark acknowledgements and the "not affiliated" sentence (docs/NAMES.md section 3). Text only; the
            // TMDB logo above is the only logo anywhere in the app.
            Section(TrademarkNotices.heading) {
                ForEach(TrademarkNotices.lines, id: \.self) { line in
                    Text(line).readableRow()
                }
            }
            Section(LicenseNotices.heading) {
                Text(LicenseNotices.intro).readableRow()
                NavigationLink("Full Licence Texts") {
                    LicenseTextsView()
                }
                ForEach(LicenseNotices.all) { notice in
                    VStack(alignment: .leading) {
                        Text(notice.name)
                        Text("\(notice.license) · \(notice.use)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(notice.copyright)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .readableRow()
                }
            }
        }
    }
}

private extension View {
    /// #24 C: a text row the Siri Remote can move to. About is long text with one link (Full Licence Texts), so before this
    /// the focus could not move and the page never scrolled: the text above and below the link was out of reach (the
    /// screenshots 41-about-scrolled-1/2/3 equalled 40-about in the run on fa00af8). Fixed in code, verify in next screenshots.
    func readableRow() -> some View {
        // design-lint:allow About is read-only text with one link; each text row takes the system focus so the Siri Remote can scroll the whole page (as LicenseTextView)
        self.focusable()
    }
}
