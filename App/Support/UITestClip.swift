#if DEBUG
import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import LibraryIndex
import AppLogic

/// #21 E: a tiny generated clip that stands in for one sample file (`UITestFixtures.clipEpisodePath`) in `-UITestFixtures`
/// mode, so the screenshot job can draw the player: its controls, the info panel, the audio and subtitle menus, Skip Intro
/// (the sample's `.segments.json`) and Next Episode (the clip ends and Sample Show 1 S01E02 follows). Debug builds only (this
/// whole file is inside `#if DEBUG`; UITestLaunchTests checks it, the Release-string check looks for its file name).
///
/// No real content: coloured frames that change hue every second, silence in two audio tracks (English and French), and two
/// subtitle tracks (English and French) with one invented line each. Written once per launch into the temporary folder with
/// AVAssetWriter (H.264 640×360 at 10 frames a second, AAC stereo, 3GPP text). HDR, Dolby Vision and Atmos cannot be made
/// this way and stay on the device checklist.
///
/// The subtitle tracks are best effort: if the writer refuses them, the clip is written again without them and the
/// subtitle-menu screenshot will show that (unproven until the next run).
///
/// #23 D, kept on purpose: the first CI compile reported 12 AVAssetWriter deprecations here (`add`, `startWriting`,
/// `startSession`, `requestMediaDataWhenReady`, `isReadyForMoreMediaData`, `append`, `markAsFinished`, …; the CI log has the
/// exact list). The replacement (`AVAssetWriter.inputReceiver(for:)`, tvOS 26+, returning an
/// `AVAssetWriterInput.SampleBufferReceiver` whose `append` waits until the input is ready; the writer's `start()` is
/// unverified, from memory) would mean rewriting this file around an API that has never been compiled here, for code that
/// exists only in Debug builds and only feeds the screenshot job. Deprecations are warnings, not errors; the move is left
/// for after the app has compiled and the clip has been seen working once.
enum UITestClip {
    static let seconds = 40
    static let fileName = "uitest-sample-clip.mov"
    static let size = (width: 640, height: 360)
    static let framesPerSecond: Int32 = 10

    /// True for the one sample file the clip stands in for, and only in fixture mode.
    static func standsIn(for file: StoredFile) -> Bool {
        UITestMode.current == .fixtures && file.sourceID == UITestFixtures.sourceID && file.path == UITestFixtures.clipEpisodePath
    }

    @MainActor private static var written: URL?

