import SwiftUI
import AVKit
import AppLogic

/// Hosts the system player. Nothing is drawn by the app except the optional Playback Stats overlay and picture subtitles.
struct PlayerHost: UIViewControllerRepresentable {
    let resolved: ResolvedPlayback
    let itemID: Int64
    let services: AppServices
    var onExit: () -> Void
    /// Called when the player item fails after it was handed over; the screen shows the reason.
    var onFailure: (PlaybackFailure) -> Void = { _ in }

    func makeCoordinator() -> PlayerCoordinator {
        let coordinator = PlayerCoordinator(resolved: resolved, itemID: itemID, services: services)
        coordinator.onFailure = onFailure
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
