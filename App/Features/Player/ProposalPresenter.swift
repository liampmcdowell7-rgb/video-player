import AVKit
import UIKit
import AppLogic

/// Presents the next episode through the system's content proposal (the Up Next card of the system player). The
/// player delegate reports Play Now and Cancel back to `handler`.
final class ProposalPresenter: UpNextProposalPresenting, @unchecked Sendable {
    weak var handler: (any UpNextProposalHandler)?
    @MainActor weak var item: AVPlayerItem?

    func present(_ proposal: UpNextProposal) {
        Task { @MainActor [weak self] in
            guard let item = self?.item else { return }
            let content = AVContentProposal(contentTimeForTransition: item.currentTime(), title: proposal.episodeTitle, previewImage: nil)
            // The countdown is run by the playback logic from the credits start, so the system's own countdown stays off.
            content.automaticAcceptanceInterval = .nan
            item.nextContentProposal = content
        }
    }

    /// The system card has no text slot for a countdown, so there is nothing to update.
    func updateCountdown(seconds: Int?) {}

    func dismiss() {
        Task { @MainActor [weak self] in
            self?.item?.nextContentProposal = nil
        }
    }
}
