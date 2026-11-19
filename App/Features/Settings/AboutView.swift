import SwiftUI
import VideoPlayerCore
import AppLogic

struct AboutView: View {
    // Height of the TMDB logo: caption-sized and scaled with the text size, so it stays smaller than the screen title and
    // the app's own name (TMDB API terms section 3: less prominent than the marks that identify the app).
    @ScaledMetric(relativeTo: .caption) private var tmdbLogoHeight: CGFloat = 28

    var body: some View {
        // #15 3.8: bounded column with the title on the left (L1, L6).
        // #25 B9: the long legal texts (source offer and links, trademark lines, the licence notices) are on Learn More pages,
        // one press away, nothing removed; the page keeps the version, the data note, and the TMDB logo with the notice TMDB
        // requires next to it. Fixed in code, verify in the next 40, 41, 42, 43.
        SettingsPane(title: "About", summary: SettingsTexts.aboutSummary) {
            Section {
                ValueRow("Version", value: AppInfo.version).readableRow()
            }
            Section("Your Data") {
                Text(AboutText.dataNote).readableRow()
            }
            Section("Open Source") {
                Text("This app is open source and free. It plays videos you own from servers you set up.").readableRow()
                LearnMoreLink(title: "Source Code", text: sourceText)
            }
            Section(Attribution.aboutHeading) {
                Text(Attribution.aboutNote).readableRow()
                    .accessibilityIdentifier(ControlID.dataSources)
                // The one logo in the app (user decision, OPEN_QUESTIONS R148): TMDB's logo exactly as TMDB publishes it
                // (docs/NAMES.md section 4), next to the notice TMDB requires. Not recoloured: the original colours are kept.
                // #25 B9: the logo sits at the row's leading edge, with the system spacing above the notice.
                VStack(alignment: .leading) {
                    Image("TMDBAttributionLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: tmdbLogoHeight, alignment: .leading) // design-lint:allow the TMDB logo's own image height inside a scrolling list, not a fixed-height card (rule L7)
                        .accessibilityLabel("TMDB")
                    Text(Attribution.catalogueNotice)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .readableRow()
                Text(Attribution.whereToWatchNotice).readableRow()
                // #26 item 7: text-only credits for the key-free sources, each with a short Learn More.
                Text(Attribution.wikidataCredit).readableRow()
                LearnMoreLink(title: Attribution.wikidataLearnMoreTitle, text: Attribution.wikidataLearnMore)
                Text(Attribution.introDBCredit).readableRow()
                LearnMoreLink(title: Attribution.introDBLearnMoreTitle, text: Attribution.introDBLearnMore)
            }
            // Trademark acknowledgements and the "not affiliated" sentence (docs/NAMES.md section 3). Text only; the
            // TMDB logo above is the only logo anywhere in the app.
            Section(LicenseNotices.heading) {
                NavigationLink {
                    LicenseTextsView()
                } label: {
                    SlotLabel("Full Licence Texts", systemImage: "doc.text")
                }
                .accessibilityIdentifier(ControlID.fullLicenceTexts)
                LearnMoreLink(title: "Licence Notices", text: noticesText)
                LearnMoreLink(title: TrademarkNotices.heading, text: TrademarkNotices.lines.joined(separator: "\n\n"))
            }
        }
        // #25 B9: the system scroll-edge effect where the page scrolls under the tab bar (tvOS 26 and later).
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private var sourceText: String {
        ([LicenseNotices.sourceOffer]
         + LicenseNotices.sourceLinks.map { $0.library + "\n" + $0.upstream }
         + [LicenseNotices.repositoryLine]).joined(separator: "\n\n")
    }

    private var noticesText: String {
        ([LicenseNotices.intro]
         + LicenseNotices.all.map { "\($0.name)\n\($0.license) · \($0.use)\n\($0.copyright)" }).joined(separator: "\n\n")
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
