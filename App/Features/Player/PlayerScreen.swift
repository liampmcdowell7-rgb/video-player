import SwiftUI
import AppLogic

/// Resolves what to play, then hands it to the system player. Nothing fails silently: every error path closes the player
/// and hands the reason to `AppServices.playFailure`, which RootView shows as a system alert over the unchanged page (#15 8.1).
struct PlayerScreen: View {
    let request: PlayRequest
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading
    /// R340: the item playing now; Up Next and the Episodes tab replace it (the next one resumes at its saved position).
    @State private var playing: PlayRequest?

    private var current: PlayRequest { playing ?? request }

    enum Phase {
        case loading
        case ready(ResolvedPlayback)
    }

    var body: some View {
        switch phase {
        case .loading:
            LoadingView()
                .task(id: current.id) { await resolve() }
        case .ready(let resolved):
            PlayerHost(resolved: resolved, itemID: current.itemID, services: services,
                       onExit: { dismiss() },
                       onFailure: { failure in
                           // The player stopped by itself (a stream the decoder rejected): the reason replaces the black screen.
                           resolved.remux?.stop()
                           fail(failure)
                       },
                       onPlayItem: { next in
                           // R340: this player is taken down (its coordinator stops: position saved, watch sync told),
                           // then the next item is resolved and played.
                           playing = PlayRequest(itemID: next, fromStart: false)
                           phase = .loading
                       })
                .id(current.id)
                // design-lint:allow the system player draws its own safe areas; the video fills the whole screen
                .ignoresSafeArea()
        }
    }

    /// Closes the player and leaves the reason for the alert on the page underneath.
    private func fail(_ failure: PlaybackFailure) {
        if !failure.isSilentByDesign { services.playFailure = PlayFailurePrompt(failure: failure, request: current) }
        dismiss()
    }

    private func resolve() async {
        do {
            let resolved = try await services.resolvePlayback(itemID: current.itemID, fromStart: current.fromStart)
            if Task.isCancelled {
                // The screen went away while the file was opening: close what was started.
                resolved.remux?.stop()
                return
            }
            phase = .ready(resolved)
        } catch {
            let failure = PlaybackFailureMapper.failure(for: error)
            fail(failure)
        }
    }
}
