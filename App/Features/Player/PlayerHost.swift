import SwiftUI
import AVKit
import AppLogic

/// Hosts the system player. Nothing is drawn by the app over the picture except picture subtitles (R340: Playback Stats is
/// an info panel tab now).
struct PlayerHost: UIViewControllerRepresentable {
    let resolved: ResolvedPlayback
    let itemID: Int64
    let services: AppServices
    var onExit: () -> Void
    /// Called when the player item fails after it was handed over; the screen shows the reason.
    var onFailure: (PlaybackFailure) -> Void = { _ in }
    /// R340: play another item in place of this one (Up Next, the Episodes tab).
    var onPlayItem: (Int64) -> Void = { _ in }

    func makeCoordinator() -> PlayerCoordinator {
        let coordinator = PlayerCoordinator(resolved: resolved, itemID: itemID, services: services)
        coordinator.onFailure = onFailure
        coordinator.onPlayItem = onPlayItem
        return coordinator
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        context.coordinator.attach(to: controller)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: PlayerCoordinator) {
        coordinator.stop()
    }
}
