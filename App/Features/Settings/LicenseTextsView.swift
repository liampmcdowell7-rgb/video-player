import SwiftUI
import AppLogic

/// Settings > About > Full Licence Texts: every licence and notice text bundled in App/Licenses (OPEN_QUESTIONS R149).
struct LicenseTextsView: View {
    var body: some View {
        VStack(alignment: .leading) {
            // #33 J: the page's visible title, once (the navigation bar is hidden on pushed pages, rule D1). One line, rule S1.
            FittingText("Full Licence Texts", style: .title2)
                .accessibilityAddTraits(.isHeader)
            List(LicenseNotices.texts) { item in
                NavigationLink(item.title) {
                    LicenseTextView(item: item)
                }
            }
            // R345: the focused row grows past the list's edge; the list must not clip it (42, 43).
            .scrollClipDisabled()
            // R346 (item A): the scrolling page is one focus region, so Up scrolls back to its first row before it
            // can leave for the tab bar (reason and UNVERIFIED cause: PaneColumns, App/Shared/SettingsPane.swift).
            .focusSection()
        }
        .pushedScreen("Full Licence Texts")
    }
}

/// One licence text, read from the app bundle. A missing file is said plainly instead of showing an empty page.
struct LicenseTextView: View {
    let item: BundledLicenseText

    private var text: String {
        guard let url = Bundle.main.url(forResource: item.fileName, withExtension: "txt"),
              let body = try? String(contentsOf: url, encoding: .utf8) else {
            return "This licence text is missing from this build (\(item.fileName).txt). It is in the app’s source repository."
        }
        return body
    }

    var body: some View {
        // design-lint:allow R345: a licence text holds no focusable row (the scroll view itself takes focus)
        ScrollView {
            VStack(alignment: .leading) {
                // #33 J: the page's title, drawn once (the navigation bar is hidden on pushed pages, rule D1, so the page
                // had no visible title). One line, rule S1.
                FittingText(item.title, style: .title2)
                    .accessibilityAddTraits(.isHeader)
                Text(text)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // design-lint:allow a long licence text has no controls, so the scroll view itself takes focus for the Siri Remote to scroll it
        .focusable()
        .pushedScreen(item.title)
    }
}
