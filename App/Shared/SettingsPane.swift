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
        // #33 K (OPEN_QUESTIONS R240, PROVISIONAL target 4.5:1): Settings' secondary text in the primary system colour. The run
        // of 20 Nov measured the footer at 2.77:1 and the summary at 4.35:1 (31-settings-playback, scripts: ScreenChecks
        // Contrast). Whether the system section footers take this style is unverified until the next 31 -CONTRAST note.
        PaneColumns(title: title, summary: summary, status: status, summaryStyle: .primary) {
            Form { content }
                .foregroundStyle(.primary)
        }
        .navigationTitle(title)
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
}

/// #25 B1 (OPEN_QUESTIONS R202, PROVISIONAL): a sheet's page as ONE column, full height: the title on top, one sentence under
/// it, then the rows in a system `Form`. Used by File Details. (#30: Add a Source and its forms are no longer sheets; they
/// use `TaskPage`.) The navigation bar stays hidden (rule D1), so the title is drawn once, here.
struct SheetColumn<Content: View>: View {
    let title: String
    var summary: String? = nil
    @ViewBuilder var content: Content

    /// #30 B: the same layout as every task screen (one shared layout, so none can drift).
    var body: some View {
        TaskPage(title: title, summary: summary) { content }
    }
}

/// #30 (OPEN_QUESTIONS R228, PROVISIONAL): the column sizes of a full-screen task page. Fractions of the space the system
/// gives the page (inside the tvOS safe area), not points: the HIG Layout page gives the safe area (60 pt top and bottom,
/// 80 pt at the sides) but no form width, so these are our choice and are listed with their alternatives in R228.
enum TaskPageLayout {
    /// The rows sit in one bounded column (rule L1, owner decision R202), centred, two thirds of the width.
    static let columnFraction: CGFloat = 2.0 / 3.0
    /// Every text field takes the same share of its row, so fields side by side in the column line up at one width (HIG
    /// Text fields: "use consistent widths"; the equal-size rule). The label has the rest of the row.
    static let fieldFraction: CGFloat = 0.5
}

/// #30 (OPEN_QUESTIONS R228, PROVISIONAL): a FULL-SCREEN page for a task (Add a Source and each source form): one bounded
/// column with the title and its one sentence at the top, then the rows of a system grouped `Form`.
/// - The title and sentence are the header of the first section, so the system gives them the same inner margin as the
///   row text below them (#30 B: in the sheet they started at the card's rounded edge). Unverified on tvOS 27 until the
///   next screenshots (10 to 19).
/// - They scroll with the rows, so at Larger Text the rows get the whole screen height (#30 E).
/// - The system scroll edge effect at both ends shows that more rows are above or below (#30 D; tvOS 26 and later).
/// - The navigation bar stays hidden (rule D1): the title is drawn once, here.
struct TaskPage<Content: View>: View {
    let title: String
    var summary: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            Section {
                EmptyView()
            } header: {
                TaskPageHeader(title: title, summary: summary)
            }
            content
        }
        .containerRelativeFrame(.horizontal) { (length: CGFloat, _: Axis) -> CGFloat in
            length * TaskPageLayout.columnFraction
        }
        .frame(maxWidth: .infinity)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .navigationTitle(title)
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
}

