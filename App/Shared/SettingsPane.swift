import SwiftUI
import AppLogic

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
        // #33 K / #34 5b (OPEN_QUESTIONS R240, PROVISIONAL target 4.5:1): Settings' secondary text (the summary, and the
        // secondary level of the Form, which the section footers are expected to use) is the primary system colour at
        // `ReadableSecondary.opacity`, not full primary, so it stays below the row titles. The run of 20 Nov measured the
        // footer at 2.77:1 and the summary at 4.35:1 in .secondary (31-settings-playback). Whether the system footers take
        // the Form's secondary level is unverified until the next 31 -CONTRAST note.
        PaneColumns(title: title, summary: summary, status: status, summaryStyle: ReadableSecondary.style) {
            Form { content }
                .foregroundStyle(HierarchicalShapeStyle.primary, ReadableSecondary.style)
                // R345 (compile run of 21 Nov 2026): the system focus effect grows the focused row a few points past the
                // Form's edge, and the Form clipped it to its bounds: every focused Settings row was cut flat on the left
                // at x 990, the left edge of this column (31 to 38, 41, 64, 69, 109). `scrollClipDisabled()` (tvOS 17.0+:
                // "Sets whether a scroll view clips its content to its bounds") lets the system draw the whole row.
                // Whether a Form (a List underneath) honours it on tvOS 27 is UNVERIFIED until the -FOCUS-CLIPPED check
                // of the next run.
                .scrollClipDisabled()
        }
        .navigationTitle(title)
        .toolbarVisibility(.hidden, for: .navigationBar)
        // R400: the cover's dark grey, inside its navigation stack (How This Was Sorted, Move).
        .taskCoverPageBackground()
        // R407 (A11Y1): the UI-test overrides on the page itself, which is pushed (every Settings page) or inside a
        // cover's navigation stack (see RouteDestinations).
        .uiTestAccessibilityOverrides()
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
/// #36 S-B (OPEN_QUESTIONS R254, PROVISIONAL): the ONE layout of every task cover: Add a Source, the source forms, Your
/// Network, File Details, Save View, Fix Match, the Move choice and How This Was Sorted. (Save View and Fix Match had a
/// centred navigation title; Move and How This Was Sorted had `SettingsPane`'s two columns.)
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
        // R345: room for the focus effect, as SettingsPane (the task pages' rows were whole in the run, 10 to 19; one
        // rule for every Form).
        .scrollClipDisabled()
        // R346 (item A): the scrolling page is one focus region, so Up scrolls back to its first row before it
        // can leave for the tab bar (reason and UNVERIFIED cause: PaneColumns, App/Shared/SettingsPane.swift).
        .focusSection()
        // #36 S-A (OPEN_QUESTIONS R253, PROVISIONAL): the same two hierarchical levels as `SettingsPane`'s Form. Why the
        // header was dim here and bright on Move: the title and sentence sit in this Form's first SECTION HEADER, which
        // the system draws in the Form's dimmed header level when the Form sets no levels of its own (run of 20 Nov: title
        // #4C4C4C, 2.45:1; the sentence, `.secondary` on top of that, #262626, 1.39:1; the other section headers 2.45:1).
        // `SettingsPane` (Move, How This Was Sorted) sets primary and `ReadableSecondary` on its Form (#34 5b), so its
        // section headers are white (66: EPISODE 21:1), and its title is outside the Form. One line, here, gives every
        // TaskPage (Add a Source, the forms, Your Network, File Details) the same levels.
        .foregroundStyle(HierarchicalShapeStyle.primary, ReadableSecondary.style)
        .containerRelativeFrame(.horizontal) { (length: CGFloat, _: Axis) -> CGFloat in
            length * TaskPageLayout.columnFraction
        }
        .frame(maxWidth: .infinity)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .navigationTitle(title)
        .toolbarVisibility(.hidden, for: .navigationBar)
        // R400: the cover's dark grey, inside its navigation stack (Add a Source, the forms, File Details, Save View,
        // Fix Match).
        .taskCoverPageBackground()
        // R407 (A11Y1): the UI-test overrides on the page itself (pushed inside a cover's navigation stack).
        .uiTestAccessibilityOverrides()
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
    /// - an opaque system background over the whole presentation: the `background` style, full bleed (R362: no longer `presentationBackground(_:)`)
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
    /// Fourth run of 20 Nov 2026 (R273 push): the page was still in the tree under all 30 covers. Every hiding modifier
    /// reads `isCovered`, and the count was handed to the cover through the SwiftUI environment of a view presented by
    /// `fullScreenCover`; if that environment does not reach the presented content on tvOS (not on any Apple page read:
    /// UNVERIFIED), the count never rises and nothing is hidden. The cover now uses the ONE shared counter directly.
    private var presence: CoverPresence? { CoverPresence.shared }

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
            // R397 (PROVISIONAL; docs/AUDIT_VISUAL_TVAPP.md SF8, AS2, HS1: "flat black pages"): the system's regular
            // material over the opaque system background, so a task cover (Add a Source, the source forms, How This Was
            // Sorted, Fix Match, Save View) is the dark grey of a material, not flat black, and still opaque: nothing
            // of the page behind shows through (R362, #33 A). A cover with artwork of its own draws it on top (the
            // synopsis cover, R392). No Apple picture shows these screens (the audit's NO REFERENCE list).
            // R414: the layers are `TaskCoverFill` (why the material alone stayed black: see there).
            .modifier(TaskCoverFill())
            // R362 (compile run of 21 Nov 2026, item 10): no `presentationBackground`. Apple's page for it: a presentation
            // background "Allows views behind the presentation to show through translucent styles", which needs the views
            // behind to stay; the page stayed in the tree under every cover of the run. The opaque full-bleed background
            // above already covers the screen (pixel check B 1 passed under every cover with it in place).
            .onAppear { presence?.opened() }
            .onDisappear { presence?.closed() }
            // #36 group 2: a screen inside the cover is not the page behind it (HiddenUnderTaskCover, RootView).
            .environment(\.isInTaskCover, true)
            .modifier(CoverCountProbe())
    }
}

