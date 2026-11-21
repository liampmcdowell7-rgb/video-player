import XCTest
@testable import PlaybackLogic

/// R316: intro and credits detection on synthetic audio. Every episode is generated here: its own "programme" sound (noise
/// shaped differently per episode, seeded), a shared theme tune placed at a different time in each, a cold open of a
/// different length before it. No real media, no downloads.
final class AudioDetectionTests: XCTestCase {
    private let rate = AudioFingerprinter.workingRate

    // MARK: Synthetic audio

    /// A deterministic generator (xorshift), so every run gives the same audio.
    private struct Noise {
        var state: UInt64
        mutating func next() -> Float {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return Float(Double(state % 2_000_001) / 1_000_000 - 1)
        }
    }

    /// The theme tune: a melody of short notes with harmonics, the same for every episode.
    private func theme(seconds: Double) -> [Float] {
        let notes: [Double] = [440, 523.25, 659.25, 587.33, 493.88, 392, 349.23, 698.46, 783.99, 329.63]
        let count = Int(seconds * rate)
        return (0..<count).map { n in
            let t = Double(n) / rate
            let note = notes[Int(t / 0.45) % notes.count] * (1 + 0.05 * Double(Int(t / 4.5) % 3))
            let tone = sin(2 * .pi * note * t) + 0.5 * sin(2 * .pi * 2 * note * t) + 0.25 * sin(2 * .pi * 3 * note * t)
            let envelope = 0.6 + 0.4 * sin(.pi * (t.truncatingRemainder(dividingBy: 0.45)) / 0.45)
            return Float(0.2 * tone * envelope)
        }
    }

    /// Programme sound for an episode: noise through a filter whose colour changes every few seconds, different per seed.
    private func programme(seconds: Double, seed: UInt64) -> [Float] {
        var noise = Noise(state: seed &* 0x9E37_79B9_7F4A_7C15 | 1)
        var low: Float = 0
        let count = Int(seconds * rate)
        var out = [Float](repeating: 0, count: count)
        var colour: Float = 0.5
        for n in 0..<count {
            if n % Int(rate * 3) == 0 { colour = 0.05 + 0.9 * abs(noise.next()) }
            low += colour * (noise.next() - low)
            out[n] = 0.3 * low
        }
        return out
    }

    /// An episode: cold open (programme), the theme at `themeAt`, more programme; `level` scales the theme (a quieter mix).
    private func episode(seed: UInt64, length: Double, themeAt: Double, themeLength: Double, level: Float = 1,
                         hiss: Float = 0) -> [Float] {
        var audio = programme(seconds: length, seed: seed)
        let tune = theme(seconds: themeLength)
        let at = Int(themeAt * rate)
        var noise = Noise(state: seed &+ 77)
        for (k, sample) in tune.enumerated() where at + k < audio.count {
            audio[at + k] = sample * level + hiss * noise.next()
        }
        return audio
    }

    private func fingerprint(_ audio: [Float], offset: TimeInterval = 0) -> AudioFingerprint {
        AudioFingerprinter.fingerprint(samples: audio, sampleRate: rate, startOffset: offset)
    }

    // MARK: Fingerprints

    func testTheSameSoundGivesTheSameWordsAndOtherSoundDoesNot() {
        let a = fingerprint(theme(seconds: 10))
        let b = fingerprint(theme(seconds: 10))
        XCTAssertEqual(a.frames, b.frames)
        let other = fingerprint(programme(seconds: 10, seed: 3))
        let differing = zip(a.frames, other.frames).dropFirst().map { ($0 ^ $1).nonzeroBitCount }
        XCTAssertGreaterThan(Double(differing.reduce(0, +)) / Double(differing.count), 10, "unrelated audio differs in many bits")
    }

    func testSilenceIsQuietAndNeverMatches() {
        let silent = fingerprint([Float](repeating: 0, count: Int(20 * rate)))
        XCTAssertTrue(silent.frames.allSatisfy { $0 == 0 })
        XCTAssertNil(SharedAudioFinder.longest(silent, silent, lengths: 5...60))
    }

    func testAHigherRateIsReducedToTheWorkingRate() {
        let double = theme(seconds: 5).flatMap { [$0, $0] }
        let print = AudioFingerprinter.fingerprint(samples: double, sampleRate: rate * 2)
        XCTAssertEqual(print.frameSeconds, Double(AudioFingerprinter.hop) / rate, accuracy: 1e-9)
    }

    // MARK: Finding the shared stretch

    func testTheThemeIsFoundAtItsPlaceInBothEpisodes() throws {
        let one = fingerprint(episode(seed: 1, length: 150, themeAt: 20, themeLength: 40))
        let two = fingerprint(episode(seed: 2, length: 150, themeAt: 55, themeLength: 40))
        let shared = try XCTUnwrap(SharedAudioFinder.longest(one, two, lengths: 15...120))
        XCTAssertEqual(shared.startA, 20, accuracy: 1)
        XCTAssertEqual(shared.endA, 60, accuracy: 1)
        XCTAssertEqual(shared.startB, 55, accuracy: 1)
        XCTAssertEqual(shared.endB, 95, accuracy: 1)
    }

    func testAQuieterMixWithHissStillMatches() throws {
        let one = fingerprint(episode(seed: 4, length: 120, themeAt: 10, themeLength: 30))
        let two = fingerprint(episode(seed: 5, length: 120, themeAt: 40, themeLength: 30, level: 0.6, hiss: 0.01))
        let shared = try XCTUnwrap(SharedAudioFinder.longest(one, two, lengths: 15...120))
        XCTAssertEqual(shared.startB, 40, accuracy: 1.5)
        XCTAssertEqual(shared.endB, 70, accuracy: 1.5)
    }

