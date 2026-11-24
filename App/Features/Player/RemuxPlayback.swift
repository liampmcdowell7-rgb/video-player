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
    /// R390: `fileOpened` is called once the file's header is read, before the loopback server starts.
    static func open(reader: any ByteRangeReader, fileOpened: @MainActor () -> Void = {}) async throws -> RemuxPlayback {
        // Profile 7 to 8.1 conversion is part of the engine options (AppLogic, docs/DOLBY_VISION.md).
        var options = RemuxPlaybackModel.engineOptions()
        // R456: Playback > Streaming Cache sets the read-ahead budget (Auto is the engine's own 192 MB).
        options.budget = StreamingCache.stored(UserDefaults.standard.string(forKey: AppPreference.streamingCache.rawValue)).budget
        // DTS, DTS-HD, Dolby TrueHD, MLP, Opus and Vorbis are decoded and repackaged as FLAC (docs/AUDIO_PIPELINE.md).
        let useCore = UserDefaults.standard.object(forKey: SettingsKey.trueHDCompatibilityCore.rawValue) as? Bool
            ?? SettingsKey.trueHDCompatibilityCore.defaultBool
        options.audioTranscoder = DecodedAudioTranscoder(settings: DecodedAudioSettings(trueHDUseEmbeddedCore: useCore))
        let host = RemuxHost(reader: reader, options: options)
        do {
            // `start` prepares the session too; prepared here first so the report can tell reading the file from starting
            // the server (the second `prepare` returns the stored result).
            _ = try await host.session.prepare()
            fileOpened()
            let url = try await host.start()
            guard let info = host.info else { throw PlaybackFailures.damaged }
            return RemuxPlayback(host: host, url: url, info: info)
        } catch {
            await host.stop()
            throw PlaybackFailures.map(error)
        }
    }

    /// R390: the player's first requests to the loopback and their answers, timed on the start's clock (`serverStartedAt`
    /// is when the server started, in seconds since the start was asked for), then the start's resources never asked for.
    func serveLines(serverStartedAt: Double) -> [String] {
        guard let log = host.serveLog else { return ["The loopback server never started."] }
        // R441: what the start's file reads cost, then what the player was served.
        var lines = info.prepareDiagnostics?.lines ?? []
        lines += log.lines(serverStartedAt: serverStartedAt).map { "Loopback " + $0 }
        let missing = log.missing()
        if !missing.isEmpty { lines.append("Loopback never asked for: " + missing.joined(separator: ", ")) }
        return lines
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
