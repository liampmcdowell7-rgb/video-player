import Foundation
import VideoPlayerCore

// The remux session: opens a Matroska file through a `ByteRangeReader`, plans segments, and answers requests for
// playlists, init segments and fMP4 media segments. Everything is built on demand from windows read by the demuxer;
// nothing is written to disk.

public struct RemuxOptions: Sendable {
    public var budget = EngineBudget()
    /// Overrides the segment length derived from the budget (tests).
    public var targetSegmentSeconds: Double?
    /// Matroska track numbers of the audio tracks to offer; nil offers every supported one.
    public var audioTrackNumbers: [Int]?
    /// Decoder for DTS / TrueHD and friends (outputs FLAC). Without it those tracks are listed as skipped.
    public var audioTranscoder: (any AudioTranscoding)?
    /// Profile 7 to 8.1 conversion. Without it a profile 7 file is played as its HDR10 base layer.
    public var dolbyVisionConverter: (any DolbyVisionConverting)?
    public var clock: any EngineClock = SystemEngineClock()
    public init() {}
}

public struct AudioRenditionInfo: Equatable, Sendable {
    public var trackNumber: Int
    public var name: String
    public var language: String
    public var codecID: String
    public var codecString: String
    public var channels: Int
    public var isDefault: Bool
    public var transcoded: Bool
    /// E-AC-3 with Dolby Atmos (JOC) signalled in the stream (EAC3Atmos, PROVISIONAL).
    public var isAtmos = false
    /// Decoded tracks only: what the source really is and what the output keeps (AudioDecode, docs/AUDIO_PIPELINE.md).
    public var transcodedSource: TranscodedAudioSource? = nil
}

public struct SkippedTrack: Equatable, Sendable {
    public var trackNumber: Int
    public var codecID: String
    public var reason: String
}

public struct RemuxMediaInfo: Sendable {
    public var durationSeconds: Double
    public var segmentCount: Int
    public var targetSegmentSeconds: Double
    /// Seconds added to every presentation time so that all decode times are non-negative (the video decode delay).
    /// A player position `p` corresponds to the file time `p - timelineOffsetSeconds + firstKeyframeSeconds`.
    public var timelineOffsetSeconds: Double
    public var firstKeyframeSeconds: Double
    public var videoCodecString: String
    public var supplementalCodecs: String?
    public var videoRange: VideoRange
    public var width: Int
    public var height: Int
    public var sampleEntry: String
    public var audio: [AudioRenditionInfo]
    public var skippedAudio: [SkippedTrack]
    /// The file's preferred audio track could not be offered and another one plays by default (shown on screen).
    public var audioFallback: AudioFallbackInfo? = nil
    public var subtitleTrackNumbers: [Int]
    public var usedClusterScan: Bool
    /// R441: the phases of `prepare()` with their read counts and times (nil for a session built from a prepared demuxer elsewhere).
    public var prepareDiagnostics: PrepareDiagnostics? = nil
    public var isOverBudget: Bool
    public var warnings: [String]
    /// Text subtitle tracks offered as WebVTT renditions (the system subtitle menu).
    public var subtitles: [SubtitleRenditionInfo] = []
    /// PGS tracks: NOT renditions; the app's one custom menu offers them and reads `.sup` data (`seg_pgs_<track>_<k>.sup`).
    public var pictureSubtitles: [PictureSubtitleInfo] = []
    public var skippedSubtitles: [SkippedSubtitle] = []
    /// Dolby Vision profile number found in the file (nil: none).
    public var dolbyVisionSourceProfile: Int? = nil
    /// From the file's Dolby Vision configuration record: an enhancement layer is present (profile 7 FEL or MEL), and the
    /// base-layer compatibility id (1 HDR10, 2 SDR, 4 HLG; 0 none). nil when the file has no Dolby Vision record.
    public var dolbyVisionEnhancementLayer: Bool? = nil
    public var dolbyVisionCompatibilityID: Int? = nil
    /// Dolby Vision profile signalled to the player (nil: none; 7 never appears here, it is converted to 8 or dropped).
    public var dolbyVisionOutputProfile: Int? = nil
    /// Profile 7 was converted to 8.1 by a `DolbyVisionConverting` implementation.
    public var dolbyVisionConverted = false
    /// The stream carries mastering display or content light level data (written to the init segment).
    public var hasHDRStaticMetadata = false
    /// Profile 7 only: full (FEL) or minimal (MEL) enhancement layer, read from the first RPU (the record cannot tell them
    /// apart: both set el_present). nil when unknown (no converter to read the RPU, or no RPU).
    public var dolbyVisionEnhancementLayerType: DolbyVisionSampleInfo.EnhancementLayer? = nil
    /// A converter was supplied but the first access unit could not be converted: the HDR10 base layer plays.
    public var dolbyVisionConversionFailed = false
    /// The file had no Dolby Vision record; it was derived from the first RPU (profile) and the picture size and rate (level).
    public var dolbyVisionRecordDerived = false
    /// HDR10+ dynamic metadata (ST 2094-40 SEI) found in the first keyframe. The samples always keep it unchanged.
    public var hasHDR10PlusMetadata = false
}

public protocol SegmentProvider: Sendable {
    /// Answers a resource path relative to the session base URL ("master.m3u8", "seg_video_3.m4s", ...).
    func resource(path: String) async throws -> LoopbackResponse
}

public protocol RemuxSession: SegmentProvider {
    func prepare() async throws -> RemuxMediaInfo
    func segmentIndex(forSeconds seconds: Double) async -> Int
    func cancel() async
}