    func testEpisodesWithoutASharedThemeGiveNothing() {
        let one = fingerprint(programme(seconds: 120, seed: 8))
        let two = fingerprint(programme(seconds: 120, seed: 9))
        XCTAssertNil(SharedAudioFinder.longest(one, two, lengths: 15...120))
    }

    func testAThemeShorterThanTheLowerBoundIsNotAnIntro() {
        let one = fingerprint(episode(seed: 10, length: 90, themeAt: 10, themeLength: 8))
        let two = fingerprint(episode(seed: 11, length: 90, themeAt: 30, themeLength: 8))
        XCTAssertNil(SharedAudioFinder.longest(one, two, lengths: 15...120))
    }

    func testTheSameRecordingTwiceIsNotAnIntro() {
        let audio = episode(seed: 12, length: 200, themeAt: 10, themeLength: 30)
        XCTAssertNil(SharedAudioFinder.longest(fingerprint(audio), fingerprint(audio), lengths: 15...120),
                     "a match longer than any intro is never chosen")
    }

    func testCreditsAreFoundInTheLastPartWithFileTimes() throws {
        // Only the last 100 s of each file are fingerprinted; the offsets give file times.
        let one = episode(seed: 13, length: 100, themeAt: 40, themeLength: 50)
        let two = episode(seed: 14, length: 100, themeAt: 30, themeLength: 50)
        let a = fingerprint(one, offset: 1300), b = fingerprint(two, offset: 1350)
        let shared = try XCTUnwrap(SharedAudioFinder.longest(a, b, lengths: DetectionLimits().creditsLength))
        XCTAssertEqual(shared.startA, 1340, accuracy: 1)
        XCTAssertEqual(shared.startB, 1380, accuracy: 1)
    }

    // MARK: The season gets better with every episode

    private func file(_ n: Int) -> FileIdentity { FileIdentity(path: "/tv/Show/S01E0\(n).mkv", size: Int64(n) * 1000, duration: 1500) }

    func testOneEpisodeAloneGivesNothingTwoGiveTheButtonThreeSkip() {
        let starts: [Double] = [20, 45, 5, 70]
        var memory = SeasonSegmentMemory()
        func add(_ n: Int) {
            let print = fingerprint(episode(seed: UInt64(20 + n), length: 140, themeAt: starts[n - 1], themeLength: 35))
            memory.add(EpisodeAudioRecord(file: file(n), intro: print, credits: nil))
        }
        add(1)
        XCTAssertTrue(memory.segments(for: file(1)).isEmpty, "no partner yet")
        add(2)
        let first = memory.segments(for: file(1))
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.first?.start ?? -1, 20, accuracy: 1)
        XCTAssertEqual(first.first?.confidence, 0.75, "one vote: the button, no automatic skip")
        add(3)
        let second = memory.segments(for: file(2))
        XCTAssertEqual(second.first?.start ?? -1, 45, accuracy: 1)
        XCTAssertEqual(second.first?.confidence, 0.9, "two agreeing votes: trusted")
        add(4)
        XCTAssertEqual(memory.segments(for: file(1)).first?.confidence ?? 0, 0.92, accuracy: 1e-9, "three votes")
        let controller = SkipController(segments: memory.segments(for: file(3)), settings: SkipSettings(intro: .automatic))
        XCTAssertTrue(controller.allowsAutomatic(try! XCTUnwrap(memory.segments(for: file(3)).first)))
    }

    func testAReplacedFileStartsAgainAndOldFingerprintsAreDropped() {
        var limits = DetectionLimits()
        limits.keptFingerprints = 2
        var memory = SeasonSegmentMemory()
        for n in 1...3 {
            let print = fingerprint(episode(seed: UInt64(40 + n), length: 100, themeAt: Double(10 * n), themeLength: 30))
            memory.add(EpisodeAudioRecord(file: file(n), intro: print, credits: nil), limits: limits)
        }
        XCTAssertNil(memory.records[0].intro, "only the newest two keep their fingerprints")
        XCTAssertFalse(memory.records[0].introVotes.isEmpty, "but its votes stay")
        var replaced = file(1)
        replaced.size = 999
        XCTAssertTrue(memory.segments(for: replaced).isEmpty, "another file at the same path")
    }

    func testTheMemorySurvivesBeingStored() throws {
        var memory = SeasonSegmentMemory()
        for n in 1...2 {
            let print = fingerprint(episode(seed: UInt64(60 + n), length: 90, themeAt: Double(5 + 20 * n), themeLength: 25))
            memory.add(EpisodeAudioRecord(file: file(n), intro: print, credits: nil))
        }
        let decoded = try JSONDecoder().decode(SeasonSegmentMemory.self, from: JSONEncoder().encode(memory))
        XCTAssertEqual(decoded, memory)
    }

    func testWindows() {
        let limits = DetectionLimits()
        XCTAssertEqual(limits.window(for: .intro, duration: 2700), 0...600)
        XCTAssertEqual(limits.window(for: .intro, duration: 1200), 0...300, "the first quarter of a short episode")
        XCTAssertEqual(limits.window(for: .credits, duration: 2700), 2100...2700)
        XCTAssertNil(limits.window(for: .recap, duration: 2700))
    }
}
