import Foundation
import AVFoundation
import CoreMedia
import PlaybackStatus
import AppLogic
import RemuxEngine

/// Reads what the system player can tell about the file and the output, for the Playback Stats overlay. Anything the
/// player does not report stays nil and is shown as "—" (never guessed).
@MainActor
final class PlaybackProbe {
    private let item: AVPlayerItem
    private var width: Int?
    private var height: Int?
    private var frameRate: Double?
    private var videoCodec: String?
    private var hdr: HDRFormat?
    private var transfer: String?
    private var audio: AudioTrackContent?

    /// Set when the converting player is in use: what the file holds is then known exactly from the engine, not guessed from tracks.
    private let remux: RemuxPlayback?
    private var selectedAudioTrack: Int?

    init(item: AVPlayerItem, remux: RemuxPlayback? = nil) {
        self.item = item
        self.remux = remux
    }

    /// Looks up which audio rendition the player is using, so the status describes that one and not the default.
    /// Matches by position in the group first (the engine lists audio in the same order), and by name when the counts differ.
    func refreshAudioSelection() async {
        guard let remux, let group = try? await item.asset.loadMediaSelectionGroup(for: .audible),
              let option = item.currentMediaSelection.selectedMediaOption(in: group) else { return }
        let audio = remux.info.audio
        if group.options.count == audio.count, let index = group.options.firstIndex(of: option) {
            selectedAudioTrack = audio[index].trackNumber
        } else if let match = audio.first(where: { $0.name == option.displayName }) {
            selectedAudioTrack = match.trackNumber
        }
    }

    /// Looks at the tracks once, after playback starts.
    func load() async {
        guard let tracks = try? await item.asset.load(.tracks) else { return }
        for track in tracks {
            if track.mediaType == .video, videoCodec == nil {
                if let rate = try? await track.load(.nominalFrameRate), rate > 0 { frameRate = Double(rate) }
                if let descriptions = try? await track.load(.formatDescriptions), let first = descriptions.first {
                    readVideo(first)
                }
            } else if track.mediaType == .audio, audio == nil {
                if let descriptions = try? await track.load(.formatDescriptions), let first = descriptions.first {
                    audio = Self.audioContent(first)
                }
            }
        }
    }

    private func readVideo(_ description: CMFormatDescription) {
        switch CMFormatDescriptionGetMediaSubType(description) {
        case kCMVideoCodecType_HEVC: videoCodec = "HEVC"
        case kCMVideoCodecType_H264: videoCodec = "H.264"
        default: videoCodec = nil
        }
        let extensionValue = CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_TransferFunction)
        transfer = extensionValue as? String
        if transfer == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String) {
            hdr = .hdr10
        } else if transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String) {
            hdr = .hlg
        } else if transfer != nil {
            hdr = .sdr
        }
    }

    private static func audioContent(_ description: CMFormatDescription) -> AudioTrackContent? {
        let channels = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee.mChannelsPerFrame ?? 2
        let kind: AudioCodecKind
        switch CMFormatDescriptionGetMediaSubType(description) {
        case kAudioFormatAC3: kind = .ac3
        case kAudioFormatEnhancedAC3: kind = .eac3
        case kAudioFormatMPEG4AAC: kind = .aac
        case kAudioFormatFLAC: kind = .flac
        case kAudioFormatLinearPCM: kind = .pcm
        default: return nil
        }
        return AudioTrackContent(kind: kind, channels: Int(channels))
    }

    func snapshot(player: AVPlayer) -> PlaybackStatsSnapshot {
        var s = PlaybackStatsSnapshot()
        let size = item.presentationSize
        if size.width > 0, size.height > 0 {
            width = Int(size.width)
            height = Int(size.height)
        }
        s.width = width
        s.height = height
        s.frameRate = frameRate
        s.videoCodec = videoCodec
        s.hdr = hdr
        s.audio = audio
        s.decodePath = .direct
        s.engine = .primary
        s.container = (item.asset as? AVURLAsset).map { $0.url.pathExtension.uppercased() }
        if let remux {
            // The converting player knows the file exactly: those facts replace anything read back from the stream it produced.
            let known = RemuxPlaybackModel.snapshot(remux.info, selectedTrack: selectedAudioTrack)
            s.width = known.width ?? s.width
            s.height = known.height ?? s.height
            s.videoCodec = known.videoCodec
            s.hdr = known.hdr
            s.audio = known.audio
            s.decodePath = .remux
            s.container = known.container
        }
        if let event = item.accessLog()?.events.last {
            if event.observedBitrate > 0 { s.liveBitrate = event.observedBitrate }
            if event.indicatedAverageBitrate > 0 { s.averageBitrate = event.indicatedAverageBitrate }
            if event.numberOfDroppedVideoFrames >= 0 { s.droppedFrames = event.numberOfDroppedVideoFrames }
        }
        if let range = item.loadedTimeRanges.first?.timeRangeValue {
            let ahead = (range.start + range.duration).seconds - player.currentTime().seconds
            if ahead.isFinite, ahead >= 0 { s.bufferSeconds = ahead }
        }
        return s
    }

    /// The honest audio and video lines. Only built when the file's audio and picture format are both known.
    func status(for snapshot: PlaybackStatsSnapshot) -> PlaybackStatus? {
        guard let audio = snapshot.audio, let format = snapshot.hdr else { return nil }
        let profile7 = remux.map { RemuxPlaybackModel.profile7Conversion($0.info) } ?? .notAvailableOnDevice
        return StatusRules.status(track: audio, route: Self.currentRoute(), format: format, display: Self.currentDisplay(),
                                  engine: .primary, profile7: profile7)
    }

    private static func currentRoute() -> AudioRoute {
        let session = AVAudioSession.sharedInstance()
        let port = session.currentRoute.outputs.first?.portType
        let kind: AudioRouteKind
        switch port {
        case .some(.HDMI): kind = .hdmi
        case .some(.bluetoothA2DP), .some(.bluetoothLE), .some(.bluetoothHFP): kind = .bluetooth
        case .some(.airPlay): kind = .airPlay
        case .some(.builtInSpeaker): kind = .builtIn
        default: kind = .unknown
        }
        return RouteClassifier.classify(kind: kind, maxChannels: session.maximumOutputNumberOfChannels, atmosRenderingReported: nil)
    }

    private static func currentDisplay() -> DisplayState {
        var modes: DisplayHDRModes = []
        // PROVISIONAL: availableHDRModes is marked deprecated (developer.apple.com/documentation/avfoundation/avplayer/availablehdrmodes,
        // "use eligibleForHDRPlayback"), but that replacement is a single Bool and cannot say WHICH modes exist, which the stats
        // overlay needs. Kept: it compiles with a deprecation warning only. Alternative: eligibleForHDRPlayback with no per-mode detail.
        let available = AVPlayer.availableHDRModes
        if available.contains(.hlg) { modes.insert(.hlg) }
        if available.contains(.hdr10) { modes.insert(.hdr10) }
        if available.contains(.dolbyVision) { modes.insert(.dolbyVision) }
        // No API says whether HDR10+ metadata is sent; it depends on the hardware model (DeviceVideoCapabilities).
        return DisplayState(availableHDR: modes, activeMode: nil, matchDynamicRange: .unknown,
                            sendsHDR10Plus: DeviceVideoCapabilities.sendsHDR10Plus(modelIdentifier: hardwareModel))
    }

    /// The hardware model identifier (`uname` machine field).
    private static let hardwareModel: String = {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }()
}
