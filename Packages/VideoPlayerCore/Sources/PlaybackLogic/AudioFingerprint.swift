import Foundation

// R316 (owner's request of 21 Nov 2026, docs/PLAYBACK_AUTOSKIP_NOWPLAYING.md section 6): on-device detection of the intro
// and the credits by comparing the audio of episodes of one season. Pure Swift, no Apple framework, so every step runs in
// the Linux tests on synthetic audio. Nothing here reads a file or the network; the app decodes the audio and hands the
// samples in, and nothing leaves the Apple TV.
//
// Method (a classic spectral-band fingerprint): the audio is made mono at about 5.5 kHz, cut into frames of 2048 samples
// (0.37 s) every 1024 samples (0.19 s), each frame's spectrum is split into 33 bands between 300 and 2000 Hz, and one 32-bit
// word per frame records, band by band, whether the energy difference between neighbouring bands rose or fell since the
// previous frame. The same sound gives (nearly) the same words wherever it sits in the file and whatever its loudness; two
// different sounds give words that differ in about half their bits.

/// The fingerprint of one stretch of a file's audio.
public struct AudioFingerprint: Equatable, Sendable, Codable {
    /// One word per frame. 0 marks a quiet frame, which never counts as a match (silence is shared by everything).
    public var frames: [UInt32]
    /// Seconds between frames.
    public var frameSeconds: Double
    /// Where in the file the first frame starts, in seconds.
    public var startOffset: TimeInterval

    public init(frames: [UInt32], frameSeconds: Double, startOffset: TimeInterval) {
        self.frames = frames
        self.frameSeconds = frameSeconds
        self.startOffset = startOffset
    }

    /// File time of frame `index`.
    public func time(ofFrame index: Int) -> TimeInterval { startOffset + Double(index) * frameSeconds }
    public var duration: TimeInterval { Double(frames.count) * frameSeconds }
}

public enum AudioFingerprinter {
    /// The rate the fingerprint works at. Higher input rates are reduced by an integer factor first.
    public static let workingRate: Double = 5512.5
    public static let frameLength = 2048
    public static let hop = 1024
    public static let bandCount = 33
    public static let lowHz: Double = 300
    public static let highHz: Double = 2000
    /// PROVISIONAL: a frame whose RMS level is below this (full scale 1.0) is quiet.
    public static let quietLevel: Float = 0.001

    /// Builds the fingerprint of mono `samples` at `sampleRate`, the first sample being at `startOffset` seconds in the file.
    public static func fingerprint(samples: [Float], sampleRate: Double, startOffset: TimeInterval = 0) -> AudioFingerprint {
        let factor = max(1, Int((sampleRate / workingRate).rounded()))
        let working = factor == 1 ? samples : decimate(samples, by: factor)
        let rate = sampleRate / Double(factor)
        let frameSeconds = Double(hop) / rate
        guard working.count >= frameLength else { return AudioFingerprint(frames: [], frameSeconds: frameSeconds, startOffset: startOffset) }
        let window = (0..<frameLength).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(frameLength - 1))) }
        let edges = bandEdges(rate: rate)
        var previous: [Float]?
        var words: [UInt32] = []
        var start = 0
        while start + frameLength <= working.count {
            let frame = Array(working[start..<(start + frameLength)])
            let level = (frame.reduce(Float(0)) { $0 + $1 * $1 } / Float(frameLength)).squareRoot()
            let energies = bandEnergies(frame: frame, window: window, edges: edges)
            if level < quietLevel {
                words.append(0)
            } else if let previous {
                var word: UInt32 = 0
                for band in 0..<(bandCount - 1) {
                    let now = energies[band] - energies[band + 1]
                    let before = previous[band] - previous[band + 1]
                    if now - before > 0 { word |= 1 << UInt32(band) }
                }
                // A word of all zeros would read as quiet; such a loud frame is vanishingly rare, so it gets one bit.
                words.append(word == 0 ? 1 : word)
            } else {
                words.append(0)
            }
            previous = energies
            start += hop
        }
        return AudioFingerprint(frames: words, frameSeconds: frameSeconds, startOffset: startOffset)
    }

    /// Averages each run of `factor` samples (a plain low-pass before dropping samples; enough for band energies).
    static func decimate(_ samples: [Float], by factor: Int) -> [Float] {
        var out: [Float] = []
        out.reserveCapacity(samples.count / factor)
        var index = 0
        while index + factor <= samples.count {
            var sum: Float = 0
            for k in index..<(index + factor) { sum += samples[k] }
            out.append(sum / Float(factor))
            index += factor
        }
        return out
    }

    /// FFT bin edges of the bands, spaced evenly on a log scale between `lowHz` and `highHz`.
    static func bandEdges(rate: Double) -> [Int] {
        let binHz = rate / Double(frameLength)
        return (0...bandCount).map { band in
            let hz = lowHz * pow(highHz / lowHz, Double(band) / Double(bandCount))
            return min(frameLength / 2, max(1, Int((hz / binHz).rounded())))
        }
    }

    static func bandEnergies(frame: [Float], window: [Float], edges: [Int]) -> [Float] {
        var re = (0..<frameLength).map { Double(frame[$0] * window[$0]) }
        var im = [Double](repeating: 0, count: frameLength)
        FFT.transform(&re, &im)
        var power = [Float](repeating: 0, count: frameLength / 2 + 1)
        for k in 0...(frameLength / 2) { power[k] = Float(re[k] * re[k] + im[k] * im[k]) }
        return (0..<bandCount).map { band in
            let from = edges[band], to = max(edges[band] + 1, edges[band + 1])
            var sum: Float = 0
            for k in from..<min(to, power.count) { sum += power[k] }
            return log(1 + sum)
        }
    }
}

