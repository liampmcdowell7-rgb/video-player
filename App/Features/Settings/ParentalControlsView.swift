import SwiftUI
import TVUIKit
import AppLogic

/// Settings > Parental Controls (R459, PROVISIONAL, NEVER COMPILED). Restrictions (off), Change Passcode, Allowed Movie
/// Ratings, Allowed TV Show Ratings (the Region setting's rating system) and Allow Unrated. While Restrictions are on, titles
/// above the allowed ratings are not shown anywhere (the library's one rule), and Discover is off. A passcode that is set is
/// asked for before this page opens. The digits are entered in the system's digit entry view, hidden as typed (HIG "Entering
/// data": a secure entry for sensitive data; tvOS: `TVDigitEntryViewController.isSecureDigitEntry`).
/// Search Lock and Require PIN are not here: with titles hidden there is no locked title to open or play, so neither has
/// anything to govern (OPEN_QUESTIONS R459).
struct ParentalControlsView: View {
    @Environment(AppServices.self) private var services
    @State private var settings = ParentalKeys.read()
    @State private var entry: Entry?
    @State private var started = false
    @State private var enableAfterCreate = false
    @State private var message: String?
    @State private var clearCount = 0
    @State private var readCount: Int?
    @State private var unrated: Int?

    enum Entry: Equatable { case unlock, create, confirm(String) }

    /// R460: the stored rating system, else the lookup region's (only until one is stored).
    private var scale: RatingScale { settings.scale(region: services.online.region) }

    var body: some View {
        Group {
            if let entry {
                PINEntryView(title: title(for: entry), prompt: message ?? prompt(for: entry), clearCount: clearCount) { digits in handle(digits, for: entry) }
                    .onExitCommand { if entry != .unlock { cancelEntry() } }
                    .accessibilityIdentifier("parental.entry")
            } else {
                page
            }
        }
        .task {
            guard !started else { return }
            started = true
            if services.parental.isSet { entry = .unlock }
        }
        // R460: the count follows the library (a scan or a reading ends with a new revision).
        .task(id: "\(services.libraryRevision)|\(services.isReadingRatings)") { unrated = await services.unratedTitleCount() }
    }

    // MARK: Page

    private var page: some View {
        SettingsPane(title: ParentalText.title, summary: "Limit what the library shows by age rating.") {
            Section {
                Toggle(isOn: Binding(get: { settings.enabled }, set: { setRestrictions($0) })) { FittingText(ParentalText.restrictions) }
                    .accessibilityLabel(ParentalText.restrictions)
                Button { startCreate(enabling: false) } label: { FittingText("Change Passcode") }
                    .accessibilityIdentifier("parental.changePasscode")
            } footer: {
                Text(ParentalText.footer)
            }
            Section {
                Picker(ParentalText.ratingSystem, selection: Binding(get: { scale.region },
                                                                     set: { settings.scaleRegion = $0; settings.movieTier = nil; settings.episodeTier = nil; save() })) {
                    ForEach(RatingScale.systems, id: \.region) { Text($0.name).tag($0.region) }
                }
                Picker("Allowed Movie Ratings", selection: Binding(get: { settings.movieTier ?? scale.movieDefault },
                                                                   set: { settings.movieTier = $0; save() })) {
                    ForEach(scale.movieTiers, id: \.title) { Text($0.title).tag($0.title) }
                }
                Picker("Allowed TV Show Ratings", selection: Binding(get: { settings.episodeTier ?? scale.episodeDefault },
                                                                     set: { settings.episodeTier = $0; save() })) {
                    ForEach(scale.episodeTiers, id: \.title) { Text($0.title).tag($0.title) }
                }
                SettingToggle("Allow Unrated", isOn: Binding(get: { settings.allowUnrated }, set: { settings.allowUnrated = $0; save() }))
            } footer: {
                Text(ParentalText.systemFooter + " " + ParentalText.unratedFooter)
            }
            Section {
                TaskButtonRow {
                    TaskButton(services.isReadingRatings ? "Reading Ratings" : "Read Ratings") { readRatings() }
                        .disabled(services.isReadingRatings)
                }
                if let unrated { ValueRow(ParentalText.withoutRating, value: String(unrated)).readableRow() }
                if let readCount { ValueRow("Ratings Found", value: String(readCount)).readableRow() }
            } footer: {
                Text("Reads the rating of every title that has none kept yet. This can take a while.")
            }
        }
    }

    // MARK: Actions

    private func save() { Task { await services.setParental(settings) } }

    private func setRestrictions(_ on: Bool) {
        if on, !services.parental.isSet { startCreate(enabling: true); return }
        settings.enabled = on
        save()
    }

    private func startCreate(enabling: Bool) {
        enableAfterCreate = enabling
        message = nil
        clearCount += 1
        entry = .create
    }

    private func cancelEntry() {
        entry = nil
        message = nil
        enableAfterCreate = false
    }

    private func readRatings() {
        Task { readCount = await services.readRatings() }
    }

    private func handle(_ digits: String, for current: Entry) {
        switch current {
        case .unlock:
            switch services.parental.check(digits) {
            case .accepted, .notSet: entry = nil; message = nil
            case .wrong(let left): message = "Wrong passcode. \(left) \(left == 1 ? "try" : "tries") left."; clearCount += 1
            case .locked(let until): message = ParentalText.locked(until: until); clearCount += 1
            }
        case .create:
            message = nil
            clearCount += 1
            entry = .confirm(digits)
        case .confirm(let first):
            guard first == digits else { message = "The passcodes did not match. Try again."; clearCount += 1; entry = .create; return }
            do {
                try services.parental.set(digits)
                if enableAfterCreate { settings.enabled = true; save() }
                cancelEntry()
            } catch {
                message = "The passcode could not be saved."
                clearCount += 1
                entry = .create
            }
        }
    }

    private func title(for entry: Entry) -> String {
        switch entry {
        case .unlock: return "Enter Passcode"
        case .create: return "New Passcode"
        case .confirm: return "Confirm Passcode"
        }
    }

    private func prompt(for entry: Entry) -> String? {
        switch entry {
        case .unlock: return services.parental.lockedUntil().map { ParentalText.locked(until: $0) }
        case .create: return "Four digits. The passcode stays on this device."
        case .confirm: return "Enter the same four digits again."
        }
    }
}

/// The system's digit entry view, hidden as typed. `clearCount` changing clears the boxes (after a wrong entry).
struct PINEntryView: UIViewControllerRepresentable {
    let title: String
    let prompt: String?
    let clearCount: Int
    let onComplete: (String) -> Void

    func makeUIViewController(context: Context) -> TVDigitEntryViewController {
        let controller = TVDigitEntryViewController()
        controller.numberOfDigits = ParentalPIN.length
        controller.isSecureDigitEntry = true
        controller.titleText = title
        controller.promptText = prompt
        // Apple: `var entryCompletionHandler: (String) -> Void` (tvOS 12.0+): the digits are not optional.
        controller.entryCompletionHandler = { digits in onComplete(digits) }
        context.coordinator.cleared = clearCount
        return controller
    }

    func updateUIViewController(_ controller: TVDigitEntryViewController, context: Context) {
        controller.titleText = title
        controller.promptText = prompt
        // Apple: `var entryCompletionHandler: (String) -> Void` (tvOS 12.0+): the digits are not optional.
        controller.entryCompletionHandler = { digits in onComplete(digits) }
        if context.coordinator.cleared != clearCount {
            context.coordinator.cleared = clearCount
            controller.clearEntry(animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { var cleared = 0 }
}
