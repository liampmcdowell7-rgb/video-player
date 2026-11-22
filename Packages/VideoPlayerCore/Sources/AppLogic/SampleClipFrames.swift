import Foundation

/// R319 (compile-run list item 9(b), 21 Nov 2026): the colour of each frame of the screenshot job's generated sample clip
/// (`UITestClip`, Debug builds only). The player pictures showed a lighter vertical strip at the left edge, x 0 to about 72
/// of 1920. It was not the player: the clip itself drew a lighter band 48 pixels wide that moved across the 640-pixel frame,
/// 8 pixels a frame, starting at x 0. So frame 0 and every 80th frame after it had the band at x 0–23, which is x 0–72 at
/// 1920. Every frame is now one even colour: nothing in the picture can be mistaken for the player's chrome. The hue still
/// changes every second, so a still picture is never black and playback still shows.
public enum SampleClipFrames {
    /// Hues in one cycle; the clip goes round it every this many seconds.
    public static let hueSteps = 12

    /// The colour of frame `index` (red, green, blue), the same for every pixel of the frame.
    public static func colour(frame index: Int, framesPerSecond: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let second = framesPerSecond > 0 ? max(index, 0) / framesPerSecond : 0
        return rgb(hue: Double(second % hueSteps) / Double(hueSteps))
    }

    /// A mid-dark colour of the given hue (value 0.55, saturation 0.6), so white subtitles and the system controls read on it.
    static func rgb(hue: Double) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let h = hue * 6, i = Int(h) % 6, f = h - Double(Int(h))
        let v = 0.55, s = 0.6
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        let c: (Double, Double, Double) = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i]
        return (UInt8(c.0 * 255), UInt8(c.1 * 255), UInt8(c.2 * 255))
    }
}
