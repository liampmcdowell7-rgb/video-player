import SwiftUI
import AppLogic

/// Settings > About > Full Licence Texts: every licence and notice text bundled in App/Licenses (OPEN_QUESTIONS R149).
struct LicenseTextsView: View {
    var body: some View {
        List(LicenseNotices.texts) { item in
            NavigationLink(item.title) {
                LicenseTextView(item: item)
            }
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
        ScrollView {
            Text(text)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // design-lint:allow a long licence text has no controls, so the scroll view itself takes focus for the Siri Remote to scroll it
        .focusable()
        .pushedScreen(item.title)
    }
}
