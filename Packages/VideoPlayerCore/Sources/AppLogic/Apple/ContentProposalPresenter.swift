#if os(tvOS) && canImport(AVKit) && canImport(UIKit)
import Foundation
import AVKit
import UIKit

// NEVER COMPILED. Written from Apple's documentation ("Presenting content proposals in tvOS", AVPlayerViewController
// `contextualActions`) without a Mac. No decisions here: `PlayerOverlayController` (tested in WSL) decides what is on screen
// and when; these two classes draw it with AVKit and report taps back.
//
// How AVKit's own model differs from ours, and what this file does about it (PROVISIONAL until run on an Apple TV,
// docs/DEVICE_TEST_CHECKLIST.md):
//   * AVKit presents a proposal when playback reaches `contentTimeForTransition` of the item's `nextContentProposal`.
//     Our machine decides the moment (the credits start). We set the transition time to the current playhead, so the
//     proposal is already due and AVKit should present it at once. (Unverified: it may need a nudge or wait for a tick.)
//   * AVKit counts `automaticAcceptanceInterval` from the END of playback. Our countdown starts at the credits start,
//     so we turn the system countdown off (`.nan`) and let the controller's own countdown (fed by its tick) call
//     `proposalAccepted()`. The text under the buttons comes from `updateCountdown`.

// MARK: Up Next

public final class ContentProposalPresenter: NSObject, UpNextProposalPresenting, AVPlayerViewControllerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private weak var playerViewController: AVPlayerViewController?
    private let image: @Sendable (String) -> UIImage?
    private var _handler: (any UpNextProposalHandler)?
    private var current: UpNextProposal?
    private var proposalController: UpNextProposalViewController?
    private var closing = false

    public init(playerViewController: AVPlayerViewController, image: @escaping @Sendable (String) -> UIImage?) {
        self.playerViewController = playerViewController
        self.image = image
        super.init()
        playerViewController.delegate = self
    }

    public var handler: (any UpNextProposalHandler)? {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }

    // MARK: UpNextProposalPresenting

    public func present(_ proposal: UpNextProposal) {
        lock.withLock { current = proposal; closing = false }
        DispatchQueue.main.async { [weak self] in
            guard let self, let vc = self.playerViewController, let item = vc.player?.currentItem else { return }
            let title = [proposal.episodeCode, proposal.episodeTitle].compactMap { $0 }.joined(separator: " · ")
            let preview = proposal.previewKey.flatMap(self.image)
            let p = AVContentProposal(contentTimeForTransition: vc.player?.currentTime() ?? .zero, title: title, previewImage: preview)
            p.automaticAcceptanceInterval = .nan        // our countdown runs it, see the note at the top
            item.nextContentProposal = p
        }
    }

    public func updateCountdown(seconds: Int?) {
        let text = PlayerOverlayController.countdownText(seconds.map(TimeInterval.init))
        DispatchQueue.main.async { [weak self] in self?.lock.withLock { self?.proposalController }?.setCountdown(text) }
    }

    public func dismiss() {
        lock.withLock { closing = true }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.playerViewController?.player?.currentItem?.nextContentProposal = nil
            self.lock.withLock { self.proposalController }?.dismissContentProposal(for: .reject, animated: true)
            self.lock.withLock { self.proposalController = nil }
        }
    }

    // MARK: AVPlayerViewControllerDelegate

    public func playerViewController(_ playerViewController: AVPlayerViewController, shouldPresent proposal: AVContentProposal) -> Bool {
        guard let spec = lock.withLock({ current }) else { return false }
        let vc = UpNextProposalViewController(spec: spec)
        lock.withLock { proposalController = vc }
        playerViewController.contentProposalViewController = vc
        return true
    }

    public func playerViewController(_ playerViewController: AVPlayerViewController, didAccept proposal: AVContentProposal) {
        guard !lock.withLock({ closing }) else { return }
        handler?.proposalAccepted()
    }

    public func playerViewController(_ playerViewController: AVPlayerViewController, didReject proposal: AVContentProposal) {
        // A reject we caused ourselves (dismiss()) is not the user pressing Menu.
        guard !lock.withLock({ closing }) else { return }
        handler?.proposalRejected()
    }
}

/// The proposal screen: the video shrinks to the top, the next episode's name and two buttons sit below it.
final class UpNextProposalViewController: AVContentProposalViewController {
    private let spec: UpNextProposal
    private let countdownLabel = UILabel()
    private var acceptButton: UIButton?

    init(spec: UpNextProposal) {
        self.spec = spec
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var preferredPlayerViewFrame: CGRect {
        guard let frame = playerViewController?.view.frame else { return .zero }
        return CGRect(x: frame.midX / 2, y: 0, width: 960, height: 540)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let heading = UILabel()
        heading.text = spec.heading
        heading.font = .preferredFont(forTextStyle: .title2)
        let title = UILabel()
        title.text = [spec.episodeCode, spec.episodeTitle].compactMap { $0 }.joined(separator: " · ")
        title.font = .preferredFont(forTextStyle: .headline)
        title.numberOfLines = 2
        countdownLabel.font = .preferredFont(forTextStyle: .callout)
        countdownLabel.text = PlayerOverlayController.countdownText(spec.automaticAcceptanceInterval)

        var play = UIButton.Configuration.filled()
        play.title = spec.acceptTitle
        let accept = UIButton(configuration: play, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            self.dismissContentProposal(for: .accept, animated: true)
        })
        var cancel = UIButton.Configuration.gray()
        cancel.title = spec.dismissTitle
        let reject = UIButton(configuration: cancel, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            self.dismissContentProposal(for: .reject, animated: true)
        })

        acceptButton = accept
        let buttons = UIStackView(arrangedSubviews: [accept, reject])
        buttons.axis = .horizontal
        buttons.spacing = 40
        let stack = UIStackView(arrangedSubviews: [heading, title, countdownLabel, buttons])
        stack.axis = .vertical
        stack.spacing = 24
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: playerLayoutGuide.leadingAnchor),
            stack.topAnchor.constraint(equalTo: playerLayoutGuide.bottomAnchor, constant: 40),
        ])
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] { acceptButton.map { [$0] } ?? [] }

    func setCountdown(_ text: String?) { countdownLabel.text = text }
}

// MARK: Skip button

/// Skip Intro / Recap / Credits as an AVPlayerViewController contextual action (tvOS 15+). AVKit shows it only while
/// the transport bar is hidden, which is the behaviour we want (docs/HIG_AUDIT.md, player overlay).
public final class ContextualActionSkipPresenter: SkipButtonPresenting, @unchecked Sendable {
    private weak var playerViewController: AVPlayerViewController?

    public init(playerViewController: AVPlayerViewController) { self.playerViewController = playerViewController }

    public func show(title: String, onPress: @escaping @Sendable () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.playerViewController?.contextualActions = [UIAction(title: title) { _ in onPress() }]
        }
    }

    public func hide() {
        DispatchQueue.main.async { [weak self] in self?.playerViewController?.contextualActions = [] }
    }
}
#endif