public actor MatroskaRemuxSession: RemuxSession {
    private let reader: any ByteRangeReader
    /// R441: counts every read the session makes (prepare reports its phases from it).
    private let tally: ReadTally
    private let options: RemuxOptions
    private let writer: FMP4Writer
    private var demuxer: (any MediaDemuxer)?
    private var seekMap = SeekMap([])
    private var planner: ReadAheadPlanner?
    private var windows: [Int: Task<DemuxedWindow, Error>] = [:]
    private var info: RemuxMediaInfo?
    private var videoTrack: MKVTrack?
    private var videoConfig: VideoTrackConfig?
    private var timeline: VideoTimeline?
    private var audioConfigs: [Int: AudioTrackConfig] = [:]
    private var audioAnchors: [Int: Int64] = [:]       // first frame time of each audio track (ns)
    private var audioOrder: [Int] = []
    private var transcoded: Set<Int> = []
    private var textSubtitles: [Int: (track: MKVTrack, format: SubtitleTextFormat)] = [:]
    private var textSubtitleOrder: [Int] = []
    private var pictureTracks: [Int: MKVTrack] = [:]
    private var cancelled = false
    /// How the samples of a Dolby Vision file are rewritten (decided once in `prepare`), and the record the file had (or
    /// the one derived from its first RPU).
    private var dvSamples: DolbyVisionSampleMode = .untouched
    private var dvFacts = DolbyVisionFacts()
    /// Windows read only because a subtitle segment asked for them (diagnostics for the device test: AVPlayer's
    /// subtitle prefetch behaviour decides how much of the file this costs).
    public private(set) var subtitleWindowLoads = 0
    public private(set) var windowLoads = 0
    /// Diagnostics: the most windows held at once and the biggest window read so far (bytes).
    public private(set) var peakCachedWindows = 0
    public private(set) var largestWindowBytes: Int64 = 0
    public var cachedWindowCount: Int { windows.count }

    public init(reader: any ByteRangeReader, options: RemuxOptions = RemuxOptions(), writer: FMP4Writer = FMP4Writer()) {
        let t = ReadTally(reader)
        self.tally = t; self.reader = t; self.options = options; self.writer = writer
    }

    /// Test seam: use a prepared demuxer instead of opening the file.
    public init(demuxer: any MediaDemuxer, reader: any ByteRangeReader, options: RemuxOptions = RemuxOptions()) {
        let t = ReadTally(reader)
        self.tally = t; self.reader = t; self.options = options; self.writer = FMP4Writer(); self.demuxer = demuxer
    }

    // MARK: Prepare

    public func prepare() async throws -> RemuxMediaInfo {
        if let info { return info }
        var warnings: [String] = []
        var recorder = PrepareRecorder(tally: tally)
        let cached = BlockCachedReader(reader)
        let index: MKVIndex
        if let d = demuxer { index = d.index } else { index = try await MatroskaIndexer.load(from: cached) }
        recorder.end("index load")
        guard let video = index.videoTrack else { throw RemuxError.unsupported("no video track") }
        let isHEVC = video.codecID == "V_MPEGH/ISO/HEVC"
        let isAVC = video.codecID == "V_MPEG4/ISO/AVC"
        guard isHEVC || isAVC else { throw RemuxError.unsupported("video codec \(video.codecID)") }

        // Keyframes: Cues when present, else a scan of cluster headers.
        var keys = index.cues.filter { $0.track == video.number }.map { VideoKeyframe(timeNs: $0.timeNs, clusterOffset: $0.clusterOffset) }
        var scanned = false
        if keys.isEmpty {
            let found = try await MatroskaClusterScanner.scan(reader: reader, index: index, videoTrack: video.number)
            keys = found.map { VideoKeyframe(timeNs: $0.timeNs, clusterOffset: $0.clusterOffset) }
            scanned = true
            warnings.append("no Cues: keyframes found by scanning \(keys.count) cluster headers")
            recorder.end("cluster scan (\(keys.count) clusters)")
        } else {
            recorder.end("cues (\(keys.count) keyframes, no further reads)")
        }
        guard !keys.isEmpty else { throw RemuxError.malformed("no keyframes found") }
        let firstKey = keys.map { $0.timeNs }.min() ?? 0
        var durationNs = index.durationNs
        if durationNs <= (keys.map { $0.timeNs }.max() ?? 0) {
            durationNs = (keys.map { $0.timeNs }.max() ?? 0) + 2_000_000_000
            warnings.append("segment duration missing: end of media estimated")
        }
        let mediaEndNs = max(durationNs, firstKey)

        // Segment length from the memory budget.
        let seconds = Double(mediaEndNs - firstKey) / 1e9
        let bitrate = seconds > 0 ? Double(index.fileSize) * 8 / seconds : 0
        let target = options.targetSegmentSeconds ?? options.budget.targetSegmentSeconds(bitrate: bitrate)
        let overBudget = options.budget.isOverBudget(bitrate: bitrate)
        if overBudget { warnings.append("bitrate \(Int(bitrate / 1e6)) Mbps exceeds the memory budget: one window, no read-ahead") }
        let plan = SegmentPlanner.plan(keyframes: keys, mediaEndNs: mediaEndNs, targetNs: Int64(target * 1e9))
        seekMap = SeekMap(plan)
        if demuxer == nil { demuxer = MatroskaDemuxer(reader: reader, index: index) }
        videoTrack = video

        // Which audio tracks to offer.
        var offered: [MKVTrack] = []
        var skipped: [SkippedTrack] = []
        let supported: Set<String> = ["A_AC3", "A_EAC3", "A_AAC", "A_FLAC"]
        for t in index.audioTracks {
            if let wanted = options.audioTrackNumbers, !wanted.contains(t.number) { continue }
            if supported.contains(t.codecID) || t.codecID.hasPrefix("A_AAC") { offered.append(t) }
            else if let tc = options.audioTranscoder, tc.supportedCodecIDs.contains(t.codecID) { offered.append(t); transcoded.insert(t.number) }
            else { skipped.append(SkippedTrack(trackNumber: t.number, codecID: t.codecID, reason: "codec not playable by AVPlayer and no decoder supplied")) }
        }

        // Subtitle tracks: text tracks become WebVTT renditions, PGS is listed for the app's menu, the rest is reported.
        var textInfos: [SubtitleRenditionInfo] = []
        var pictureInfos: [PictureSubtitleInfo] = []
        var skippedSubs: [SkippedSubtitle] = []
        for t in index.subtitleTracks {
            switch SubtitleClassifier.classify(codecID: t.codecID) {
            case .text(let f):
                textSubtitles[t.number] = (t, f); textSubtitleOrder.append(t.number)
                textInfos.append(SubtitleRenditionInfo(trackNumber: t.number, name: subtitleName(t), language: t.language, isDefault: t.isDefault,
                                                       isForced: t.isForced, isHearingImpaired: t.isHearingImpaired, format: f))
            case .picture:
                pictureTracks[t.number] = t
                pictureInfos.append(PictureSubtitleInfo(trackNumber: t.number, name: subtitleName(t), language: t.language, isDefault: t.isDefault,
                                                        isForced: t.isForced, isHearingImpaired: t.isHearingImpaired))
            case .unsupported(let why):
                skippedSubs.append(SkippedSubtitle(trackNumber: t.number, codecID: t.codecID, reason: why))
            }
        }

        // Planner for read-ahead.
        planner = ReadAheadPlanner(config: ReadAheadPlanner.Config(budget: options.budget, bitrate: bitrate, segmentSeconds: target, segmentCount: plan.count))

        recorder.end("planning")
        // First window: parameter sets, SEI and the first frame of each audio track (and the subtitle blocks of that window).
        let wanted = Set([video.number] + offered.map { $0.number } + textSubtitleOrder + pictureTracks.keys)
        let first = try await loadWindow(0, tracks: wanted)
        recorder.end("first window")
        let firstVideo = first.frames.first { $0.track == video.number && $0.isKeyframe }
        guard let firstVideo else { throw RemuxError.malformed("first segment has no video keyframe") }

        let vconfig = try buildVideoConfig(video, firstKeyframe: Array(firstVideo.data), isHEVC: isHEVC, warnings: &warnings)
        videoConfig = vconfig.config
        let tl = VideoTimeline(originNs: firstKey, frameNs: vconfig.frameNs, delayFrames: vconfig.reorder)
        timeline = tl

        var renditions: [AudioRenditionInfo] = []
        for t in offered {
            guard let f = first.frames.first(where: { $0.track == t.number && $0.timeNs >= firstKey - tl.delayNs }) else {
                skipped.append(SkippedTrack(trackNumber: t.number, codecID: t.codecID, reason: "no audio frame in the first segment")); continue
            }
            do {
                // A decoder gets every frame of the track in the first window (a TrueHD stream decodes from its next major sync).
                let firstFrames = first.frames.filter { $0.track == t.number && $0.timeNs >= f.timeNs }
                let cfg = try await audioConfig(for: t, firstFrame: Array(f.data), firstFrames: firstFrames)
                audioConfigs[t.number] = cfg
                audioAnchors[t.number] = f.timeNs
                audioOrder.append(t.number)
                var rendition = AudioRenditionInfo(trackNumber: t.number, name: audioName(t), language: t.language, codecID: t.codecID,
                                                   codecString: cfg.codecString, channels: cfg.channels, isDefault: t.isDefault,
                                                   transcoded: transcoded.contains(t.number), isAtmos: cfg.isAtmos)
                if transcoded.contains(t.number), let tc = options.audioTranscoder { rendition.transcodedSource = await tc.sourceInfo(for: t) }
                renditions.append(rendition)
            } catch {
                skipped.append(SkippedTrack(trackNumber: t.number, codecID: t.codecID, reason: "\(error)"))
            }
        }
        // HLS allows one DEFAULT=YES rendition per group: the first track flagged default (else the first track).
        if !renditions.isEmpty {
            let chosen = renditions.firstIndex(where: { $0.isDefault }) ?? 0
            for i in renditions.indices { renditions[i].isDefault = (i == chosen) }
        }
        // The file's preferred audio track (flagged default, else the first one) could not be offered: the best other track
        // plays by default instead, and the app says so on screen (AudioTrackRanking, PROVISIONAL rule).
        var audioFallback: AudioFallbackInfo? = nil
        let considered = index.audioTracks.filter { options.audioTrackNumbers?.contains($0.number) ?? true }
        if let preferred = considered.first(where: { $0.isDefault }) ?? considered.first,
           let lost = skipped.first(where: { $0.trackNumber == preferred.number }) {
            let lossless = Set(renditions.filter { $0.codecID == "A_FLAC" || $0.transcodedSource?.isLossless == true }.map { $0.trackNumber })
            let pick = AudioTrackRanking.replacement(for: preferred, among: renditions, losslessTracks: lossless)
            if let pick { for i in renditions.indices { renditions[i].isDefault = renditions[i].trackNumber == pick.trackNumber } }
            audioFallback = AudioFallbackInfo(unplayable: lost, replacement: pick?.trackNumber)
        }

        recorder.end("track set-up")
        let (codecs, supplemental, range) = variantAttributes(vconfig.config)
        var result = RemuxMediaInfo(
            durationSeconds: Double(mediaEndNs - firstKey) / 1e9, segmentCount: plan.count, targetSegmentSeconds: target,
            timelineOffsetSeconds: Double(tl.delayTicks) / 90000, firstKeyframeSeconds: Double(firstKey) / 1e9,
            videoCodecString: codecs, supplementalCodecs: supplemental, videoRange: range,
            width: vconfig.config.width, height: vconfig.config.height, sampleEntry: vconfig.config.sampleEntry,
            audio: renditions, skippedAudio: skipped, audioFallback: audioFallback, subtitleTrackNumbers: index.subtitleTracks.map { $0.number },
            usedClusterScan: scanned, isOverBudget: overBudget, warnings: warnings,
            subtitles: textInfos, pictureSubtitles: pictureInfos, skippedSubtitles: skippedSubs,
            dolbyVisionSourceProfile: dvFacts.source?.profile, dolbyVisionEnhancementLayer: dvFacts.source?.elPresent,
            dolbyVisionCompatibilityID: dvFacts.source?.blCompatibilityID, dolbyVisionOutputProfile: vconfig.config.dolbyVision?.profile,
            dolbyVisionConverted: dvSamples == .convertAll,
            hasHDRStaticMetadata: !vconfig.config.hdr.isEmpty,
            dolbyVisionEnhancementLayerType: dvFacts.enhancementLayer, dolbyVisionConversionFailed: dvFacts.conversionFailed,
            dolbyVisionRecordDerived: dvFacts.derived, hasHDR10PlusMetadata: dvFacts.hdr10Plus)
        result.prepareDiagnostics = recorder.diagnostics
        info = result
        return result
    }

    private func audioName(_ t: MKVTrack) -> String {
        if !t.name.isEmpty { return t.name }
        return t.language.isEmpty ? "Track \(t.number)" : t.language
    }

    private func subtitleName(_ t: MKVTrack) -> String {
        if !t.name.isEmpty { return t.name }
        let lang = PlaylistWriter.bcp47(t.language)
        if let lang, let shown = Locale.current.localizedString(forLanguageCode: lang), !shown.isEmpty { return shown.prefix(1).uppercased() + shown.dropFirst() }
        return t.language.isEmpty || t.language == "und" ? "Subtitles \(t.number)" : t.language
    }

    private func audioConfig(for t: MKVTrack, firstFrame: [UInt8], firstFrames: [MKVFrame]) async throws -> AudioTrackConfig {
        if transcoded.contains(t.number), let tc = options.audioTranscoder {
            return try await tc.outputConfig(for: t, firstFrames: firstFrames)
        }
        switch t.codecID {
        case "A_AC3": return try AudioConfigBuilder.ac3(track: t, firstFrame: firstFrame)
        case "A_EAC3": return try AudioConfigBuilder.eac3(track: t, firstAccessUnit: firstFrame)
        case "A_FLAC": return try AudioConfigBuilder.flac(track: t)
        default: return try AudioConfigBuilder.aac(track: t)
        }
    }

    // MARK: Video configuration

    private struct BuiltVideo { var config: VideoTrackConfig; var frameNs: Double?; var reorder: Int }

    private func buildVideoConfig(_ t: MKVTrack, firstKeyframe: [UInt8], isHEVC: Bool, warnings: inout [String]) throws -> BuiltVideo {
        let frameNs: Double? = t.defaultDurationNs.map { Double($0) }
        let fps: Double? = frameNs.map { 1e9 / $0 }
        if !isHEVC {
            let avc = try AVCConfig(parsing: t.codecPrivate)
            let colour = Self.colour(from: t.colour, sps: nil)
            let cfg = VideoTrackConfig(trackID: UInt32(t.number), codec: .avc(avc), width: t.pixelWidth, height: t.pixelHeight,
                                       sampleEntry: "avc1", colour: colour, hdr: HDRStaticMetadata(), dolbyVision: nil,
                                       language: t.language, frameRate: fps)
            // The H.264 SPS is not parsed: allow two frames of reordering (B-pyramid); a deeper stream throws on the first segment that needs it.
            warnings.append("H.264 reorder depth assumed to be 2 frames")
            return BuiltVideo(config: cfg, frameNs: frameNs, reorder: 2)
        }
        let hvcc = try HVCConfig(parsing: t.codecPrivate)
        let sps = hvcc.nalus(ofType: HEVCNAL.sps).first.flatMap { HEVCSPS.parse($0) }
        var hdr = HEVCSEI.staticMetadata(config: hvcc, firstKeyframe: firstKeyframe)
        if let m = t.colour?.mastering { hdr.mdcv = HEVCSEI.mdcvPayload(m) }
        if let c = t.colour, let cll = c.maxCLL, let fall = c.maxFALL {
            hdr.clli = [UInt8(truncatingIfNeeded: cll >> 8), UInt8(truncatingIfNeeded: cll), UInt8(truncatingIfNeeded: fall >> 8), UInt8(truncatingIfNeeded: fall)]
        }
        let reorder = sps?.maxNumReorderPics ?? 2
        let fpsForLevel = fps ?? 24
        let decided = DolbyVisionPlanner.decide(record: t.dolbyVision, firstKeyframe: firstKeyframe, lengthSize: hvcc.lengthSize,
                                                converter: options.dolbyVisionConverter, transfer: Self.colour(from: t.colour, sps: sps)?.transfer,
                                                width: sps?.width ?? t.pixelWidth, height: sps?.height ?? t.pixelHeight,
                                                framesPerSecond: fpsForLevel, warnings: &warnings)
        dvSamples = decided.mode
        dvFacts = decided.facts
        let dv = decided.signalled
        let entry = (dv?.profile == 5) ? "dvh1" : "hvc1"
        if sps == nil { warnings.append("SPS not parsed: reorder depth assumed to be 2 frames") }
        let width = sps?.width ?? t.pixelWidth, height = sps?.height ?? t.pixelHeight
        let cfg = VideoTrackConfig(trackID: UInt32(t.number), codec: .hevc(hvcc), width: t.displayWidth != nil ? t.pixelWidth : width,
                                   height: t.displayHeight != nil ? t.pixelHeight : height, sampleEntry: entry,
                                   colour: Self.colour(from: t.colour, sps: sps), hdr: hdr, dolbyVision: dv,
                                   language: t.language, frameRate: fps)
        return BuiltVideo(config: cfg, frameNs: frameNs, reorder: reorder)
    }

    static func colour(from c: MKVColour?, sps: HEVCSPSInfo?) -> ColourInfo? {
        let primaries = c?.primaries ?? sps?.colourPrimaries
        let transfer = c?.transfer ?? sps?.transferCharacteristics
        let matrix = c?.matrix ?? sps?.matrixCoefficients
        guard primaries != nil || transfer != nil || matrix != nil else { return nil }
        let full: Bool = (c?.range).map { $0 == 2 } ?? (sps?.fullRange ?? false)
        return ColourInfo(primaries: primaries ?? 2, transfer: transfer ?? 2, matrix: matrix ?? 2, fullRange: full)
    }

    private func variantAttributes(_ v: VideoTrackConfig) -> (codecs: String, supplemental: String?, range: VideoRange) {
        var range: VideoRange = .sdr
        if let t = v.colour?.transfer { range = t == 16 ? .pq : (t == 18 ? .hlg : .sdr) }
        guard let dv = v.dolbyVision else {
            // HDR10+: the base CODECS plus the 'cdm4' brand in SUPPLEMENTAL-CODECS (HLS authoring spec, SUPPLEMENTAL-CODECS).
            // PROVISIONAL: Apple's only example is AV1; the HEVC form is by analogy. Alternative: no attribute (the SEI is
            // still in every sample either way).
            if dvFacts.hdr10Plus && range == .pq { return (v.codecString, v.codecString + "/cdm4", range) }
            return (v.codecString, nil, range)
        }
        let level = String(format: "%02d", dv.level)
        if dv.profile == 5 { return ("dvh1.05.\(level)", nil, .pq) }
        let brand: String
        switch dv.blCompatibilityID { case 1: brand = "db1p"; case 2: brand = "db2g"; case 4: brand = "db4h"; default: brand = "db1p" }
        return (v.codecString, "dvh1.\(String(format: "%02d", dv.profile)).\(level)/\(brand)", range)
    }

    // MARK: Windows and read-ahead

    private var allTracks: Set<Int> {
        var s = Set(audioOrder)
        s.formUnion(textSubtitleOrder)
        s.formUnion(pictureTracks.keys)
        if let v = videoTrack { s.insert(v.number) }
        return s
    }

    private func loadWindow(_ k: Int, tracks: Set<Int>? = nil, forSubtitles: Bool = false) async throws -> DemuxedWindow {
        if let existing = windows[k] { return try await existing.value }
        guard let demuxer, k >= 0, k < seekMap.segments.count else { throw RemuxError.notFound("segment \(k)") }
        let spec = seekMap.segments[k]
        let next = k + 1 < seekMap.segments.count ? seekMap.segments[k + 1] : nil
        let want = tracks ?? allTracks
        let clock = options.clock
        if !forSubtitles { planner?.started(k) } else { subtitleWindowLoads += 1 }
        windowLoads += 1
        let task = Task<DemuxedWindow, Error> {
            try await demuxer.window(for: spec, next: next, tracks: want)
        }
        windows[k] = task
        peakCachedWindows = max(peakCachedWindows, windows.count)
        let t0 = clock.now
        do {
            let w = try await task.value
            largestWindowBytes = max(largestWindowBytes, w.bytesRead)
            if !forSubtitles { planner?.finished(k, bytes: w.bytesRead, seconds: max(1e-6, clock.now - t0)) }
            return w
        } catch {
            windows[k] = nil
            if !forSubtitles { planner?.failed(k) }
            throw error
        }
    }

    /// Called for every media segment request: starts read-ahead and drops windows the budget no longer holds.
    private func noteRequest(_ k: Int) {
        guard var p = planner else { return }
        let plan = p.requested(k, now: options.clock.now)
        for c in plan.cancel { windows[c]?.cancel(); windows[c] = nil }
        let keep = Set(p.held).union(p.inFlight)
        for key in windows.keys where !keep.contains(key) && key != k { windows[key] = nil }
        planner = p
        for idx in plan.fetch where windows[idx] == nil {
            Task { [weak self] in _ = try? await self?.loadWindow(idx) }
        }
    }

    // MARK: Resources

    public func segmentIndex(forSeconds seconds: Double) -> Int {
        seekMap.index(containing: Int64(seconds * 1e9) + (info.map { Int64($0.firstKeyframeSeconds * 1e9) } ?? 0))
    }

    /// The segment that holds a player position (the item time AVPlayer reports): the video decode delay is taken off first.
    public func segmentIndex(forPlayerSeconds seconds: Double) -> Int {
        segmentIndex(forSeconds: max(0, seconds - (info?.timelineOffsetSeconds ?? 0)))
    }

    public func cancel() {
        cancelled = true
        for (_, t) in windows { t.cancel() }
        windows.removeAll()
    }

    public func resource(path: String) async throws -> LoopbackResponse {
        if cancelled { throw RemuxError.cancelled }
        let info = try await prepare()
        let name = path.hasPrefix("/") ? String(path.dropFirst()) : path
        switch name {
        case "master.m3u8": return playlist(masterPlaylist(info))
        case "video.m3u8": return playlist(mediaPlaylist(initURI: "init_video.mp4", prefix: "seg_video_"))
        case "init_video.mp4":
            guard let v = videoConfig else { throw RemuxError.notFound(name) }
            return mp4(LoopbackBody(writer.initSegment(for: .video(v))))
        default: break
        }
        if name.hasPrefix("audio_"), name.hasSuffix(".m3u8"), let n = Int(name.dropFirst(6).dropLast(5)), audioConfigs[n] != nil {
            return playlist(mediaPlaylist(initURI: "init_audio_\(n).mp4", prefix: "seg_audio_\(n)_"))
        }
        if name.hasPrefix("init_audio_"), name.hasSuffix(".mp4"), let n = Int(name.dropFirst(11).dropLast(4)), let cfg = audioConfigs[n] {
            return mp4(LoopbackBody(writer.initSegment(for: .audio(cfg))))
        }
        if name.hasPrefix("seg_video_"), name.hasSuffix(".m4s"), let k = Int(name.dropFirst(10).dropLast(4)) {
            return try await videoSegment(k)
        }
        if name.hasPrefix("seg_audio_"), name.hasSuffix(".m4s") {
            let parts = name.dropFirst(10).dropLast(4).split(separator: "_")
            if parts.count == 2, let n = Int(parts[0]), let k = Int(parts[1]), audioConfigs[n] != nil { return try await audioSegment(track: n, k) }
        }
        if name.hasPrefix("subs_"), name.hasSuffix(".m3u8"), let n = Int(name.dropFirst(5).dropLast(5)), textSubtitles[n] != nil {
            let segs = seekMap.segments.map { (uri: "seg_subs_\(n)_\($0.index).vtt", seconds: $0.durationSeconds) }
            return playlist(PlaylistWriter.subtitleMedia(segments: segs, targetDuration: seekMap.targetDurationSeconds))
        }
        if name.hasPrefix("seg_subs_"), name.hasSuffix(".vtt") {
            let parts = name.dropFirst(9).dropLast(4).split(separator: "_")
            if parts.count == 2, let n = Int(parts[0]), let k = Int(parts[1]), textSubtitles[n] != nil { return try await subtitleSegment(track: n, k) }
        }
        if name.hasPrefix("seg_pgs_"), name.hasSuffix(".sup") {
            let parts = name.dropFirst(8).dropLast(4).split(separator: "_")
            if parts.count == 2, let n = Int(parts[0]), let k = Int(parts[1]), pictureTracks[n] != nil { return try await pictureSegment(track: n, k) }
        }
        return .notFound()
    }

    private func playlist(_ s: String) -> LoopbackResponse {
        LoopbackResponse(contentType: "application/vnd.apple.mpegurl", body: LoopbackBody(string: s), headers: [("Cache-Control", "no-cache")])
    }

    private func mp4(_ b: LoopbackBody) -> LoopbackResponse { LoopbackResponse(contentType: "video/mp4", body: b) }

    private func masterPlaylist(_ info: RemuxMediaInfo) -> String {
        let avg = info.durationSeconds > 0 ? Int(Double(planner?.config.bitrate ?? 0)) : 0
        let video = PlaylistVideo(codecs: info.videoCodecString, supplementalCodecs: info.supplementalCodecs, range: info.videoRange,
                                  width: info.width, height: info.height, frameRate: videoConfig?.frameRate,
                                  averageBandwidth: avg, bandwidth: Int(Double(avg) * 1.25))
        let audio = info.audio.map {
            PlaylistAudio(trackNumber: $0.trackNumber, name: $0.name, language: $0.language, codecs: $0.codecString, channels: $0.channels,
                          isDefault: $0.isDefault, uri: "audio_\($0.trackNumber).m3u8", isAtmos: $0.isAtmos)
        }
        let subs = info.subtitles.map {
            PlaylistSubtitle(trackNumber: $0.trackNumber, name: $0.name, language: $0.language, isDefault: $0.isDefault, isForced: $0.isForced,
                             isHearingImpaired: $0.isHearingImpaired, uri: "subs_\($0.trackNumber).m3u8")
        }
        return PlaylistWriter.master(video: video, audio: audio, subtitles: subs)
    }

    private func mediaPlaylist(initURI: String, prefix: String) -> String {
        let segs = seekMap.segments.map { (uri: "\(prefix)\($0.index).m4s", seconds: $0.durationSeconds) }
        return PlaylistWriter.media(initURI: initURI, segments: segs, targetDuration: seekMap.targetDurationSeconds)
    }

    // MARK: Segments

    private func videoSegment(_ k: Int) async throws -> LoopbackResponse {
        guard let tl = timeline, let video = videoTrack, let cfg = videoConfig, k >= 0, k < seekMap.segments.count else { return .notFound() }
        noteRequest(k)
        let w = try await loadWindow(k)
        let spec = seekMap.segments[k]
        let isLast = k == seekMap.segments.count - 1
        var frames: [MKVFrame] = []
        var started = false
        for f in w.frames where f.track == video.number {
            if !started { if f.isKeyframe && f.timeNs == spec.startNs { started = true } else { continue } }
            else if f.isKeyframe && f.timeNs >= spec.endNs && !isLast { break }
            frames.append(f)
        }
        guard started, !frames.isEmpty else { throw RemuxError.malformed("segment \(k): keyframe at \(spec.startNs) ns not found in its window") }
        let (samples, base) = try videoSamples(frames, timeline: tl, config: cfg)
        let parts = writer.fragmentParts(for: .video(cfg), sequence: UInt32(k + 1), baseDecodeTime: base, samples: samples)
        return mp4(LoopbackBody(chunks: [parts.head[...]] + parts.samples))
    }

    func videoSamples(_ frames: [MKVFrame], timeline tl: VideoTimeline, config: VideoTrackConfig) throws -> (samples: [FMP4Sample], base: UInt64) {
        let pts = frames.map { tl.tick($0.timeNs) }
        let sorted = pts.sorted()
        let endTick = tl.tickAfter(frames.map { $0.timeNs }.max() ?? 0)
        let lengthSize: Int
        switch config.codec { case .hevc(let c): lengthSize = c.lengthSize; case .avc(let c): lengthSize = c.lengthSize }
        var out: [FMP4Sample] = []
        out.reserveCapacity(frames.count)
        for (i, f) in frames.enumerated() {
            let dts = sorted[i]
            let duration = (i + 1 < sorted.count ? sorted[i + 1] : endTick) - dts
            let cto = pts[i] + tl.delayTicks - dts
            if cto < 0 { throw RemuxError.reorderDepthExceeded(neededTicks: -cto) }
            guard duration >= 0, duration <= Int64(UInt32.max), cto <= Int64(Int32.max) else { throw RemuxError.malformed("video timing out of range") }
            var data = f.data
            if case .hevc = config.codec {
                // Dolby Vision: converted on the fly, sample by sample, from the bytes already read for the remux (no extra read).
                // A single RPU the converter rejects mid-stream does not stop playback: that one frame keeps its base
                // layer only (no RPU, no enhancement layer). PROVISIONAL: alternative is to repeat the previous frame's
                // converted RPU, which would make a sample depend on the one before it (and on seek order).
                switch dvSamples {
                case .untouched: break
                case .convertAll:
                    if let conv = options.dolbyVisionConverter {
                        do { data = ArraySlice(try conv.convert(sample: Array(data), lengthSize: lengthSize)) }
                        catch { data = ArraySlice(try dropDolbyVisionNALs(Array(data), lengthSize: lengthSize)) }
                    }
                case .convertWhereEnhancementLayer:
                    if let conv = options.dolbyVisionConverter, DolbyVisionNAL.hasEnhancementLayer(Array(data), lengthSize: lengthSize) {
                        do { data = ArraySlice(try conv.convert(sample: Array(data), lengthSize: lengthSize)) }
                        catch { data = ArraySlice(try dropDolbyVisionNALs(Array(data), lengthSize: lengthSize)) }
                    }
                case .baseLayerOnly:
                    data = ArraySlice(try dropDolbyVisionNALs(Array(data), lengthSize: lengthSize))
                }
            }
            out.append(FMP4Sample(data: data, duration: UInt32(duration), isSync: f.isKeyframe, compositionOffset: Int32(cto)))
        }
        return (out, UInt64(max(0, sorted.first ?? 0)))
    }

    private func audioSegment(track n: Int, _ k: Int) async throws -> LoopbackResponse {
        guard let cfg = audioConfigs[n], let tl = timeline, let anchor = audioAnchors[n], let track = demuxerTrack(n), k >= 0, k < seekMap.segments.count else { return .notFound() }
        noteRequest(k)
        let w = try await loadWindow(k)
        let spec = seekMap.segments[k]
        let isLast = k == seekMap.segments.count - 1
        let lo = k == 0 ? spec.startNs - tl.delayNs : spec.startNs
        let hi = isLast ? Int64.max : spec.endNs
        var frames = w.frames.filter { $0.track == n && $0.timeNs >= lo && $0.timeNs < hi }
        if transcoded.contains(n), let tc = options.audioTranscoder {
            let input = try await transcodeInput(track: n, k, frames: frames, window: w, hi: hi, anchor: anchor)
            frames = try await tc.transcode(input, track: track, config: cfg)
        }
        if frames.isEmpty { throw RemuxError.malformed("segment \(k): no audio frames for track \(n)") }
        let samplesPerFrame = cfg.samplesPerFrame
        let rate = Double(cfg.sampleRate)
        let frameNs = samplesPerFrame > 0 ? Double(samplesPerFrame) / rate * 1e9 : 0
        let ordinal = frameNs > 0 ? Int64(((Double(frames[0].timeNs - anchor)) / frameNs).rounded()) : 0
        let startOffset = Int64((Double(anchor - tl.originNs + tl.delayNs) * rate / 1e9).rounded())
        let base = frameNs > 0 ? ordinal * Int64(samplesPerFrame) + startOffset
                               : Int64((Double(frames[0].timeNs - tl.originNs + tl.delayNs) * rate / 1e9).rounded())
        let samples: [FMP4Sample] = frames.map { f in
            // FLAC: the frame header holds the real length (the last frame of a stream is shorter than the block size).
            let d = samplesPerFrame > 0 && cfg.codec != .flac ? samplesPerFrame : AudioConfigBuilder.frameSamples(cfg, frame: Array(f.data))
            return FMP4Sample(data: f.data, duration: UInt32(d), isSync: true)
        }
        let parts = writer.fragmentParts(for: .audio(cfg), sequence: UInt32(k + 1), baseDecodeTime: UInt64(max(0, base)), samples: samples)
        return mp4(LoopbackBody(chunks: [parts.head[...]] + parts.samples))
    }

    /// The segment request for a decoding transcoder: the segment's frames, up to 0.5 s of the track before it when the
    /// previous window is still held (decoder warm-up after a seek), and the frames just after it (from this window, and
    /// from the next one when this window ends too early). PROVISIONAL amounts, docs/AUDIO_PIPELINE.md.
    private func transcodeInput(track n: Int, _ k: Int, frames: [MKVFrame], window w: DemuxedWindow, hi: Int64, anchor: Int64) async throws -> AudioTranscodeInput {
        let spec = seekMap.segments[k]
        let isLast = k == seekMap.segments.count - 1
        var preroll: [MKVFrame] = []
        if k > 0, let previous = windows[k - 1], let pw = try? await previous.value {
            preroll = pw.frames.filter { $0.track == n && $0.timeNs < spec.startNs && $0.timeNs >= spec.startNs - 500_000_000 }
        }
        var lookahead: [MKVFrame] = []
        if !isLast {
            let wanted = hi + 300_000_000
            lookahead = w.frames.filter { $0.track == n && $0.timeNs >= hi && $0.timeNs < wanted }
            if (lookahead.last?.timeNs ?? Int64.min) < hi + 200_000_000, k + 1 < seekMap.segments.count, let nw = try? await loadWindow(k + 1) {
                let after = lookahead.last?.timeNs ?? (hi - 1)
                lookahead += nw.frames.filter { $0.track == n && $0.timeNs > after && $0.timeNs >= hi && $0.timeNs < wanted }
            }
        }
        return AudioTranscodeInput(segmentIndex: k, frames: frames, preroll: preroll, lookahead: lookahead,
                                   startNs: k == 0 ? nil : spec.startNs, endNs: isLast ? nil : spec.endNs, anchorNs: anchor)
    }

    /// Running counters of every decoded audio track (stats overlay).
    public func audioDiagnostics() async -> [Int: AudioTranscodeDiagnostics] {
        guard let tc = options.audioTranscoder else { return [:] }
        var out: [Int: AudioTranscodeDiagnostics] = [:]
        for n in transcoded { if let d = await tc.diagnostics(for: n) { out[n] = d } }
        return out
    }

    private func subtitleSegment(track n: Int, _ k: Int) async throws -> LoopbackResponse {
        guard let entry = textSubtitles[n], let tl = timeline, k >= 0, k < seekMap.segments.count else { return .notFound() }
        let w = try await loadWindow(k, forSubtitles: true)
        let (lo, hi) = timeRange(k)
        let cues = WebVTTBuilder.cues(frames: w.frames, track: entry.track, format: entry.format, lo: lo, hi: hi,
                                      originNs: tl.originNs, delaySeconds: Double(tl.delayTicks) / VideoTimeline.scale)
        return LoopbackResponse(contentType: "text/vtt", body: LoopbackBody(string: WebVTTBuilder.segment(cues: cues)), headers: [("Cache-Control", "no-cache")])
    }

    /// PGS data for one segment window as `.sup` bytes (media timeline PTS). For the app's picture-subtitle overlay; not an HLS resource.
    private func pictureSegment(track n: Int, _ k: Int) async throws -> LoopbackResponse {
        guard let track = pictureTracks[n], let tl = timeline, k >= 0, k < seekMap.segments.count else { return .notFound() }
        let w = try await loadWindow(k, forSubtitles: true)
        let (lo, hi) = timeRange(k)
        let bytes = PGSSupWriter.sup(frames: w.frames, track: track, lo: lo, hi: hi, originNs: tl.originNs,
                                     delaySeconds: Double(tl.delayTicks) / VideoTimeline.scale)
        return LoopbackResponse(contentType: "application/octet-stream", body: LoopbackBody(bytes))
    }

    /// The file-time range whose blocks belong to segment `k`: the first segment also takes everything before its keyframe,
    /// the last one everything after, so no block is lost and none is served twice.
    private func timeRange(_ k: Int) -> (Int64, Int64) {
        let spec = seekMap.segments[k]
        return (k == 0 ? Int64.min : spec.startNs, k == seekMap.segments.count - 1 ? Int64.max : spec.endNs)
    }

    private func demuxerTrack(_ n: Int) -> MKVTrack? { demuxer?.index.track(number: n) }
}

