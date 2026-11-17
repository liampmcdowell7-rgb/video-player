import Foundation
import RemuxEngine
import AppLogic
import AudioDecode

/// One converted playback: the file's bytes are read through a `ByteRangeReader`, rewritten on demand as fragmented MP4 and
/// served on a loopback address, and the player opens that address like any other stream (docs/PLAYBACK_WIRING.md).
///
/// Lives as long as the player screen. `stop()` closes the loopback server and the read-ahead; the player must be stopped first.
@MainActor
final class RemuxPlayback {
    let url: URL
    let info: RemuxMediaInfo
    /// What the person should be told about left-out tracks and limits, most important first.
    let notices: [PlaybackNotice]
    private let host: RemuxHost
    private var stopped = false

    private init(host: RemuxHost, url: URL, info: RemuxMediaInfo) {
        self.host = host
        self.url = url
        self.info = info
        self.notices = RemuxPlaybackModel.notices(info)
    }

    /// Opens the file and starts the loopback server. Throws a `PlaybackFailure` (plain text and a what-to-do line) for any file
    /// the engine cannot handle; nothing is left running when it throws.
    static func open(reader: any ByteRangeReader) async throws -> RemuxPlayback {
        // Profile 7 to 8.1 conversion is part of the engine options (AppLogic, docs/DOLBY_VISION.md).
        var options = RemuxPlaybackModel.engineOptions()
        // DTS, DTS-HD, Dolby TrueHD, MLP, Opus and Vorbis are decoded and repackaged as FLAC (docs/AUDIO_PIPELINE.md).
        let useCore = UserDefaults.standard.object(forKey: SettingsKey.trueHDCompatibilityCore.rawValue) as? Bool
            ?? SettingsKey.trueHDCompatibilityCore.defaultBool
        options.audioTranscoder = DecodedAudioTranscoder(settings: DecodedAudioSettings(trueHDUseEmbeddedCore: useCore))
        let host = RemuxHost(reader: reader, options: options)
        do {
            let url = try await host.start()
            guard let info = host.info else { throw PlaybackFailures.damaged }
            return RemuxPlayback(host: host, url: url, info: info)
        } catch {
            await host.stop()
            throw PlaybackFailures.map(error)
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        let host = self.host
        Task { await host.stop() }
    }

    // MARK: Seeking and picture subtitles

    /// The index of the segment that holds player time `seconds` (the decode delay of the stream is taken into account).
    func segmentIndex(forPlayerSeconds seconds: TimeInterval) async -> Int {
        await host.session.segmentIndex(forPlayerSeconds: seconds)
    }

    var segmentCount: Int { info.segmentCount }

    /// Running notices from the audio decoder (damaged frames concealed, lossless extension missing, layout or rate changes),
    /// for the Playback Stats overlay.
    func audioDiagnosticNotices() async -> [PlaybackNotice] {
        let all = await host.session.audioDiagnostics()
        return all.keys.sorted().flatMap { RemuxPlaybackModel.audioDiagnosticNotices(trackNumber: $0, all[$0]!) }
    }

    /// The picture subtitle data (`.sup` bytes) of one track for one segment window. nil when the engine has none for it.
    func pictureData(track: Int, segment: Int) async -> Data? {
        guard let response = try? await host.session.resource(path: "seg_pgs_\(track)_\(segment).sup"), response.status == 200 else { return nil }
        var data = Data(capacity: response.body.count)
        for chunk in response.body.chunks { data.append(contentsOf: chunk) }
        return data
    }
}
