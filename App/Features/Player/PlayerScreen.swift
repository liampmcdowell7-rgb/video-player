import SwiftUI
import AppLogic

/// Resolves the item, then hands the system player the URL. A failure is a system alert with the reason, "Try Again" (when
/// trying again can help) and "Done", which closes the player.
///
/// R311 (owner's device test of build 5, 21 Nov 2026: a black player for about 30 seconds, then the page again with no
/// message; the CI run of the same commit stopped the same way with the sample clip):
///  - the alert is presented by this screen, inside the player cover. Before, the reason was handed to the page underneath
///    (`services.playFailure`) in the same update that closed the cover, and an alert cannot come up while a cover is still
///    on screen or closing, so it never showed;
///  - every failure is shown while this screen is up, `.cancelled` included (`PlaybackFailurePolicy`);
///  - each step of the start has a time limit (`PlaybackStartWatch` here, the player's own steps in `PlayerCoordinator`),
///    so a step that hangs ends with a message naming it instead of a black screen;
///  - the problem is kept for Settings > Playback > Last Playback Problem (`PlaybackProblemLog`), tokens removed.
struct PlayerScreen: View {
    let request: PlayRequest
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading
    /// R340: the item playing now; Up Next and the Episodes tab replace it (the next one resumes at its saved position).
    @State private var playing: PlayRequest?
    /// R311: the steps of the start that is running (a new one for each start).
    @State private var start = PlayerStartModel()
    /// Set when the screen went away; nothing is shown after that.
    @State private var closed = false
    /// R386: the problem behind the alert, whose lines (error domain and code, underlying errors, last event) the alert shows.
    @State private var problem: PlaybackProblem?
    /// R458: episodes that followed each other on their own, and the one waiting for "Are you still watching?".
    @State private var run = EpisodeRun()
    @State private var waitingFor: Int64?
    @AppStorage(AppPreference.inactivityCheck.rawValue) private var inactivityRaw = InactivityCheck.default.rawValue

    private var current: PlayRequest { playing ?? request }

    /// UI test 22 reads the running step from the spinner (R311).
    static let loadingIdentifier = "player.loading"
    static let playerIdentifier = "player.screen"

    enum Phase {
        case loading
        case ready(ResolvedPlayback)
        case failed(PlaybackFailure)
        /// R458: the inactivity prompt is up; nothing plays until Select.
        case asking
    }

