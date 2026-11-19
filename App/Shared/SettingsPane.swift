import SwiftUI

/// A settings-style page or sheet (#15 rules L1, L3, L6, D1; PROVISIONAL, OPEN_QUESTIONS R172): the page title and one sentence
/// on the left, the rows in a system `Form` on the right, so rows sit in a column of about half the screen and never run edge
/// to edge across 1920 pt. The navigation bar is hidden, so there is no dim centred duplicate title; the title stays the
/// screen's accessibility header. Status sentences ("Signed in to iCloud", "Reduce Motion: Off") go in `status`: plain
/// secondary text under the summary, never rows or pills (L3). Used by every Settings page (#15 Part 3) and the sorting
/// screens.
struct SettingsPane<Content: View>: View {
    let title: String
    let summary: String
    var status: [String] = []
    @ViewBuilder var content: Content

    var body: some View {
        PaneColumns(title: title, summary: summary, status: status) {
            Form { content }
        }
        .navigationTitle(title)
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
}

/// #25 B1 (OPEN_QUESTIONS R202, PROVISIONAL): a sheet's page as ONE column, full height: the title on top, one sentence under
/// it, then the rows in a system `Form`. The Add a Source sheet is a panel narrower than the screen; the two columns of
/// `SettingsPane` cramped it (the run on 1fe5d50: "Sea…", "A web folder, f…", the title "WebDAV" past the panel's left edge,
/// 10, 93, 94, 99, 100, 110, 111). The navigation bar stays hidden (rule D1), so the title is drawn once, here.
struct SheetColumn<Content: View>: View {
    let title: String
    var summary: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading) {
            FittingText(title, style: .title2)
                .accessibilityAddTraits(.isHeader)
            if let summary {
                Text(summary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Form { content }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(title)
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
}

/// The two columns of `SettingsPane` without the `Form`: the title (when the screen has none of its own) and the summary on
/// the left, any rows (a `List`) in the right half. #15 7.1: the Files screens use it, so their rows sit in a bounded column
/// like the Settings rows (L1, L2). Fixed in code, verify in next screenshots.
struct PaneColumns<Content: View>: View {
    var title: String? = nil
    let summary: String
    var status: [String] = []
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                if let title {
                    Text(title)
                        .font(.title2)
                        .accessibilityAddTraits(.isHeader)
                }
                Text(summary)
                    .foregroundStyle(.secondary)
                ForEach(status.filter { !$0.isEmpty }, id: \.self) { line in
                    StatusText(line)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            // #25 B9: the system padding between the left text and the rows (Storage and iCloud: the text almost touched the
            // list). No number: the platform default.
            .padding(.trailing)
            content
                .frame(maxWidth: .infinity)
        }
    }
}

/// #25 B3: a system `Toggle` whose label stays on one line at every text size (rule S1): `FittingText` shrinks it to fit
/// within the readable minimum instead of wrapping it to a second line. The spoken label is the full title.
struct SettingToggle: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) { FittingText(title) }
            .accessibilityLabel(title)
    }
}

/// #25 B3: a system `LabeledContent` row whose label and value each stay on one line (rule S1). The run on 1fe5d50 showed
/// the value "Kept by iCloud Sync" wrapping at Larger Text (92); values are short, longer wording goes in the footer.
struct ValueRow: View {
    let title: String
    let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        LabeledContent {
            FittingText(value)
        } label: {
            FittingText(title)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}
