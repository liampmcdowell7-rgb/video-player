import Foundation
import AVKit
import AVFoundation
import CoreMedia
import UIKit
import SwiftUI
import AppLogic
import PlaybackLogic
import PlaybackStatus

/// Owns one playback: the player, the progress saving, the Now Playing entry, the Playback Stats overlay, the picture subtitle
/// menu, the mark menu and (when segment data exists) the skip button and Up Next. The system player draws everything else.
///
/// Two ways in: a file the system player opens itself (`resolved.remux == nil`), or a converted playback where `resolved.url` is the
/// loopback address of `resolved.remux` (docs/PLAYBACK_WIRING.md).
///
/// #23 D: AVPlayerViewControllerDelegate is not main-actor isolated, but AVKit calls it on the main thread. The conformance is
/// `@preconcurrency` (SE-0423): the methods stay main-actor isolated and Swift checks at run time that a call arrives on the
/// main actor, instead of the compile-time warning "conformance crosses into main actor-isolated code".
@MainActor
final class PlayerCoordinator: NSObject, @preconcurrency AVPlayerViewControllerDelegate {
    private let resolved: ResolvedPlayback
    private let itemID: Int64
    private let services: AppServices
    private let player: AVPlayer
    private let item: AVPlayerItem
    private let probe: PlaybackProbe
    private let stats = StatsOverlayModel()
    private let skipPresenter = SkipButtonPresenter()
    private let proposalPresenter = ProposalPresenter()
    /// Created when the length of the file is known; nil before that (and when there is nothing to show).
    private var overlay: PlayerOverlayController?
    private var markController: PlayerMarkController?
    private var pictureModel: PictureSubtitleMenuModel?
    private var pictureOverlay: PictureSubtitleOverlay?
    private weak var controller: AVPlayerViewController?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var jumpObserver: NSObjectProtocol?
    private var selectionObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var statsHost: UIHostingController<StatsOverlayView>?
    private var lastSaved: TimeInterval = 0
    private var lastPosition: TimeInterval = 0
    private var stopped = false
    private var noticeShown = false

    /// Called once when the player item fails after it was handed over (the screen shows the reason).
    var onFailure: (PlaybackFailure) -> Void = { _ in }

    init(resolved: ResolvedPlayback, itemID: Int64, services: AppServices) {
        self.resolved = resolved
        self.itemID = itemID
        self.services = services
        let options: [String: Any]? = resolved.headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": resolved.headers]
        let asset = AVURLAsset(url: resolved.url, options: options)
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.externalMetadata = Self.metadata(for: resolved)
        let avPlayer = AVPlayer(playerItem: playerItem)
        self.item = playerItem
        self.player = avPlayer
        self.probe = PlaybackProbe(item: playerItem, remux: resolved.remux)
        super.init()
        skipPresenter.controllerProvider = { [weak self] in self?.controller }
        proposalPresenter.item = playerItem
        if let remux = resolved.remux {
            let model = PictureSubtitleMenuModel(info: remux.info.pictureSubtitles)
            pictureModel = model.isVisible ? model : nil
            stats.notes = remux.notices.map(\.fullText)
        }
    }

    func attach(to controller: AVPlayerViewController) {
        self.controller = controller
        controller.player = player
        controller.delegate = self
        // Now Playing: on tvOS the system player publishes the entry itself from `item.externalMetadata` and manages its own
        // Now Playing session and remote commands, so the app writes neither MPNowPlayingInfoCenter nor MPRemoteCommandCenter
        // (docs/API_USAGE.md "Now Playing on tvOS", OPEN_QUESTIONS R157). `updatesNowPlayingInfoCenter` does not exist on tvOS.
        // The display follows the file: the system matches dynamic range and frame rate to the stream (when the person has those
        // settings on) before the first frame. Set explicitly so a later default change cannot switch it off.
        controller.appliesPreferredDisplayCriteriaAutomatically = true
        // Picture in Picture: on for both ways in. In converted playback the loopback server keeps serving while the app is in the
        // background, so it keeps playing (decision D3, PROVISIONAL; the fallback player, when it exists, gets none).
        controller.allowsPictureInPicturePlayback = true
        installStatsOverlay(in: controller)
        if let remux = resolved.remux, pictureModel != nil, let container = controller.contentOverlayView {
            pictureOverlay = PictureSubtitleOverlay(playback: remux, container: container)
        }
        markController = SegmentsWiring.makeMarkController(
            itemID: itemID, services: services,
            playhead: { [weak self] in self?.lastPosition },
            length: { [weak self] in
                guard let self else { return nil }
                let seconds = self.item.duration.seconds
                return seconds.isFinite && seconds > 0 ? seconds : self.resolved.duration
            })
        markController?.onMenuChanged = { [weak self] in self?.rebuildMenus() }
        markController?.onMarksChanged = { [weak self] in self?.reloadOverlay() }
        markController?.refresh()
        rebuildMenus()
        start()
    }