extension View {
    /// #30 B (OPEN_QUESTIONS R228, PROVISIONAL): the ONE way the app presents a task screen (Add a Source, File Details,
    /// Save View, Fix Match, How This Was Sorted, the Move choice): a full-screen cover, so no tab bar is on top and nothing
    /// shows behind it, with the UI-test text-size and Bold Text overrides applied inside (a presented view is outside the
    /// tab content that carries them, App/Shell/RootView.swift). scripts/design-lint.sh rule `form-sheet` fails on `.sheet(`.
    ///
    /// #33 A: the run of 20 Nov showed every cover SEE-THROUGH (10 to 19, 21, 59, 66, 67, 74): the cover was above the tab
    /// bar and full width (notes 10-add-source-types-HIERARCHY, 11-form-webdav-PRESENTATION), but drew no background, so the
    /// page and the tab bar showed through. `TaskCoverChrome` gives every cover, here in one place:
    /// - an opaque system background over the whole presentation: `presentationBackground(_:)` with the `background` style
    ///   ("Automatically fills the entire presentation"; tvOS 16.4+);
    /// - the modal accessibility trait (`AccessibilityTraits.isModal`: "sibling accessibility elements that are not modal are
    ///   ignored"), and it hides the app's tabs from accessibility while it is open (`CoverPresence`, RootView).
    func taskCover<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        fullScreenCover(isPresented: isPresented) {
            content()
                .modifier(TaskCoverChrome())
        }
    }

    /// `taskCover` for an item: shown while `item` is not nil.
    func taskCover<Item: Identifiable, Content: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        fullScreenCover(item: item) { (value: Item) in
            content(value)
                .modifier(TaskCoverChrome())
        }
    }
}

/// #33 A and B (2): what every task cover gets (`taskCover`). The background is the system's `background` shape style, not a
/// colour of ours (system colours only, docs/DESIGN_SYSTEM.md).
struct TaskCoverChrome: ViewModifier {
    @Environment(CoverPresence.self) private var presence: CoverPresence?

    func body(content: Content) -> some View {
        content
            .uiTestAccessibilityOverrides()
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            // #34 2: the cover's own root also draws the system background, full bleed, so the cover is opaque even if
            // tvOS ignores `presentationBackground` on a full-screen cover (its page speaks of "the enclosing sheet").
            // This is the pattern of Apple's `fullScreenCover(isPresented:onDismiss:content:)` example (a full-frame
            // background that ignores the safe area); `background(_:ignoresSafeAreaEdges:)` ignores all edges by default.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BackgroundStyle(), ignoresSafeAreaEdges: .all)
            .presentationBackground(.background)
            .onAppear { presence?.opened() }
            .onDisappear { presence?.closed() }
    }
}

/// #33 B (2): how many task covers are open. RootView hides its tabs (and with them the page under a cover) from
/// accessibility while one is, so VoiceOver and the UI tests see only the cover: HIG Modality, a modal view "prevents
/// interaction with the parent view".
@MainActor @Observable
final class CoverPresence {
    private(set) var openCovers: Int = 0

    var isCovered: Bool { openCovers > 0 }

    func opened() { openCovers += 1 }

    func closed() { openCovers = max(0, openCovers - 1) }
}

/// The title (one line, rule S1) and the one sentence of a `TaskPage`, in the system section-header position. The sentence
/// may wrap: it is a sentence, not a short text.
private struct TaskPageHeader: View {
    let title: String
    let summary: String?

    var body: some View {
        VStack(alignment: .leading) {
            FittingText(title, style: .title2)
                .accessibilityAddTraits(.isHeader)
            if let summary {
                Text(summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textCase(nil)
    }
}

/// The two columns of `SettingsPane` without the `Form`: the title (when the screen has none of its own) and the summary on
/// the left, any rows (a `List`) in the right half. #15 7.1: the Files screens use it, so their rows sit in a bounded column
/// like the Settings rows (L1, L2). Fixed in code, verify in next screenshots.
struct PaneColumns<Content: View>: View {
    var title: String? = nil
    let summary: String
    var status: [String] = []
    /// #33 K: Settings passes `.primary` (R240); the Files screens keep the system's secondary style.
    var summaryStyle: HierarchicalShapeStyle = .secondary
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
                    .foregroundStyle(summaryStyle)
                // #30 Part 3 (35-38): each status sentence is its own paragraph, with the system padding above it, so the
                // left column is not one block of sentences. Wording unchanged. Fixed in code, verify in next 35 to 38.
                ForEach(status.filter { !$0.isEmpty }, id: \.self) { line in
                    StatusText(line)
                        .padding(.top)
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