    /// The clip's file URL, written on first use.
    @MainActor
    static func url() async throws -> URL {
        if let written, FileManager.default.fileExists(atPath: written.path) { return written }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try await write(to: url, subtitles: true)
        } catch {
            try await write(to: url, subtitles: false)
        }
        written = url
        return url
    }

    enum ClipError: Error { case cannotWrite(String) }

    // MARK: Writing

    nonisolated static func write(to url: URL, subtitles: Bool) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
        ])
        video.expectsMediaDataInRealTime = false
        guard writer.canAdd(video) else { throw ClipError.cannotWrite("video") }
        writer.add(video)

        let audioSettings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
                                            AVEncoderBitRateKey: 96_000]
        var audio: [AVAssetWriterInput] = []
        for (code, tag) in [("eng", "en"), ("fra", "fr")] {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = false
            input.languageCode = code
            input.extendedLanguageTag = tag
            guard writer.canAdd(input) else { throw ClipError.cannotWrite("audio \(code)") }
            writer.add(input)
            audio.append(input)
        }
        let audioGroup = AVAssetWriterInputGroup(inputs: audio, defaultInput: audio[0])
        if writer.canAdd(audioGroup) { writer.add(audioGroup) }

        var text: [(input: AVAssetWriterInput, line: String, format: CMFormatDescription)] = []
        if subtitles {
            guard let format = textFormat() else { throw ClipError.cannotWrite("subtitle format") }
            for (code, tag, line) in [("eng", "en", "Sample subtitle line in English."), ("fra", "fr", "Sample subtitle line in French.")] {
                let input = AVAssetWriterInput(mediaType: .subtitle, outputSettings: nil, sourceFormatHint: format)
                input.expectsMediaDataInRealTime = false
                input.languageCode = code
                input.extendedLanguageTag = tag
                guard writer.canAdd(input) else { throw ClipError.cannotWrite("subtitle \(code)") }
                writer.add(input)
                text.append((input, line, format))
            }
            let textGroup = AVAssetWriterInputGroup(inputs: text.map(\.input), defaultInput: nil)
            if writer.canAdd(textGroup) { writer.add(textGroup) }
        }

        guard writer.startWriting() else { throw ClipError.cannotWrite(writer.error?.localizedDescription ?? "start") }
        writer.startSession(atSourceTime: .zero)

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await feed(video, VideoFrames()) }
            for input in audio { group.addTask { await feed(input, Silence()) } }
            for t in text { group.addTask { await feed(t.input, TextSamples(line: t.line, format: t.format)) } }
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw ClipError.cannotWrite(writer.error?.localizedDescription ?? "finish") }
    }

    /// Appends what `samples` makes until it runs out, whenever the input is ready, then marks the input finished.
    nonisolated static func feed(_ input: AVAssetWriterInput, _ samples: some SampleMaker) async {
        let queue = DispatchQueue(label: "uitest-sample-clip.\(input.mediaType.rawValue)")
        let box = FeedState(samples)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    guard let buffer = box.next(), input.append(buffer) else {
                        input.markAsFinished()
                        box.finishOnce { done.resume() }
                        return
                    }
                }
            }
        }
    }

    // MARK: Samples

    /// The 3GPP text sample description (3GPP TS 26.245 "TextSampleEntry", big-endian): white text, transparent background,
    /// bottom-centred, one font. The byte layout is from memory, not from an Apple page (unverified); if CoreMedia rejects it,
    /// the clip is written without subtitles.
    nonisolated static func textFormat() -> CMFormatDescription? {
        var d = Data()
        func u8(_ v: UInt8) { d.append(v) }
        func u16(_ v: UInt16) { d.append(contentsOf: [UInt8(v >> 8), UInt8(v & 0xFF)]) }
        func u32(_ v: UInt32) { d.append(contentsOf: [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]) }
        let font = Array("Sans".utf8)
        let total = 16 + 4 + 2 + 4 + 8 + 12 + (4 + 4 + 2 + 2 + 1 + font.count)
        u32(UInt32(total)); d.append(contentsOf: Array("tx3g".utf8))
        d.append(contentsOf: [0, 0, 0, 0, 0, 0]); u16(1)          // reserved, data reference index
        u32(0)                                                      // display flags
        u8(1); u8(0xFF)                                             // horizontal centre, vertical bottom
        u32(0)                                                      // background RGBA: transparent
        u16(0); u16(0); u16(UInt16(size.height)); u16(UInt16(size.width)) // default text box: top, left, bottom, right
        u16(0); u16(0); u16(1); u8(0); u8(24); u32(0xFFFF_FFFF)     // style: start, end, font 1, plain, 24 pt, white
        u32(UInt32(4 + 4 + 2 + 2 + 1 + font.count)); d.append(contentsOf: Array("ftab".utf8))
        u16(1); u16(1); u8(UInt8(font.count)); d.append(contentsOf: font)
        var format: CMTextFormatDescription?
        let status = d.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return CMTextFormatDescriptionCreateFromBigEndianTextDescriptionData(
                allocator: kCFAllocatorDefault, bigEndianTextDescriptionData: base, size: d.count, flavor: nil,
                mediaType: kCMMediaType_Subtitle, formatDescriptionOut: &format)
        }
        return status == noErr ? format : nil
    }
}

/// Makes the next sample buffer of one track, or nil at the end.
protocol SampleMaker {
    mutating func next() -> CMSampleBuffer?
}

/// Holds one track's sample maker and the "finished" flag for the writer's callback queue (one queue per input).
private final class FeedState<M: SampleMaker>: @unchecked Sendable {
    private var maker: M
    private var finished = false
    init(_ maker: M) { self.maker = maker }
    func next() -> CMSampleBuffer? { maker.next() }
    func finishOnce(_ action: () -> Void) {
        guard !finished else { return }
        finished = true
        action()
    }
}

/// Frames of one colour each, the hue moving every second (so a still screenshot shows a picture, not black).
private struct VideoFrames: SampleMaker {
    var index = 0
    var format: CMVideoFormatDescription?

