import SwiftUI
import AppLogic

/// Resolves what to play, then hands it to the system player. Nothing fails silently: every error path closes the player
/// and hands the reason to `AppServices.playFailure`, which RootView shows as a system alert over the unchanged page (#15 8.1).
struct PlayerScreen: View {
    let request: PlayRequest
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading

    enum Phase {
        case loading
        case ready(ResolvedPlayback)
    }

    var body: some View {
        switch phase {
        case .loading:
            LoadingView()
                .task { await resolve() }
        case .ready(let resolved):
            PlayerHost(resolved: resolved, itemID: request.itemID, services: services,
                       onExit: { dismiss() },
                       onFailure: { failure in
                           // The player stopped by itself (a stream the decoder rejected): the reason replaces the black screen.
                           resolved.remux?.stop()
                           fail(failure)
                       })
                // design-lint:allow the system player draws its own safe areas; the video fills the whole screen
                .ignoresSafeArea()
        }
    }

    /// Closes the player and leaves the reason for the alert on the page underneath.
    private func fail(_ failure: PlaybackFailure) {
        if !failure.isSilentByDesign { services.playFailure = PlayFailurePrompt(failure: failure, request: request) }
        dismiss()
    }

    private func resolve() async {
        do {
            let resolved = try await services.resolvePlayback(itemID: request.itemID, fromStart: request.fromStart)
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
