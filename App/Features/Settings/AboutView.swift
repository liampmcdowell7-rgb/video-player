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
                LabeledContent("Version", value: AppInfo.version)
            }
            Section("Your Data") {
                Text(AboutText.dataNote)
            }
            Section("Open Source") {
                Text("This app is open source and free. It plays videos you own from servers you set up.")
                Text(LicenseNotices.sourceOffer)
                ForEach(LicenseNotices.sourceLinks) { link in
                    VStack(alignment: .leading) {
                        Text(link.library)
                        Text(link.upstream)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(LicenseNotices.repositoryLine)
            }
            Section(Attribution.aboutHeading) {
                Text(Attribution.aboutNote)
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
                Text(Attribution.whereToWatchNotice)
            }
            // Trademark acknowledgements and the "not affiliated" sentence (docs/NAMES.md section 3). Text only; the
            // TMDB logo above is the only logo anywhere in the app.
            Section(TrademarkNotices.heading) {
                ForEach(TrademarkNotices.lines, id: \.self) { line in
                    Text(line)
                }
            }
            Section(LicenseNotices.heading) {
                Text(LicenseNotices.intro)
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
                }
            }
        }
    }
}