/// R362 (item 10): a UI-test-only record of the cover counter, read by the -COVER note, so the next run tells the two
/// remaining causes apart: the counter never rose (the cover says "cover probe: open covers 0"), or the page was told to hide and
/// XCTest still lists it (the page says "cover probe: told hidden true"). Nothing in a Release build or a normal launch.
struct CoverCountProbe: ViewModifier {
    private var presence: CoverPresence? { CoverPresence.shared }

    func body(content: Content) -> some View {
        #if DEBUG
        if UITestMode.current != .off {
            content.accessibilityValue("cover probe: open covers \(presence?.openCovers ?? -1)")
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension EnvironmentValues {
    /// #36 group 2: true inside a task cover (TaskCoverChrome), so HiddenUnderTaskCover never hides the cover's own content.
    @Entry var isInTaskCover: Bool = false
}

/// #33 B (2): how many task covers are open. RootView hides its tabs (and with them the page under a cover) from
/// accessibility while one is, so VoiceOver and the UI tests see only the cover: HIG Modality, a modal view "prevents
/// interaction with the parent view".
@MainActor @Observable
final class CoverPresence {
    /// The one counter of the app (R292): RootView, every task cover and every page screen read this same instance.
    static let shared: CoverPresence = CoverPresence()

    /// R378: the counting itself is AppLogic `CoverCount` (Linux tests), unchanged in behaviour.
    private var count = CoverCount()

    var openCovers: Int { count.open }

    var isCovered: Bool { count.isCovered }

    func opened() { count.opened() }

    func closed() { count.closed() }
}

/// The title (one line, rule S1) and the one sentence of a `TaskPage`, in the system section-header position. The sentence
/// may wrap: it is a sentence, not a short text.
private struct TaskPageHeader: View {
    let title: String
    let summary: String?

    var body: some View {
        VStack(alignment: .leading) {
            // #36 S-A: the levels of the Form (TaskPage), named here so the header cannot fall back to a dimmer one.
            FittingText(title, style: .title2)
                .foregroundStyle(HierarchicalShapeStyle.primary)
                .accessibilityAddTraits(.isHeader)
            if let summary {
                Text(summary)
                    .font(.body)
                    .foregroundStyle(ReadableSecondary.style)
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
    /// #33 K / #34 5b: Settings passes `ReadableSecondary.style` (R240); the Files screens keep the system's secondary style.
    var summaryStyle: AnyShapeStyle = AnyShapeStyle(HierarchicalShapeStyle.secondary)
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
            // R345: the right column's List or Form must not clip its focused row (Files 71 to 73, Settings 31 to 38).
            content
                .scrollClipDisabled()
                // R346 (owner's device test of build 5, item A): Up from a lower row jumped to the tab bar once the focus reached
                // the top of the visible area, before the page was back at its first row. `focusSection()` (tvOS 15.0+: "the view's
                // frame and cohort of focusable descendants should be used to guide focus movement") makes the scrolling column one
                // focus region, so the focus engine searches it, rows above the visible area included, before leaving it. That this
                // is the cause is UNVERIFIED (no Apple page says why the jump happens); the -SCROLL-UP notes of the next run prove it.
                .focusSection()
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

/// R389: the identifier of the last row of a Settings page whose last rows are read-only, for the UI test that moves the
/// focus there.
enum SettingsRowID {
    static let last = "settings.lastRow"
}

extension View {
    /// #24 C, R389: a read-only row the Siri Remote can move to. On tvOS a Form scrolls only by moving the focus, so rows
    /// below the last control were out of reach (About before #24 C; Settings > Playback's Last Playback Problem and
    /// Library's counts before R389). Each such row takes the system focus, so the focus moves row by row and the system
    /// scrolls the list to keep the focused row visible. Was private to About; shared by R389.
    func readableRow() -> some View {
        // design-lint:allow a read-only Settings row takes the system focus so the Siri Remote can reach it and the list scrolls to it (#24 C, R389)
        self.focusable()
    }
}

/// R400 (owner's review of the run on f0a67d3, item 1; PROVISIONAL): the dark grey of a task cover, drawn by the PAGE inside
/// the cover's `NavigationStack`, not around the stack. Cause of the flat black covers (10 to 21, 93, 94, 99, 100, 110, 111):
/// R397 put the material on the cover's root (`TaskCoverChrome`), which is OUTSIDE the `NavigationStack` that every cover
/// holds (SourceSetupFlow, FixMatchView, SaveViewSheet, SortMoveSheet, FileDetailsSheet). The stack and the pages it shows
/// are above that root, so whatever they draw (the stack's own container, the `Form`'s scroll background) hid the material
/// completely; the run shows no change at all, which fits an opaque layer above it. Which of those layers is the opaque
/// one is NOT on an Apple page (UNVERIFIED). The page draws the material over the system background itself, full bleed.
/// R412 (compile check run #26 on a10f582: "'scrollContentBackground' is unavailable in tvOS"): the page no longer hides
/// its `Form`'s scroll background; Apple's page for `scrollContentBackground(_:)` lists iOS, iPadOS, Mac Catalyst, macOS,
/// visionOS and watchOS, no tvOS. Whether a tvOS `Form` draws an opaque background of its own is on no Apple page read
/// (the `Form` page describes iOS and macOS only): UNVERIFIED, the next run's pictures decide. If it does, it hides this
/// material and the covers stay black.
/// R414 (run #27): the material is not hidden by anything; it has nothing but black to blur (see `TaskCoverFill`).
/// Only inside a task cover (`isInTaskCover`); a tab's own pages keep the system's background.
struct TaskCoverPageBackground: ViewModifier {
    @Environment(\.isInTaskCover) private var isInTaskCover: Bool

    func body(content: Content) -> some View {
        if isInTaskCover {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .modifier(TaskCoverFill())
        } else {
            content
        }
    }
}

/// R414 (run #27, all 26 -COVER notes: "cover background #000000 (most common colour of the four corners)"; R397, R400
/// and R412 changed nothing; PROVISIONAL): the layers of a task cover, from the top.
///
/// Cause, from Apple's `Material` page (https://developer.apple.com/documentation/swiftui/material, tvOS 15.0+): "adding a
/// material is like inserting a translucent layer between the modified view and its background"; it blurs "a background
/// that's part of your app". R397 and R400 put the material directly on `BackgroundStyle()`, which is black in the dark
/// appearance, so it had only black to blur and the corners stayed #000000. Nothing drew black over it: at the corners
/// the page's own background is the top layer (TaskPage's `Form` is a centred column; its frame does not reach them), so
/// neither the cover's presentation, the navigation stack's container nor the `Form` is the cause. That fits both runs
/// showing exactly the same black whether the material was outside the stack (R397) or inside it (R400). The tabs are grey
/// because something of the system's sidebar-adaptable tab view draws there (the app draws no background on Settings or
/// Files); a full-screen cover is presented outside the tab view, so it does not get that grey (which layer of the tab
/// view it is: not on an Apple page read, UNVERIFIED).
///
/// Fix: a second, opaque level of the system background under the material: `BackgroundStyle` (tvOS 14.0+,
/// https://developer.apple.com/documentation/swiftui/backgroundstyle) with `secondary` ("Returns the second level of this
/// shape style", tvOS 17.0+, https://developer.apple.com/documentation/swiftui/shapestyle/secondary-swift.property), over
/// the plain background so the cover stays opaque even if that level is translucent. System styles only, no colour of
/// ours. What the second level of the background looks like on tvOS is on no Apple page read (UNVERIFIED): if the next
/// run still measures #000000, it is black there too. `UIColor.secondarySystemBackground` would be the obvious grey, but
/// its page lists no tvOS (iOS, iPadOS, Mac Catalyst, visionOS): TvOSAvailabilityTests now catches it.
struct TaskCoverFill: ViewModifier {
    func body(content: Content) -> some View {
        content
            // design-lint:allow R397: the system regular material as a task cover's background, over the opaque system background; a standard material, no colour of ours
            .background(.regularMaterial, ignoresSafeAreaEdges: .all)
            // design-lint:allow R414: the second level of the system background, so the material has a grey (not black) to blur; a system style, no colour of ours
            .background(BackgroundStyle().secondary, ignoresSafeAreaEdges: .all)
            .background(BackgroundStyle(), ignoresSafeAreaEdges: .all)
    }
}

extension View {
    /// R400: see `TaskCoverPageBackground`.
    func taskCoverPageBackground() -> some View {
        modifier(TaskCoverPageBackground())
    }
}
