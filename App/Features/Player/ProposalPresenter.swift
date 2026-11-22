import AVKit
import UIKit
import AppLogic

/// Presents the next episode through the system's content proposal (the Up Next card of the system player). The
/// player delegate reports Play Now and Cancel back to `handler`.
///
/// R340 (owner decision of 21 Nov 2026 in R338, docs/HIG_AUDIT.md T19): the countdown is the system's own. The playback logic
/// runs in Ask mode (it presents and waits, `PlayerSessionFactory.systemUpNextSettings`); with Auto-Play Next Episode on, the
/// proposal's `automaticAcceptanceInterval` makes the system accept `UpNextCard.countdownSeconds` after the card appears
/// (Apple: "The interval between the time playback ends and automatic acceptance"; negative while the credits still run,
/// as Apple's article uses -1.0). Off: NaN, the card waits. Whether the system's acceptance calls the delegate's
/// `didAccept` like a press does: UNVERIFIED until a run.
final class ProposalPresenter: UpNextProposalPresenting, @unchecked Sendable {
    weak var handler: (any UpNextProposalHandler)?
    @MainActor weak var item: AVPlayerItem?
    /// Settings > Playback > Auto-Play Next Episode.
    @MainActor var autoPlay = true
    /// The show's name, for the card's line "Show · S1, E4 · Episode name" (R313).
    @MainActor var seriesTitle: String?
    /// R383: the next episode's still from the artwork cache (no request), nil when none is on hand.
    @MainActor var stillOnHand: (@MainActor (Int64) async -> Data?)?

    func present(_ proposal: UpNextProposal) {
        Task { @MainActor [weak self] in
            guard let self, self.item != nil else { return }
            // R313: the system card shows "Up Next" above this line.
            let title: String = PlayerEpisodeText.upNextLine(proposal, show: self.seriesTitle)
            // R383 (audit #11): Apple's previewImage page asks for "a frame from the proposed video, not the poster
            // artwork", so only the episode's still is used, and only when it is already cached; otherwise no picture.
            var image: UIImage?
            if let id = UpNextPreview.itemID(previewKey: proposal.previewKey), let still = self.stillOnHand,
               let data = await still(id) {
                image = UIImage(data: data)
            }
            guard let item = self.item else { return }
            let content = AVContentProposal(contentTimeForTransition: item.currentTime(), title: title, previewImage: image)
            let duration: Double = item.duration.seconds
            content.automaticAcceptanceInterval = UpNextCard.acceptanceInterval(
                autoPlay: self.autoPlay, position: item.currentTime().seconds, duration: duration.isFinite ? duration : nil)
            item.nextContentProposal = content
        }
    }

    /// The countdown is the system's (R340); the card reads it from the playhead, so there is nothing to update.
    func updateCountdown(seconds: Int?) {}

    func dismiss() {
        Task { @MainActor [weak self] in
            self?.item?.nextContentProposal = nil
        }
    }
}