    mutating func next() -> CMSampleBuffer? {
        let total = UITestClip.seconds * Int(UITestClip.framesPerSecond)
        guard index < total else { return nil }
        defer { index += 1 }
        var pixel: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, UITestClip.size.width, UITestClip.size.height, kCVPixelFormatType_32BGRA,
                                  attributes, &pixel) == kCVReturnSuccess, let pixel else { return nil }
        // R319 (item 9(b)): one even colour per frame. The moving lighter band this drew before sat at x 0–23 on the first
        // frame, which the player pictures showed as a strip at the left edge (`SampleClipFrames`).
        let (r, g, b) = SampleClipFrames.colour(frame: index, framesPerSecond: Int(UITestClip.framesPerSecond))
        CVPixelBufferLockBaseAddress(pixel, [])
        if let base = CVPixelBufferGetBaseAddress(pixel) {
            let rowBytes = CVPixelBufferGetBytesPerRow(pixel)
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<UITestClip.size.height {
                let row = bytes + y * rowBytes
                for x in 0..<UITestClip.size.width {
                    row[x * 4] = b; row[x * 4 + 1] = g; row[x * 4 + 2] = r; row[x * 4 + 3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pixel, [])
        if format == nil {
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel, formatDescriptionOut: &format)
        }
        guard let format else { return nil }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: UITestClip.framesPerSecond),
                                        presentationTimeStamp: CMTime(value: CMTimeValue(index), timescale: UITestClip.framesPerSecond),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel, formatDescription: format,
                                                 sampleTiming: &timing, sampleBufferOut: &sample)
        return sample
    }
}

/// Silence: 16-bit stereo PCM at 48 kHz in tenth-of-a-second buffers (the writer encodes it to AAC).
private struct Silence: SampleMaker {
    static let rate = 48_000
    static let framesPerBuffer = 4_800
    var written = 0
    var format: CMAudioFormatDescription?

    mutating func next() -> CMSampleBuffer? {
        guard written < UITestClip.seconds * Self.rate else { return nil }
        if format == nil {
            var asbd = AudioStreamBasicDescription(mSampleRate: Float64(Self.rate), mFormatID: kAudioFormatLinearPCM,
                                                   mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                                                   mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2,
                                                   mBitsPerChannel: 16, mReserved: 0)
            CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                           magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        }
        guard let format else { return nil }
        let length = Self.framesPerBuffer * 4
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length,
                                                 blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                                                 dataLength: length, flags: kCMBlockBufferAssureMemoryNowFlag,
                                                 blockBufferOut: &block) == kCMBlockBufferNoErr, let block else { return nil }
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: length)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(Self.rate)),
                                        presentationTimeStamp: CMTime(value: CMTimeValue(written), timescale: CMTimeScale(Self.rate)),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
                                  sampleCount: Self.framesPerBuffer, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                  sampleSizeEntryCount: 1, sampleSizeArray: [4], sampleBufferOut: &sample)
        written += Self.framesPerBuffer
        return sample
    }
}

/// 3GPP text samples covering the whole clip: the line for four seconds, then four seconds of nothing, and again.
/// A sample is a 16-bit big-endian length and the UTF-8 text (an empty sample has length 0).
private struct TextSamples: SampleMaker {
    let line: String
    let format: CMFormatDescription
    var start = 0

    init(line: String, format: CMFormatDescription) {
        self.line = line
        self.format = format
    }

    mutating func next() -> CMSampleBuffer? {
        guard start < UITestClip.seconds else { return nil }
        let showing = (start / 4) % 2 == 0
        let utf8 = showing ? Array(line.utf8) : []
        var bytes = [UInt8(utf8.count >> 8), UInt8(utf8.count & 0xFF)] + utf8
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes.count,
                                                 blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                                                 dataLength: bytes.count, flags: kCMBlockBufferAssureMemoryNowFlag,
                                                 blockBufferOut: &block) == kCMBlockBufferNoErr, let block,
              CMBlockBufferReplaceDataBytes(with: &bytes, blockBuffer: block, offsetIntoDestination: 0,
                                            dataLength: bytes.count) == kCMBlockBufferNoErr else { return nil }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 4, timescale: 1), presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: 1),
                                        decodeTimeStamp: .invalid)
        var size = bytes.count
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: 1,
                                  sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size,
                                  sampleBufferOut: &sample)
        start += 4
        return sample
    }
}
#endif
