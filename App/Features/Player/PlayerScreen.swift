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

    private var current: PlayRequest { playing ?? request }

    /// UI test 22 reads the running step from the spinner (R311).
    static let loadingIdentifier = "player.loading"
    static let playerIdentifier = "player.screen"

    enum Phase {
        case loading
        case ready(ResolvedPlayback)
        case failed(PlaybackFailure)
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
                Text(failure.text)
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
                       onFailure: { failure, detail in
                           // The player stopped by itself (a stream the decoder rejected, a step past its limit): the reason
                           // replaces the black screen.
                           resolved.remux?.stop()
                           fail(failure, detail: detail)
                       },
                       onPlayItem: { next in
                           // R340: this player is taken down (its coordinator stops: position saved, watch sync told),
                           // then the next item is resolved and played.
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
        }
    }

    private var failure: PlaybackFailure? {
        if case .failed(let failure) = phase { return failure }
        return nil
    }

    /// Keeps the problem for Settings > Playback and shows the reason here (never a silent close while the screen is up).
    private func fail(_ failure: PlaybackFailure, detail: String? = nil) {
        PlaybackProblemLog.save(start.tracker.problem(failure, detail: detail))
        guard PlaybackFailurePolicy.shows(failure, screenClosed: closed) else { return }
        phase = .failed(failure)
    }

    private func tryAgain() {
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
            fail(PlaybackFailureMapper.failure(for: error), detail: Self.detail(of: error))
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
