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
    @State private var reading = false
    @State private var readCount: Int?

    enum Entry: Equatable { case unlock, create, confirm(String) }

    private var scale: RatingScale { RatingScale.forRegion(services.online.region) }

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
                Text(ParentalText.unratedFooter)
            }
            Section {
                TaskButtonRow {
                    TaskButton(reading ? "Reading Ratings" : "Read Ratings") { readRatings() }
                        .disabled(reading)
                }
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
        reading = true
        Task {
            readCount = await services.online.readRatings()
            reading = false
            await services.setParental(settings)
        }
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
        controller.entryCompletionHandler = { digits in
            if let digits { onComplete(digits) }
        }
        context.coordinator.cleared = clearCount
        return controller
    }

    func updateUIViewController(_ controller: TVDigitEntryViewController, context: Context) {
        controller.titleText = title
        controller.promptText = prompt
        controller.entryCompletionHandler = { digits in
            if let digits { onComplete(digits) }
        }
        if context.coordinator.cleared != clearCount {
            context.coordinator.cleared = clearCount
            controller.clearEntry(animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { var cleared = 0 }
}
