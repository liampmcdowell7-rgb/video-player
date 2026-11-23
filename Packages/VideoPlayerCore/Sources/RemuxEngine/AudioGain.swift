import Foundation

/// R458 (Settings > Audio > Volume Boost, PROVISIONAL): a gain on the PCM of the audio the app decodes itself (DTS, TrueHD,
/// Opus, Vorbis, before it is repackaged as FLAC). The decoder hands over samples left-aligned in 32 bits (a 16-bit sample times
/// 65536), so full scale is the Int32 range whatever the track's depth. A result past full scale is held at its end (hard
/// limit), so loud passages can clip at the higher settings. Audio the system decodes (AAC, Dolby Digital) is not touched:
/// Apple's `setVolume(_:at:)` of an audio mix accepts 0.0 to 1.0 only, so it cannot raise a level.
public enum AudioGain {
    /// The linear factor of a gain in decibels.
    public static func factor(decibels: Double) -> Float { Float(pow(10, decibels / 20)) }

    /// Scales every sample in place. A factor of 1 leaves the array alone.
    public static func apply(_ samples: inout [Int32], gain: Float) {
        guard gain != 1 else { return }
        let g = Double(gain)
        var i = 0
        while i < samples.count {
            let scaled = (Double(samples[i]) * g).rounded()
            samples[i] = Int32(max(Double(Int32.min), min(Double(Int32.max), scaled)))
            i += 1
        }
    }
}
