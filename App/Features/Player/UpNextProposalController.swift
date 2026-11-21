import AVKit
import AVFoundation
import SwiftUI
import UIKit
import AppLogic

/// R340 (owner decision of 21 Nov 2026 in R338, docs/HIG_AUDIT.md T19): the system Up Next. The proposal is an
/// `AVContentProposal` on the current item (`ProposalPresenter`); its card is this `AVContentProposalViewController`
/// subclass, as Apple's article "Presenting content proposals in tvOS" builds it: "You create this interface by subclassing
/// the AVKit framework's AVContentProposalViewController class", with controls that call
/// `dismissContentProposal(for: .accept / .reject)`, and the video scaled to "a 960x540 window centered at the top"
/// (`preferredPlayerViewFrame`). The countdown text follows the system's `automaticAcceptanceInterval` from the playhead,
/// so a pause stops it. Whether the system also draws its own countdown, and how the card looks on tvOS 27: UNVERIFIED.
final class UpNextProposalController: AVContentProposalViewController {
    private let model = UpNextCardModel()
    private var timeObserver: Any?

    override var preferredPlayerViewFrame: CGRect {
        guard let frame = playerViewController?.view.frame else { return .zero }
        return CGRect(x: frame.midX / 2.0, y: 0, width: 960, height: 540)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        model.title = contentProposal?.title ?? ""
        let card = UpNextCardView(model: model,
                                  accept: { [weak self] in self?.dismissContentProposal(for: .accept, animated: true, completion: nil) },
                                  reject: { [weak self] in self?.dismissContentProposal(for: .reject, animated: true, completion: nil) })
        let host = UIHostingController(rootView: card)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: playerLayoutGuide.bottomAnchor, constant: 40),
            host.view.leadingAnchor.constraint(equalTo: playerLayoutGuide.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: playerLayoutGuide.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard let player = playerViewController?.player, timeObserver == nil else { return }
        refresh(player)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self, weak player] _ in
            MainActor.assumeIsolated { if let player { self?.refresh(player) } }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let timeObserver { playerViewController?.player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
    }

    private func refresh(_ player: AVPlayer) {
        let duration: Double? = player.currentItem.map { $0.duration.seconds }
        let interval: Double = contentProposal?.automaticAcceptanceInterval ?? .nan
        let seconds: Int? = UpNextCard.remaining(position: player.currentTime().seconds, duration: duration, interval: interval)
        model.countdown = UpNextCard.countdownText(seconds)
    }
}

@MainActor
@Observable
final class UpNextCardModel {
    var title = ""
    var countdown: String?
}

/// The card's content: "Up Next", the episode, the countdown when Auto-Play is on, and two system buttons.
struct UpNextCardView: View {
    let model: UpNextCardModel
    var accept: () -> Void
    var reject: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Text(UpNextCard.heading)
                .font(.headline)
                .foregroundStyle(.secondary)
            FittingText(model.title, style: .title3)
            if let countdown = model.countdown {
                FittingText(countdown, style: .callout)
                    .foregroundStyle(.secondary)
            }
            ActionRow {
                Button(action: accept) { ActionLabel(UpNextCard.playNow, systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(ControlID.upNextPlayNow)
                Button(action: reject) { ActionLabel(UpNextCard.cancel, systemImage: "xmark") }
                    .accessibilityIdentifier(ControlID.upNextCancel)
            }
        }
    }
}