/// Maps Matroska timestamps to the 90 kHz video timeline. With a constant frame rate the timestamps are snapped to the
/// frame grid, so segment boundaries line up exactly (Matroska stores milliseconds, which jitters 23.976 fps by +-0.5 ms).
struct VideoTimeline: Sendable {
    let originNs: Int64
    let frameNs: Double?
    let delayFrames: Int
    static let scale = 90000.0

    /// Decode delay in ticks (reorder depth x frame duration).
    var delayTicks: Int64 {
        let one = frameNs.map { $0 * Self.scale / 1e9 } ?? 3750
        return Int64((Double(delayFrames) * one).rounded())
    }
    var delayNs: Int64 { Int64(Double(delayTicks) * 1e9 / Self.scale) }

    func tick(_ ns: Int64) -> Int64 {
        if let f = frameNs, f > 0 {
            let idx = (Double(ns - originNs) / f).rounded()
            return Int64((idx * f * Self.scale / 1e9).rounded())
        }
        return Int64((Double(ns - originNs) * Self.scale / 1e9).rounded())
    }

    /// Tick of the frame after the one at `ns` (the end of that frame).
    func tickAfter(_ ns: Int64) -> Int64 {
        if let f = frameNs, f > 0 {
            let idx = (Double(ns - originNs) / f).rounded() + 1
            return Int64((idx * f * Self.scale / 1e9).rounded())
        }
        return tick(ns) + 3750
    }
}