/// In-place radix-2 FFT (the length must be a power of two). Small and plain, so the Linux tests and the Apple TV run the
/// same code.
enum FFT {
    static func transform(_ re: inout [Double], _ im: inout [Double]) {
        let n = re.count
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j |= bit
            if i < j { re.swapAt(i, j); im.swapAt(i, j) }
        }
        var length = 2
        while length <= n {
            let angle = -2 * Double.pi / Double(length)
            let wRe = cos(angle), wIm = sin(angle)
            var start = 0
            while start < n {
                var curRe = 1.0, curIm = 0.0
                for k in 0..<(length / 2) {
                    let a = start + k, b = a + length / 2
                    let tRe = re[b] * curRe - im[b] * curIm
                    let tIm = re[b] * curIm + im[b] * curRe
                    re[b] = re[a] - tRe; im[b] = im[a] - tIm
                    re[a] += tRe; im[a] += tIm
                    let next = curRe * wRe - curIm * wIm
                    curIm = curRe * wIm + curIm * wRe
                    curRe = next
                }
                start += length
            }
            length <<= 1
        }
    }
}

/// A stretch of audio two files share: where it is in each, in file seconds.
public struct SharedStretch: Equatable, Sendable {
    public var startA: TimeInterval
    public var endA: TimeInterval
    public var startB: TimeInterval
    public var endB: TimeInterval
    /// Frames that matched inside the stretch.
    public var matchedFrames: Int
    public var length: TimeInterval { endA - startA }
}

/// Finds the longest stretch two fingerprints share, at any offset between them.
public enum SharedAudioFinder {
    /// PROVISIONAL tuning: two words match when they differ in at most this many of their 32 bits (unrelated audio differs
    /// in about 16; at most 10 of 32 happens by chance for about 2 % of unrelated frames).
    public static let maxBitErrors = 10
    /// PROVISIONAL: a run of matching frames may have holes of at most this many frames (about 3 s) and stay one stretch.
    public static let maxGapFrames = 16
    /// PROVISIONAL: at least this share of the frames inside a stretch must match.
    public static let minDensity = 0.5

    /// The longest shared stretch whose length lies in `lengths`, nil when none. A shared stretch longer than the upper
    /// bound means the two are the same recording (two copies of one episode): then nothing is shared that could be told
    /// apart as an intro, and the answer is nil.
    public static func longest(_ a: AudioFingerprint, _ b: AudioFingerprint, lengths: ClosedRange<TimeInterval>) -> SharedStretch? {
        let na = a.frames.count, nb = b.frames.count
        guard na > 0, nb > 0, abs(a.frameSeconds - b.frameSeconds) < 1e-6 else { return nil }
        var best: (i: Int, j: Int, length: Int, matched: Int)?
        var sameRecording = false
        // Offset d: frame i of `a` against frame i - d of `b`.
        for d in (-(nb - 1))...(na - 1) {
            let iFrom = max(0, d), iTo = min(na, nb + d)
            guard iTo - iFrom > 0 else { continue }
            var positions: [Int] = []
            func close() {
                defer { positions.removeAll(keepingCapacity: true) }
                // Chance matches near a real stretch would stretch its edges: each end moves in to the first place where
                // most of the next `edgeFrames` frames match.
                var from = 0, to = positions.count - 1
                while from <= to, !solid(positions, at: from, forward: true) { from += 1 }
                while to >= from, !solid(positions, at: to, forward: false) { to -= 1 }
                guard from <= to else { return }
                let first = positions[from], last = positions[to]
                let frames = last - first + 1, matched = to - from + 1
                guard Double(matched) / Double(frames) >= minDensity else { return }
                let seconds = Double(frames) * a.frameSeconds
                if seconds > lengths.upperBound { sameRecording = true }
                if lengths.contains(seconds), matched > (best?.matched ?? 0) {
                    best = (first, first - d, frames, matched)
                }
            }
            for i in iFrom..<iTo {
                let x = a.frames[i], y = b.frames[i - d]
                if x != 0, y != 0, (x ^ y).nonzeroBitCount <= maxBitErrors {
                    if let last = positions.last, i - last > maxGapFrames + 1 { close() }
                    positions.append(i)
                }
            }
            close()
        }
        guard !sameRecording, let found = best else { return nil }
        let startA = a.time(ofFrame: found.i), startB = b.time(ofFrame: found.j)
        let seconds = Double(found.length) * a.frameSeconds
        return SharedStretch(startA: startA, endA: startA + seconds, startB: startB, endB: startB + seconds, matchedFrames: found.matched)
    }

    /// PROVISIONAL: an edge of a stretch is solid when at least `edgeMatches` of the `edgeFrames` frames from it (inwards)
    /// match (about 1.5 s).
    public static let edgeFrames = 8
    public static let edgeMatches = 5

    /// Whether the matched frame `positions[index]` starts (forward) or ends (backward) a solid part.
    static func solid(_ positions: [Int], at index: Int, forward: Bool) -> Bool {
        let here = positions[index]
        var count = 0
        if forward {
            var k = index
            while k < positions.count, positions[k] < here + edgeFrames { count += 1; k += 1 }
        } else {
            var k = index
            while k >= 0, positions[k] > here - edgeFrames { count += 1; k -= 1 }
        }
        return count >= edgeMatches
    }
}
