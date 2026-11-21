import SwiftUI
import AppLogic

/// R329 (PROVISIONAL, docs/SOURCE_SETUP_DESIGN.md): About Source Types as a hierarchy of lists (HIG Lists and tables: "iOS
/// Settings uses a hierarchy of lists"). One row per type, each opening that type's About page. Replaces the one long text
/// about every type (10-add-source-learn-more).
struct SourceTypesAboutView: View {
    let kinds: [SourceKindInfo]

    var body: some View {
        TaskPage(title: SourceSetupText.learnMoreTitle) {
            Section {
                ForEach(kinds) { (info: SourceKindInfo) in
                    NavigationLink {
                        SourceAboutPage(info: info)
                    } label: {
                        SourceKindRow(info: info)
                    }
                    .accessibilityIdentifier(ControlID.sourceAbout(info.kind.rawValue))
                }
            }
        }
    }
}

/// R329: one type's About page: its summary as the page header, then what was tested and what was not, or why it cannot be
/// set up yet and what to use instead. Opened from About Source Types, from a type that is not available (20), and from a
/// form's "About WebDAV" row.
struct SourceAboutPage: View {
    let info: SourceKindInfo

    var body: some View {
        TaskPage(title: SourceAboutText.title(info), summary: info.summary) {
            ForEach(SourceAboutText.sections(info), id: \.header) { (section: SourceAboutSection) in
                Section(section.header) {
                    Text(section.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .readableAboutRow()
                }
            }
        }
    }
}

private extension View {
    /// R329: the page is read-only text, so each text row takes the system focus and the Siri Remote can move down a page
    /// that is longer than the screen at Larger Text (as About and the licence texts in Settings). UNVERIFIED: the focus
    /// look of a text row on tvOS 27.
    func readableAboutRow() -> some View {
        // design-lint:allow an About page is read-only text; each text row takes the system focus so the Siri Remote can scroll the page (as AboutView)
        self.focusable()
    }
}