    // MARK: Start and stop

    private func start() {
        // Sound goes to the TV and the speakers whatever the silent switch or other apps say.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let start = resolved.startAt
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.itemStatusChanged() }
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if start > 1 {
                _ = await self.player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            }
            self.player.play()
            // The poster may need a download; it runs on its own so the skip button and Up Next set-up below never wait for it.
            Task { @MainActor [weak self] in await self?.addArtworkToMetadata() }
            await self.probe.load()
            await self.probe.refreshAudioSelection()
            self.reloadOverlay()
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor [weak self] in self?.tick(seconds) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: self.item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.finished() }
        }
        jumpObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.timeJumpedNotification, object: self.item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.jumped() }
        }
        selectionObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.mediaSelectionDidChangeNotification, object: self.item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.selectionChanged() }
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        statusObservation?.invalidate()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        for token in [endObserver, jumpObserver, selectionObserver] { if let token { NotificationCenter.default.removeObserver(token) } }
        player.pause()
        _ = overlay?.stopped()
        markController?.end()
        pictureOverlay?.hide()
        save(lastPosition)
        // The player is stopped first, then the loopback server and the file reader are closed.
        resolved.remux?.stop()
    }

    // MARK: Events

    private func tick(_ seconds: TimeInterval) {
        guard seconds.isFinite, !stopped else { return }
        let wholeSecondBefore = Int(lastPosition)
        lastPosition = seconds
        pictureOverlay?.tick(seconds)
        showImportantNoticeIfNeeded()
        // Everything below runs once a second, as before the quarter-second clock was needed for picture subtitles.
        guard Int(seconds) != wholeSecondBefore else { return }
        if let overlay { handle(overlay.playhead(seconds, kind: .natural)) }
        if seconds - lastSaved >= 15 {
            lastSaved = seconds
            save(seconds)
        }
        if stats.isVisible {
            stats.update(from: probe, player: player)
            // The audio decoder's running counters (concealed frames and the like) join the file's notices every 5 seconds.
            if Int(seconds) % 5 == 0, let remux = resolved.remux {
                Task { @MainActor [weak self] in
                    let extra = await remux.audioDiagnosticNotices()
                    guard let self, !self.stopped else { return }
                    self.stats.notes = (remux.notices + extra).map(\.fullText)
                }
            }
        }
    }

    private func jumped() {
        guard !stopped else { return }
        pictureOverlay?.didSeek()
        let seconds = player.currentTime().seconds
        if seconds.isFinite, let overlay { handle(overlay.playhead(seconds, kind: .seek)) }
    }

    private func finished() {
        guard !stopped else { return }
        let id = itemID
        let services = self.services
        Task { await services.setWatched(id, true) }
        if let overlay { handle(overlay.ended()) }
    }

    /// The person chose (or the system chose) another subtitle or audio option.
    private func selectionChanged() async {
        guard !stopped else { return }
        await probe.refreshAudioSelection()
        if stats.isVisible { stats.update(from: probe, player: player) }
        guard pictureModel != nil, let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) else { return }
        let textIsOn = item.currentMediaSelection.selectedMediaOption(in: group) != nil
        if let effects = pictureModel?.textSelectionChanged(isOn: textIsOn) { apply(effects) }
        rebuildMenus()
    }

    private func itemStatusChanged() {
        guard !stopped, item.status == .failed else { return }
        let failure = Self.failure(for: item.error)
        player.pause()
        onFailure(failure)
    }

    private static func failure(for error: Error?) -> PlaybackFailure {
        guard let error else { return PlaybackFailures.playerFailure(.other) }
        if (error as NSError).domain == NSURLErrorDomain { return PlaybackFailures.playerFailure(.network) }
        guard let code = (error as? AVError)?.code else { return PlaybackFailures.playerFailure(.other) }
        switch code {
        case .fileFormatNotRecognized, .failedToParse, .fileFailedToParse, .formatUnsupported:
            return PlaybackFailures.playerFailure(.formatNotRecognized)
        case .decoderNotFound, .incompatibleAsset:
            return PlaybackFailures.playerFailure(.decoderMissing)
        case .decodeFailed, .undecodableMediaData:
            return PlaybackFailures.playerFailure(.decodeFailed)
        default:
            return PlaybackFailures.playerFailure(.other)
        }
    }

    /// A notice the person would be confused without (no sound, say) is said once, as an alert, in the first seconds of playback.
    private func showImportantNoticeIfNeeded() {
        guard !noticeShown, lastPosition > 0.5, let controller, controller.presentedViewController == nil,
              let notice = resolved.remux?.notices.first(where: { $0.severity == .important }) else { return }
        noticeShown = true
        let alert = UIAlertController(title: notice.title ?? "About This Playback", message: notice.fullText, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        controller.present(alert, animated: true)
    }

    private func save(_ position: TimeInterval) {
        guard position > 1 else { return }
        let id = itemID
        let duration = item.duration.seconds.isFinite ? item.duration.seconds : resolved.duration
        let services = self.services
        Task { await services.saveProgress(itemID: id, position: position, duration: duration) }
    }

    private func handle(_ effects: [PlayerOverlayEffect]) {
        for effect in effects {
            switch effect {
            case .seek(let target):
                Task { _ = await player.seek(to: CMTime(seconds: target, preferredTimescale: 600)) }
            case .markWatched:
                let id = itemID
                let services = self.services
                Task { await services.setWatched(id, true) }
            default:
                break
            }
        }
    }

    // MARK: Skip button and Up Next

    /// Builds (or builds again) the skip and Up Next logic from the segments of this item and the length of the file.
    private func reloadOverlay() {
        guard !stopped else { return }
        let length = item.duration.seconds.isFinite && item.duration.seconds > 0 ? item.duration.seconds : resolved.duration
        let segments = resolved.segments
        let itemID = self.itemID
        let services = self.services
        let skip = skipPresenter, proposals = proposalPresenter
        let sink: @Sendable ([PlayerOverlayEffect]) -> Void = { [weak self] effects in
            Task { @MainActor in self?.handle(effects) }
        }
        Task { @MainActor [weak self] in
            // Marks made during playback are read from the ledger, so the stored segments are collected again.
            let current = await services.segmentService.segments(forItem: itemID)
            let made = await SegmentsWiring.makeOverlay(
                itemID: itemID, segments: current.isEmpty ? segments : current, duration: length, services: services,
                upNextPresenter: proposals, skipPresenter: skip, sink: sink)
            guard let self, !self.stopped else { return }
            self.overlay = made
            self.proposalPresenter.handler = made
        }
    }

    // MARK: Menus

    private func rebuildMenus() {
        guard let controller else { return }
        var items: [UIMenuElement] = []
        if let model = pictureModel { items.append(pictureMenu(model)) }
        if let markController { items += SegmentsWiring.markMenuItems(for: markController) }
        if UserDefaults.standard.object(forKey: SettingsKey.showPlaybackStatsButton.rawValue) as? Bool ?? true {
            items.append(statsAction())
        }
        controller.transportBarCustomMenuItems = items
    }

    /// The one custom subtitle menu: picture subtitles only. Text subtitles stay in the system menu (decision D1, PROVISIONAL).
    private func pictureMenu(_ model: PictureSubtitleMenuModel) -> UIMenuElement {
        let actions: [UIAction] = model.rows.map { row in
            let action = UIAction(title: row.title, subtitle: row.detail, state: row.isSelected ? .on : .off) { [weak self] _ in
                Task { @MainActor [weak self] in self?.choosePicture(row.track) }
            }
            return action
        }
        return UIMenu(title: PictureSubtitleMenuModel.menuTitle, image: UIImage(systemName: "captions.bubble"), children: actions)
    }

    private func choosePicture(_ track: Int?) {
        guard var model = pictureModel else { return }
        let effects = model.choose(track)
        pictureModel = model
        apply(effects)
        rebuildMenus()
    }

    private func apply(_ effects: [PictureSubtitleMenuModel.Effect]) {
        for effect in effects {
            switch effect {
            case .showPicture(let track):
                pictureOverlay?.show(track: track)
            case .hidePicture:
                pictureOverlay?.hide()
            case .turnOffText:
                Task { @MainActor [weak self] in
                    guard let self, let group = try? await self.item.asset.loadMediaSelectionGroup(for: .legible) else { return }
                    self.item.select(nil, in: group)
                }
            }
        }
    }

    // MARK: Playback Stats overlay

    private func statsAction() -> UIAction {
        UIAction(title: "Playback Stats", image: UIImage(systemName: "chart.bar")) { [weak self] _ in
            Task { @MainActor [weak self] in self?.toggleStats() }
        }
    }

    private func toggleStats() {
        stats.isVisible.toggle()
        statsHost?.view.isHidden = !stats.isVisible
        if stats.isVisible { stats.update(from: probe, player: player) }
    }

    private func installStatsOverlay(in controller: AVPlayerViewController) {
        guard let container = controller.contentOverlayView else { return }
        let host = UIHostingController(rootView: StatsOverlayView(model: stats))
        host.sizingOptions = .intrinsicContentSize
        host.view.backgroundColor = .clear
        host.view.isHidden = true
        host.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            host.view.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor),
        ])
        controller.addChild(host)
        host.didMove(toParent: controller)
        statsHost = host
    }

    // MARK: Up Next (system content proposals)

    func playerViewController(_ playerViewController: AVPlayerViewController, shouldPresent proposal: AVContentProposal) -> Bool { true }

    func playerViewController(_ playerViewController: AVPlayerViewController, didAccept proposal: AVContentProposal) {
        proposalPresenter.handler?.proposalAccepted()
    }

    func playerViewController(_ playerViewController: AVPlayerViewController, didReject proposal: AVContentProposal) {
        proposalPresenter.handler?.proposalRejected()
    }

    // MARK: Metadata (also the Now Playing entry on tvOS)

    /// Title and second line. The system player shows these in its info panel and publishes them as the Now Playing entry
    /// (WWDC17 session 251; `AVPlayerItem.externalMetadata` lists the identifiers it shows).
    private static func metadata(for resolved: ResolvedPlayback) -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []
        func add(_ identifier: AVMetadataIdentifier, _ value: String) {
            let entry = AVMutableMetadataItem()
            entry.identifier = identifier
            entry.value = value as NSString
            entry.extendedLanguageTag = "und"
            items.append(entry)
        }
        add(.commonIdentifierTitle, resolved.title)
        if let subtitle = resolved.subtitle { add(.iTunesMetadataTrackSubTitle, subtitle) }
        return items
    }

    /// Adds the poster (when one is found) as `commonIdentifierArtwork`, with the data type WWDC17 session 251 asks for (JPEG or
    /// PNG). Bytes that are neither are left out rather than sent with a wrong type. Whether the system picks up metadata added
    /// after playback started is a device check (docs/DEVICE_TEST_CHECKLIST_PLATFORM.md, P10 (d)).
    private func addArtworkToMetadata() async {
        guard let key = resolved.content.artworkKey, let bytes = await services.online.artworkBytes(key: key), !stopped else { return }
        let type: String
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            type = kCMMetadataBaseDataType_JPEG as String
        } else if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            type = kCMMetadataBaseDataType_PNG as String
        } else {
            return
        }
        let entry = AVMutableMetadataItem()
        entry.identifier = .commonIdentifierArtwork
        entry.value = bytes as NSData
        entry.dataType = type
        entry.extendedLanguageTag = "und"
        item.externalMetadata.append(entry)
    }
}

/// A monotonic clock for the playback logic (not affected by changes of the wall-clock time).
struct MonotonicClock: PlaybackClock {
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
}
