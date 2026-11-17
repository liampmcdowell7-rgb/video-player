import SwiftUI
import AppLogic

/// Resolves what to play, then hands it to the system player. Shows why, and what to do, when a title cannot be played.
/// Nothing fails silently: every error path ends in the `.failed` state.
struct PlayerScreen: View {
    let request: PlayRequest
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading

    enum Phase {
        case loading
        case ready(ResolvedPlayback)
        case failed(PlaybackFailure)
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
                           phase = .failed(failure)
                       })
                // design-lint:allow the system player draws its own safe areas; the video fills the whole screen
                .ignoresSafeArea()
        case .failed(let failure):
            ContentUnavailableView {
                Label(PlaybackFailure.title, systemImage: "play.slash")
            } description: {
                Text(failure.message)
                if !failure.advice.isEmpty { Text(failure.advice) }
            } actions: {
                Button("Done") { dismiss() }
            }
        }
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
            if failure.isSilentByDesign { dismiss() } else { phase = .failed(failure) }
        }
    }
}