/// Convenience that wires a session to a loopback server.
public final class RemuxHost: @unchecked Sendable {
    public let session: MatroskaRemuxSession
    public let server: any LoopbackServer
    public private(set) var masterURL: URL?
    public private(set) var info: RemuxMediaInfo?
    /// R390: the first requests of the player and how they were answered (set when the server starts).
    public private(set) var serveLog: LoopbackServeLog?

    public init(reader: any ByteRangeReader, options: RemuxOptions = RemuxOptions(), server: any LoopbackServer = POSIXLoopbackServer()) {
        self.session = MatroskaRemuxSession(reader: reader, options: options)
        self.server = server
    }

    /// Prepares the session, starts the server and returns the URL to hand to AVPlayer.
    public func start() async throws -> URL {
        info = try await session.prepare()
        let s = session
        let log = LoopbackServeLog()
        serveLog = log
        let base = try server.start { request in
            // R390: logged only; the answer is the session's, unchanged.
            let token = log.asked(request.path)
            do {
                let response = try await s.resource(path: request.path)
                log.answered(token, status: response.status)
                return response
            } catch {
                // R441: a thrown error becomes the loopback's 500; the entry keeps the (redacted) text next to it. A cancelled
                // request (the player closed the connection) is no answer.
                let cancelled = error is CancellationError || (error as? RemuxError) == .cancelled
                if cancelled { log.failed(token, error: String(describing: error)) }
                else { log.failed(token, status: 500, error: String(describing: error)) }
                throw error
            }
        }
        let url = base.appendingPathComponent("master.m3u8")
        masterURL = url
        return url
    }

    public func stop() async {
        server.stop()
        await session.cancel()
    }
}