    var body: some View {
        content
            .alert(failure?.alertTitle ?? PlaybackFailure.title,
                   isPresented: Binding(get: { failure != nil }, set: { _ in }),
                   presenting: failure) { failure in
                if failure.canTryAgain {
                    Button("Try Again") { tryAgain() }
                }
                Button("Done", role: .cancel) { dismiss() }
            } message: { failure in
                // R395 (item 11 of the owner's review of the run on fd9731f): the alert shows the sentence, the Result
                // line and the Step line only (`PlaybackProblem.alertLines`); 14 checkpoint lines filled it before.
                // Everything else (R386's error lines, R390's checkpoints) is in Settings >
                // Playback > Full Problem Report, where the problem is kept (`PlaybackProblemLog`).
                // R313: an episode's alert still starts with which episode it was ("Show · S1, E3 · Name").
                let lines: String? = problem.map { $0.alertLines().joined(separator: "\n") }
                Text([start.tracker.itemLine, failure.text, lines].compactMap { $0 }.joined(separator: "\n\n"))
            }
            .alert(InactivityCheck.question, isPresented: Binding(get: { waitingFor != nil }, set: { _ in })) {
                Button("Continue") { continueAfterPrompt() }
                Button("Done", role: .cancel) { dismiss() }
            }
            .onDisappear { closed = true }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            LoadingView()
                .accessibilityIdentifier(Self.loadingIdentifier)
                .accessibilityValue(start.stepTitle)
                .task(id: current.id) { await resolve() }
        case .ready(let resolved):
            PlayerHost(resolved: resolved, itemID: current.itemID, services: services, tracker: start.tracker,
                       onExit: { dismiss() },
                       onFailure: { failure, diagnostics in
                           // The player stopped by itself (a stream the decoder rejected, a step past its limit): the reason
                           // replaces the black screen.
                           resolved.remux?.stop()
                           fail(failure, diagnostics: diagnostics)
                       },
                       onPlayItem: { next, byPerson in
                           // R340: this player is taken down (its coordinator stops: position saved, watch sync told),
                           // then the next item is resolved and played.
                           // R458: an episode that followed on its own counts toward Inactivity Check; a pick by hand starts over.
                           if byPerson { run.personActed() } else { run.episodeFinishedOnItsOwn() }
                           let check = InactivityCheck(rawValue: inactivityRaw) ?? .off
                           if !byPerson, check.asks(episodesInARow: run.count) {
                               waitingFor = next
                               phase = .asking
                               return
                           }
                           playing = PlayRequest(itemID: next, fromStart: false)
                           phase = .loading
                       })
                .id(current.id)
                // R311: UI test 22 tells "the player is up" from "the player closed" by this.
                .accessibilityIdentifier(Self.playerIdentifier)
                // design-lint:allow the system player draws its own safe areas; the video fills the whole screen
                .ignoresSafeArea()
        case .failed:
            // The player is gone (its coordinator stopped); the alert above says why.
            Color.clear
        case .asking:
            // The alert above asks; the player behind it is already closed.
            Color.clear
        }
    }

    /// R458: Select on "Are you still watching?" starts the next episode and the count begins again.
    private func continueAfterPrompt() {
        guard let next = waitingFor else { return }
        waitingFor = nil
        run.personActed()
        playing = PlayRequest(itemID: next, fromStart: false)
        phase = .loading
    }

    private var failure: PlaybackFailure? {
        if case .failed(let failure) = phase { return failure }
        return nil
    }

    /// Keeps the problem for Settings > Playback and shows the reason here (never a silent close while the screen is up).
    private func fail(_ failure: PlaybackFailure, diagnostics: PlaybackDiagnostics = PlaybackDiagnostics()) {
        let kept = start.tracker.problem(failure, diagnostics: diagnostics)
        PlaybackProblemLog.save(kept)
        guard PlaybackFailurePolicy.shows(failure, screenClosed: closed) else { return }
        problem = kept
        phase = .failed(failure)
    }

    private func tryAgain() {
        problem = nil
        playing = PlayRequest(itemID: current.itemID, fromStart: current.fromStart)
        phase = .loading
    }

    private func resolve() async {
        let model = PlayerStartModel()
        start = model
        let tracker = model.tracker
        let services = self.services
        let request = current
        let outcome = await PlaybackStartWatch.run(
            tracker: tracker,
            onTick: { step in await model.show(step) },
            // A file opened after the limit was reported is closed again.
            onLate: { resolved in await MainActor.run { resolved.remux?.stop() } }
        ) {
            try await services.resolvePlayback(itemID: request.itemID, fromStart: request.fromStart, tracker: tracker)
        }
        switch outcome {
        case .finished(let resolved):
            if Task.isCancelled || closed {
                // The screen went away while the file was opening: close what was started (and keep why).
                resolved.remux?.stop()
                return
            }
            tracker.enter(.openPlayer)
            phase = .ready(resolved)
        case .failed(let error):
            // R386: an error of the system or a source (not one of the app's plain failures) is shown with its domain,
            // code and underlying errors too.
            let plain = error is PlaybackFailure || error is PlaybackError
            fail(PlaybackFailureMapper.failure(for: error),
                 diagnostics: PlaybackDiagnostics(detail: Self.detail(of: error), player: plain ? nil : PlayerErrorReport(error as NSError)))
        case .overdue(let step, let seconds):
            fail(PlaybackFailures.startTimedOut(step, seconds: seconds))
        }
    }

    /// The error's own words for the diagnostic row, when it is not one of the app's plain failures.
    static func detail(of error: Error) -> String? {
        if error is PlaybackFailure || error is PlaybackError { return nil }
        let ns = error as NSError
        return "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
    }
}

/// R311: the start that is running, for the spinner's step (UI test 22) and the time limits.
@MainActor
@Observable
final class PlayerStartModel {
    let tracker = PlaybackStartTracker()
    private(set) var stepTitle = PlaybackStep.findFile.title

    func show(_ step: PlaybackStep) { stepTitle = step.title }
}
