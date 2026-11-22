import Foundation
import AVKit
import AVFoundation
import CoreMedia
import UIKit
import SwiftUI
import VideoPlayerCore
import AppLogic
import PlaybackLogic
import PlaybackStatus

/// Owns one playback: the player, the progress saving, the Now Playing entry, the info panel's Episodes and Playback Stats
/// tabs, the picture subtitle menu, the mark menu and (when segment data exists) the skip button and Up Next. The system
/// player draws everything else.
///
/// R340 (owner decision of 21 Nov 2026 in R338, docs/HIG_AUDIT.md T15 to T19): Playback Stats moved from an overlay over
/// the picture into an info panel tab; an Episodes tab; the system Up Next (`AVContentProposal` with its own
/// `automaticAcceptanceInterval`, the card `UpNextProposalController`); and the advance step that was dropped (`handle` let
/// `.advance` fall into `default`, so the next episode never started) now plays the next item through `onPlayItem`. The
/// overlay's effects reach `handle` once, through its sink (before, the returned copy was handled too, so a seek ran twice).
///
/// R311 (owner's device test of build 5: a black player, about 30 seconds, then the page again with no message; the CI run
/// of the same commit stopped the same way with the sample clip): the start is a chain of named steps, each with a time
/// limit checked by the one-second clock: the item becoming ready, the move to the saved position, the first moving picture.
/// A step past its limit, or an item that fails, ends with the reason on screen and in Settings > Playback > Last Playback
/// Problem. The item's status is observed from its first value (a failure that came before the observer was added was
/// never seen, leaving a black screen); playback starts when the item is ready, and only then the resume seek (with 2 s
/// of tolerance before the saved place, so it lands on a nearby key frame instead of decoding up to an exact frame).
/// The info panel tabs are installed once, after play has been asked for (before, they were set while SwiftUI was
/// building the player and again a moment later), and the R309 timeline clock is the same one-second clock.
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
    /// R309: the play state and a one-second clock for the Plex watch sync (it sends at most every 10 seconds, at once on a change).
    private var playStateObservation: NSKeyValueObservation?
    private var timelineTimer: Timer?
    /// R340: the Episodes tab's content (nil for a film); loaded once at the start.
    private var episodes: PlayerEpisodes.Content?
    private var advanced = false
    /// R311: the steps of this start and their time limits.
    private let tracker: PlaybackStartTracker
    private var begun = false
    private var failed = false
    private var lastSaved: TimeInterval = 0
    private var lastPosition: TimeInterval = 0
    private var stopped = false
    private var noticeShown = false
    /// R316: the background reading of this episode's and the next one's audio (cancelled when playback stops).
    private var learning: Task<Void, Never>?
    /// R386: what the player did, newest last, for the failure screen and Settings (the last event with its time).
    private let events = PlaybackEventLog()
    /// R386: when the player got the file (system uptime), for "n s after the player opened".
    private var openedAt: TimeInterval = ProcessInfo.processInfo.systemUptime
    /// R386: the playhead when play was asked for; the start counts as playing once it moves on (`PlaybackStartProgress`).
    private var positionAtPlay: Double?
    /// R386: the error of `failedToPlayToEndTimeNotification`, when the system posted one.
    private var endReport: PlayerErrorReport?
    private var stallObserver: NSObjectProtocol?
    private var failedEndObserver: NSObjectProtocol?
    private var errorLogObserver: NSObjectProtocol?
    /// R390: the first frame, from `AVPlayerViewController.isReadyForDisplay` (Apple: "A Boolean value that indicates
    /// whether the player item's first video frame is ready for display. This property is key-value observable.").
    private var displayObservation: NSKeyValueObservation?
    private var audioChecked = false

    /// Called once when the player item fails after it was handed over, or a step of the start runs past its limit (the
    /// screen shows the reason). The second value holds the system's own error text for the diagnostic row (R311) and,
    /// R386, the player's error domain, code and underlying errors and its last events.
    var onFailure: (PlaybackFailure, PlaybackDiagnostics) -> Void = { _, _ in }
    /// R340: play another library item in place of this one (Up Next accepted, or an episode chosen in the Episodes tab).
    /// The screen ends this playback (`stop`, which saves the position and tells the watch sync) and starts the next.
    var onPlayItem: (Int64) -> Void = { _ in }

    init(resolved: ResolvedPlayback, itemID: Int64, services: AppServices, tracker: PlaybackStartTracker) {
        self.resolved = resolved
        self.itemID = itemID
        self.services = services
        self.tracker = tracker
        let options: [String: Any]? = resolved.headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": resolved.headers]
        let asset = AVURLAsset(url: resolved.url, options: options)
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.externalMetadata = Self.metadata(for: resolved)
        let avPlayer = AVPlayer(playerItem: playerItem)
        self.item = playerItem
        self.player = avPlayer
        self.probe = PlaybackProbe(item: playerItem, remux: resolved.remux)
        super.init()
        // R390: the system player has its item from here.
        tracker.reach(.itemCreated)
        skipPresenter.controllerProvider = { [weak self] in self?.controller }
        proposalPresenter.item = playerItem
        proposalPresenter.stillOnHand = { [services] id in await services.online.upNextStill(itemID: id) }
        proposalPresenter.seriesTitle = resolved.content.seriesTitle
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
        stats.onShown = { [weak self] in
            guard let self, !self.stopped else { return }
            self.stats.update(from: self.probe, player: self.player)
        }
        // R311: the info panel tabs are installed once playback has been asked for (`begin`), not while SwiftUI builds the player.
        proposalPresenter.autoPlay = SegmentsWiring.autoPlayNextEpisode
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
        // R311: from here the item must become ready within its limit (checked once a second in `everySecond`).
        tracker.enter(.playerReady)
        openedAt = ProcessInfo.processInfo.systemUptime
        record("The player got the file")
        // R390: the first frame, observed from its first value.
        displayObservation = controller?.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, change in
            let ready = change.newValue ?? false
            Task { @MainActor [weak self] in if ready { self?.firstFrameShown() } }
        }
        Task { @MainActor [weak self] in await self?.inspectVideoTrack() }
        // `.initial`: a status the item reached before this line is seen too (R311).
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.itemStatusChanged() }
        }
        services.watchSync.send(.started(itemID: itemID, file: resolved.file))
        playStateObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.playStateChanged() }
        }
        // One clock for the time limits of the start (R311) and the watch sync's timeline (R309).
        timelineTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.everySecond() }
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
        // R386: recorded only, so the failure report says what the player did last; none of them changes playback.
        // Apple: playbackStalledNotification is posted when "media doesn't arrive in time to continue playback";
        // "Streaming-media playback continues ... File-based playback doesn't continue."
        stallObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.playbackStalledNotification, object: self.item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.record("Stalled: the media did not arrive in time") }
        }
        // Apple: failedToPlayToEndTimeNotification, its error under AVPlayerItemFailedToPlayToEndTimeErrorKey.
        failedEndObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: self.item, queue: .main) { [weak self] note in
            let report = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError).map(PlayerErrorReport.init)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.endReport = report
                self.record("Failed to play to the end" + (report.map { ": " + $0.codeLine } ?? ""))
            }
        }
        errorLogObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.newErrorLogEntryNotification, object: self.item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let entry = self.item.errorLog()?.events.last else { return }
                self.record("Error log: " + PlayerErrorReport.line(domain: entry.errorDomain, code: entry.errorStatusCode,
                                                                   message: entry.errorComment ?? ""))
            }
        }
    }

    /// R386: one event of this playback, with the playhead and the seconds since the player got the file.
    private func record(_ name: String) {
        let position = player.currentTime().seconds
        events.record(name, position: position.isFinite ? position : nil,
                      elapsed: ProcessInfo.processInfo.systemUptime - openedAt)
    }

    /// R386: the start is over once the player plays or the playhead moved on since play was asked for. Before, only a
    /// CHANGE of the play state seen after `play()` ended it: a player already playing by then (Play pressed during the
    /// move to the saved position) sent none, and the 30-second limit of "Starting playback" ended a playing video.
    private func markPlayingIfStarted() {
        guard !stopped, tracker.step.step == .startPlaying else { return }
        let position = player.currentTime().seconds
        guard PlaybackStartProgress.hasStarted(isPlaying: player.timeControlStatus == .playing, positionAtPlay: positionAtPlay,
                                               position: position.isFinite ? position : nil) else { return }
        tracker.enter(.playing)
        record("Playing")
    }

    // MARK: R390 checkpoints

    private func firstFrameShown() {
        guard !stopped else { return }
        let size = item.presentationSize
        tracker.reach(.firstFrame, detail: size.width > 0 ? "\(Int(size.width)) × \(Int(size.height))" : nil)
        record("First frame ready for display")
    }

    /// The video track the system player will decode, in plain words, with what the system says when it cannot decode or
    /// play it (`AVAssetTrack` `isDecodable`: "the system can decode the track"; `isPlayable`). Direct playback reads the
    /// file's own track before the item is ready, so a track the Apple TV cannot show is named even when the item never
    /// becomes ready. Converted playback names what the converting player serves (the stream's tracks are only listed once
    /// the item is ready).
    private func inspectVideoTrack() async {
        if let remux = resolved.remux {
            let info = remux.info
            tracker.describe(.videoTrackFound, detail: PlaybackCheckpoints.videoTrackText(
                codec: info.videoCodecString, width: info.width, height: info.height, decodable: nil, playable: nil))
            return
        }
        guard let tracks = try? await item.asset.loadTracks(withMediaType: .video), !stopped else { return }
        guard let track = tracks.first else {
            tracker.describe(.videoTrackFound, detail: "The file has no video track the system player can read")
            tracker.note("The system player found no video track in the file.")
            return
        }
        var codec: String?
        if let description = try? await track.load(.formatDescriptions).first {
            codec = PlaybackCheckpoints.codecName(fourCC: PlaybackCheckpoints.fourCC(CMFormatDescriptionGetMediaSubType(description)))
        }
        let size = try? await track.load(.naturalSize)
        let decodable = try? await track.load(.isDecodable)
        let playable = try? await track.load(.isPlayable)
        guard !stopped else { return }
        let text = PlaybackCheckpoints.videoTrackText(codec: codec, width: size.map { Int($0.width) }, height: size.map { Int($0.height) },
                                                      decodable: decodable, playable: playable)
        tracker.reach(.videoTrackFound, detail: text)
        if decodable == false || playable == false { tracker.note("Video track: " + text + ".") }
    }

    /// The tracks of the ready item: a video track (converted playback reaches the checkpoint here), and a note when the item
    /// is ready with no video in it (a picture the system left out without an error).
    private func checkReadyItemTracks() {
        let video = item.tracks.filter { $0.assetTrack?.mediaType == .video }
        if !video.isEmpty {
            if resolved.remux != nil { tracker.reach(.videoTrackFound) }
            if !video.contains(where: \.isEnabled) { tracker.note("The item's video track is turned off.") }
        } else if !item.tracks.isEmpty {
            tracker.note("The item is ready but holds no video track: the picture was left out.")
        }
    }

    /// The playhead's distance from where play was asked for: the 5 s and 30 s checkpoints, and the audio one (an enabled
    /// audio track while the playhead moves; whether sound reaches the TV is not something the player reports).
    private func checkPlayhead(_ seconds: TimeInterval) {
        guard let start = positionAtPlay else { return }
        let moved = seconds - start
        if moved >= 0.5, !audioChecked {
            audioChecked = true
            if let audio = item.tracks.first(where: { $0.assetTrack?.mediaType == .audio && $0.isEnabled }) {
                tracker.reach(.audioStarted)
                if let assetTrack = audio.assetTrack {
                    Task { @MainActor [weak self] in
                        guard let description = try? await assetTrack.load(.formatDescriptions).first else { return }
                        let code = PlaybackCheckpoints.fourCC(CMFormatDescriptionGetMediaSubType(description))
                        self?.tracker.reach(.audioStarted, detail: PlaybackCheckpoints.codecName(fourCC: code))
                    }
                }
            } else {
                tracker.describe(.audioStarted, detail: "No enabled audio track while the video moved")
            }
        }
        if moved >= 5 { tracker.reach(.playheadMoved5) }
        if moved >= 30 { tracker.reach(.playheadMoved30) }
    }

    /// Notes for the report at a failure: what the loopback served (converted), and a ready item with no video.
    private func addFailureNotes() {
        if item.status == .readyToPlay { checkReadyItemTracks() }
        if let remux = resolved.remux {
            let started = tracker.checkpoints.entry(.loopbackReady)?.seconds ?? 0
            for line in remux.serveLines(serverStartedAt: started) { tracker.note(line) }
        }
    }

    /// R386: the play state as the event log says it, with the system's reason for waiting.
    private var playStateText: String {
        switch player.timeControlStatus {
        case .playing: return "Play state: playing"
        case .paused: return "Play state: paused"
        case .waitingToPlayAtSpecifiedRate:
            return "Play state: waiting" + (player.reasonForWaitingToPlay.map { " (\($0.rawValue))" } ?? "")
        @unknown default: return "Play state: \(player.timeControlStatus.rawValue)"
        }
    }

    /// Runs once, when the item is ready to play (R311): the move to the saved position, play, then everything that may wait.
    private func begin() async {
        let start = resolved.startAt
        if start > 1 {
            tracker.enter(.resumeSeek)
            record("Moving to the saved position " + PlaybackEvent.clock(start))
            _ = await player.seek(to: CMTime(seconds: start, preferredTimescale: 600),
                                  toleranceBefore: CMTime(seconds: 2, preferredTimescale: 600), toleranceAfter: .zero)
            guard !stopped, !failed else { return }
        }
        tracker.enter(.startPlaying)
        let here = player.currentTime().seconds
        positionAtPlay = here.isFinite ? here : nil
        record("Play asked for")
        player.play()
        // R386: a player that was already playing sends no change of play state; check now as well.
        markPlayingIfStarted()
        // The poster may need a download; it runs on its own so the skip button and Up Next set-up below never wait for it.
        Task { @MainActor [weak self] in await self?.addArtworkToMetadata() }
        // R319: the content rating may need the online details too, so it is added the same way, on its own.
        Task { @MainActor [weak self] in await self?.addRatingToMetadata() }
        await probe.load()
        await probe.refreshAudioSelection()
        reloadOverlay()
        startLearning()
        // R340: the Episodes tab once the season is read; the tabs are set once (R311).
        episodes = await PlayerEpisodes.load(itemID: itemID, store: services.store)
        installInfoPanels()
    }

    private func playStateChanged() {
        guard !stopped else { return }
        record(playStateText)
        // Playing, or paused after play was asked for (the person paused): the start is over and has no limit any more.
        if player.timeControlStatus != .waitingToPlayAtSpecifiedRate, tracker.step.step == .startPlaying { tracker.enter(.playing) }
        reportTimeline()
    }

    /// The one-second clock: the time limit of the running start step (R311), then the timeline for the watch sync (R309).
    private func everySecond() {
        guard !stopped, !failed else { return }
        // R386: a video that is playing or moving is past its start, whatever change of play state was or was not seen.
        markPlayingIfStarted()
        let step = tracker.step.step
        if step != .playing, tracker.isOverdue {
            report(PlaybackFailures.startTimedOut(step, seconds: PlaybackStartDeadline.limit(for: step) ?? 0))
            return
        }
        reportTimeline()
    }

    /// Ends this playback with the reason (once).
    private func report(_ failure: PlaybackFailure) {
        guard !stopped, !failed else { return }
        failed = true
        // R390: the loopback's answers and the item's tracks, read before the player is paused.
        addFailureNotes()
        // R386: read before the pause below adds an event of its own.
        let diagnostics = PlaybackDiagnostics(detail: playerDetail, player: playerReport, events: events.recent)
        item.cancelPendingSeeks()
        player.pause()
        onFailure(failure, diagnostics)
    }

    /// R386: the system player's error for the failure screen: the item's error, else the one posted with
    /// `failedToPlayToEndTimeNotification`, else the newest entry of the item's error log; nil when there is none (a step
    /// of the start past its limit).
    private var playerReport: PlayerErrorReport? {
        if let error = item.error as NSError? { return PlayerErrorReport(error) }
        if let endReport { return endReport }
        if let entry = item.errorLog()?.events.last {
            return PlayerErrorReport(domain: entry.errorDomain, code: entry.errorStatusCode, message: entry.errorComment ?? "")
        }
        return nil
    }

    /// What the system player said about the problem, for the diagnostic row (tokens are removed by the tracker).
    private var playerDetail: String? {
        var parts: [String] = []
        if let error = item.error as NSError? { parts.append("\(error.domain) \(error.code): \(error.localizedDescription)") }
        if let event = item.errorLog()?.events.last {
            parts.append("\(event.errorDomain) \(event.errorStatusCode): \(event.errorComment ?? "")")
        }
        parts.append("item status \(item.status.rawValue), play state \(player.timeControlStatus.rawValue)")
        return parts.joined(separator: "; ")
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        statusObservation?.invalidate()
        playStateObservation?.invalidate()
        displayObservation?.invalidate()
        timelineTimer?.invalidate()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        for token in [endObserver, jumpObserver, selectionObserver, stallObserver, failedEndObserver, errorLogObserver] {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
        player.pause()
        learning?.cancel()
        _ = overlay?.stopped()
        markController?.end()
        pictureOverlay?.hide()
        save(lastPosition)
        services.watchSync.send(.stopped(position: lastPosition, duration: knownDuration, at: Date()))
        // The player is stopped first, then the loopback server and the file reader are closed.
        resolved.remux?.stop()
    }

    // MARK: Events

    private func tick(_ seconds: TimeInterval) {
        guard seconds.isFinite, !stopped else { return }
        let wholeSecondBefore = Int(lastPosition)
        lastPosition = seconds
        markPlayingIfStarted()
        checkPlayhead(seconds)
        pictureOverlay?.tick(seconds)
        showImportantNoticeIfNeeded()
        // Everything below runs once a second, as before the quarter-second clock was needed for picture subtitles.
        guard Int(seconds) != wholeSecondBefore else { return }
        // R340: the effects arrive once, through the overlay's sink (`reloadOverlay`).
        _ = overlay?.playhead(seconds, kind: .natural)
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
        record("Time jumped")
        pictureOverlay?.didSeek()
        let seconds = player.currentTime().seconds
        if seconds.isFinite { _ = overlay?.playhead(seconds, kind: .seek) }
    }

    private func finished() {
        guard !stopped else { return }
        record("Played to the end")
        let id = itemID
        let services = self.services
        Task { await services.setWatched(id, true) }
        _ = overlay?.ended()
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
        guard !stopped, !failed else { return }
        switch item.status {
        case .readyToPlay: record("Item status: ready to play")
        case .failed: record("Item status: failed" + ((item.error as NSError?).map { ": \($0.domain) \($0.code)" } ?? ""))
        default: record("Item status: \(item.status.rawValue)")
        }
        switch item.status {
        case .failed:
            report(Self.failure(for: item.error))
        case .readyToPlay:
            guard !begun else { return }
            begun = true
            // R390: the item reached ready; its tracks are listed from here.
            tracker.reach(.itemReady)
            checkReadyItemTracks()
            Task { @MainActor [weak self] in await self?.begin() }
        default:
            break
        }
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

    private var knownDuration: TimeInterval? { item.duration.seconds.isFinite ? item.duration.seconds : resolved.duration }

    /// R309: what the player is doing, for the Plex watch sync (nothing is sent unless a Plex source of this item has the
    /// switch on).
    private func reportTimeline() {
        guard !stopped else { return }
        let state: ServerPlaybackState
        switch player.timeControlStatus {
        case .playing: state = .playing
        case .paused: state = .paused
        case .waitingToPlayAtSpecifiedRate: state = .buffering
        @unknown default: state = .playing
        }
        let seconds = player.currentTime().seconds
        services.watchSync.send(.progress(state: state, position: seconds.isFinite ? seconds : lastPosition, duration: knownDuration, at: Date()))
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
            case .advance:
                // R340: the next episode starts (it was dropped here before, so it never did).
                if let next = SegmentsWiring.itemID(for: effect) { play(next) }
            default:
                break
            }
        }
    }

    /// R340: hands another item to the screen, once per playback.
    private func play(_ next: Int64) {
        guard !stopped, !advanced, next != itemID else { return }
        advanced = true
        onPlayItem(next)
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

    /// R316: learns the intro and credits of this episode and of the next one from their audio, at background priority, so
    /// the next episode can be skipped even without markers. Local only; a failure only means nothing is learned.
    private func startLearning() {
        let segmentService = services.segmentService
        let store = services.store
        let itemID = self.itemID
        learning = Task.detached(priority: .background) {
            await segmentService.learn(forItem: itemID)
            let feed = await NextEpisodeFeed.resolve(itemID: itemID, store: store)
            if case .next(let ref) = feed.decision, let next = NextEpisodeFeed.libraryItemID(for: ref), !Task.isCancelled {
                await segmentService.learn(forItem: next)
            }
        }
    }

    // MARK: Menus

    private func rebuildMenus() {
        guard let controller else { return }
        var items: [UIMenuElement] = []
        if let model = pictureModel { items.append(pictureMenu(model)) }
        if let markController { items += SegmentsWiring.markMenuItems(for: markController) }
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

    // MARK: Info panel (R340)

    /// The content tabs under the transport controls: Episodes (an episode only), then Playback Stats (Settings > Playback >
    /// Show Playback Stats in the Player). Built again when the season has been read.
    private func installInfoPanels() {
        guard let controller, !stopped else { return }
        var tabs: [UIViewController] = []
        if let episodes {
            tabs.append(PlayerInfoPanels.controller(title: PlayerEpisodes.tabTitle, services: services) {
                PlayerEpisodesPanel(content: episodes, onPlay: { [weak self] id in self?.play(id) })
            })
        }
        if UserDefaults.standard.object(forKey: SettingsKey.showPlaybackStatsButton.rawValue) as? Bool ?? true {
            tabs.append(PlayerInfoPanels.controller(title: "Playback Stats", services: services) { StatsPanelView(model: stats) })
        }
        controller.customInfoViewControllers = tabs
    }

    // MARK: Up Next (system content proposals)

    /// R340: the card is the app's `AVContentProposalViewController` subclass (Apple's article "Presenting content proposals
    /// in tvOS": set it as `contentProposalViewController` here).
    func playerViewController(_ playerViewController: AVPlayerViewController, shouldPresent proposal: AVContentProposal) -> Bool {
        playerViewController.contentProposalViewController = UpNextProposalController()
        return true
    }

    func playerViewController(_ playerViewController: AVPlayerViewController, didAccept proposal: AVContentProposal) {
        proposalPresenter.handler?.proposalAccepted()
    }

    func playerViewController(_ playerViewController: AVPlayerViewController, didReject proposal: AVContentProposal) {
        proposalPresenter.handler?.proposalRejected()
    }

    // MARK: Metadata (also the Now Playing entry on tvOS)

    /// Title and second line. The system player shows these in its info panel and publishes them as the Now Playing entry
    /// (WWDC17 session 251; `AVPlayerItem.externalMetadata` lists the identifiers it shows).
    ///
    /// R317 (iPhone Now Playing, Apple's pages read 21 Nov 2026): "An AVPlayerViewController manages its own player and Now
    /// Playing session, so you can't add your own" (MPNowPlayingSession). So the app supplies only this metadata (title =
    /// episode name, second line "Show · S1, E3" from R313, and the poster); the system takes the duration, elapsed time and
    /// rate from the AVPlayer and answers play, pause, scrubbing and the skip buttons itself. The app registers no
    /// MPRemoteCommandCenter handlers and sets no MPNowPlayingInfoCenter values (that would compete with the system's
    /// entry). `updatesNowPlayingInfoCenter` exists on iOS, not on tvOS. The iPhone's Remote and its volume buttons are
    /// system features of the Apple TV (volume only with a receiver or TV that supports it).
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
        // R380: the rating on hand goes on the item before playback starts, so the content restrictions can use it.
        if let rating = resolved.startRating { add(.iTunesMetadataContentRating, rating.value) }
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

    /// R319 (owner's request of 21 Nov 2026): the title's content rating in the Info tab, as the system's own item.
    /// Apple's AVMetadataIdentifier page (read 21 Nov 2026) lists `iTunesMetadataContentRating`, "An identifier that
    /// represents the content rating in iTunes" (tvOS 9.0+), and "Customizing the tvOS playback experience" lists
    /// "Content rating | iTunesMetadataContentRating | String" among the values the player presents in its Info tab. The
    /// value is R371's rating, the badge text ("PG-13"); no item when there is none. Now Playing: MPNowPlayingInfoCenter has
    /// no content-rating key, and the system owns the entry on tvOS (R317), so the app adds nothing there. Whether the Info
    /// tab shows an item added after playback started is the same device check as the artwork's.
    ///
    /// R380 (PROVISIONAL): a rating on hand is already on the item from before the start (`metadata(for:)`). The lookup's
    /// answer replaces it only when `PlayerRating.afterLookup` says so (none at start, or an answer from a layer at least
    /// as strong); the old rating item is removed first, so the item never carries two ratings.
    private func addRatingToMetadata() async {
        guard let key = resolved.ratingKey else { return }
        let answer = await services.online.layeredDetails(key: key)
        guard let choice = PlayerRating.afterLookup(current: resolved.startRating, answer: answer.details?.contentRating,
                                                    answerLayer: answer.ratingLayer), !stopped else { return }
        let entry = AVMutableMetadataItem()
        entry.identifier = .iTunesMetadataContentRating
        entry.value = choice.value as NSString
        entry.extendedLanguageTag = "und"
        item.externalMetadata = item.externalMetadata.filter { $0.identifier != .iTunesMetadataContentRating } + [entry]
    }
}

/// A monotonic clock for the playback logic (not affected by changes of the wall-clock time).
struct MonotonicClock: PlaybackClock {
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
}
