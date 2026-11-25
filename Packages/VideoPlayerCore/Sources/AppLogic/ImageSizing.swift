import Foundation

/// R471 (48), PROVISIONAL (owner's scroll report of 25 Nov 2026): the size a picture is decoded at. A picture next to the
/// media (a poster or fan art file) can be thousands of pixels across; decoded whole, every card of a shelf or a library
/// grid holds a full-size bitmap and the system scales it down on every frame. It is decoded instead at the pixels its
/// frame shows (the frame in points times the screen's scale), so it still fills the frame (aspect fill) without a blur.
public enum ImageSizing {
    /// Decoded sizes are rounded up to this many pixels, so a frame a point wider or narrower reuses the cached copy.
    public static let step = 64

    /// The longest side, in pixels, to decode a picture of `imageWidth` x `imageHeight` pixels at, so it FILLS a frame of
    /// `frameWidth` x `frameHeight` points on a screen of `scale`: the picture's own longest side times the fill factor
    /// (`max(frame/picture)` over both sides), rounded up to `step`. Never larger than the picture itself (no upscaling).
    /// Nil when any size is not positive (nothing is shown yet).
    public static func maxPixelSize(frameWidth: Double, frameHeight: Double, imageWidth: Double, imageHeight: Double,
                                    scale: Double) -> Int? {
        guard frameWidth > 0, frameHeight > 0, imageWidth > 0, imageHeight > 0, scale > 0 else { return nil }
        let fill = max(frameWidth * scale / imageWidth, frameHeight * scale / imageHeight)
        let longest = max(imageWidth, imageHeight)
        let needed = (longest * fill).rounded(.up)
        let stepped = (needed / Double(step)).rounded(.up) * Double(step)
        return Int(min(stepped, longest.rounded(.up)))
    }

    /// The cache key of one decoded copy: the picture's address and the decoded size.
    public static func cacheKey(url: URL, maxPixelSize: Int) -> String {
        "\(url.absoluteString)|\(maxPixelSize)"
    }
}
