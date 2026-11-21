import Foundation
import AVFoundation
import VideoPlayerCore
import PlaybackLogic
import AppLogic

/// R316: reads the audio of an episode's intro and credits windows as mono samples for the on-device detection
/// (`EpisodeAnalysis`, `SeasonDetectionStore`). Runs at background priority while an episode plays, for that episode and the
/// next one, and never stops playback when it fails: then nothing is learned from that file.
///
/// UNVERIFIED until a device run: whether `AVAssetReader` reads a file over HTTP (Plex, WebDAV) here at all, how long the
/// two windows take on an Apple TV, and whether the system mixes several channels to one when one channel is asked for.
/// Files the system cannot open (Matroska played through the app's own remux, sources read byte by byte) are skipped.
enum EpisodeAudioReader {
    /// 11025 Hz is twice the fingerprint's working rate, so the fingerprinter only halves it.
    static let sampleRate: Double = 11_025

    /// Analyses `target` when it is still unknown and stores the result. Returns true when something was stored.
    @discardableResult
    static func analyse(_ target: SegmentProvider.AnalysisTarget, access: PlaybackAccess, store: (EpisodeAudioRecord) async -> Void) async -> Bool {
        guard case .url(let url, let headers) = access else { return false }
        let options: [String: Any]? = headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let asset = AVURLAsset(url: url, options: options)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return false }
        let intro = target.introWindow.flatMap { samples(asset: asset, track: track, window: $0) }
        guard !Task.isCancelled else { return false }
        let credits = target.creditsWindow.flatMap { samples(asset: asset, track: track, window: $0) }
        guard intro != nil || credits != nil, !Task.isCancelled else { return false }
        let record = EpisodeAnalysis.record(file: target.file,
                                            intro: intro.map { ($0, sampleRate, target.introWindow!.lowerBound) },
                                            credits: credits.map { ($0, sampleRate, target.creditsWindow!.lowerBound) })
        await store(record)
        return true
    }

    /// Mono 32-bit float samples of `window`, nil when the reader cannot open the file or stops early.
    private static func samples(asset: AVURLAsset, track: AVAssetTrack, window: ClosedRange<TimeInterval>) -> [Float]? {
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        reader.timeRange = CMTimeRange(start: CMTime(seconds: window.lowerBound, preferredTimescale: 600),
                                       duration: CMTime(seconds: window.upperBound - window.lowerBound, preferredTimescale: 600))
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        var out: [Float] = []
        out.reserveCapacity(Int((window.upperBound - window.lowerBound) * sampleRate))
        while !Task.isCancelled, let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var chunk = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            let status = chunk.withUnsafeMutableBytes { raw in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
            }
            if status == kCMBlockBufferNoErr { out += chunk }
        }
        if Task.isCancelled { reader.cancelReading(); return nil }
        guard reader.status == .completed, !out.isEmpty else { return nil }
        return out
    }
}
