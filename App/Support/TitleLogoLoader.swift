import Foundation
import CoreGraphics
import ImageIO
import AppLogic

/// Loads title-logo candidates in order and returns the first that passes `TitleLogoRules.check` (#15 9.3, R179). Decoding
/// uses ImageIO (`CGImageSourceCreateImageAtIndex`, `CGImageSourceCreateThumbnailAtIndex`, Apple's ImageIO pages). The check
/// measures a small copy (at most 256 px wide), so a 4000 px logo is not scanned pixel by pixel.
enum TitleLogoLoader {
    struct Loaded: @unchecked Sendable {
        let image: CGImage
        let pixels: LogoPixels
    }

    static func firstAcceptable(_ candidates: [LogoCandidate], session: URLSession) async -> Loaded? {
        for candidate in candidates {
            guard let data = await bytes(candidate.location, session: session), let loaded = decode(data) else { continue }
            if TitleLogoRules.check(loaded.pixels) == nil { return loaded }
        }
        return nil
    }

    private static func bytes(_ location: ArtworkResult, session: URLSession) async -> Data? {
        switch location {
        case .file(let url): return try? Data(contentsOf: url)
        case .remote(let url):
            guard let (data, response) = try? await session.data(from: url), (response as? HTTPURLResponse)?.statusCode == 200,
                  data.count <= ArtworkEngine.maxSidecarBytes else { return nil }
            return data
        case .none: return nil
        }
    }

    static func decode(_ data: Data) -> Loaded? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 256] as CFDictionary
        let small = CGImageSourceCreateThumbnailAtIndex(source, 0, options) ?? image
        guard let buffer = rgba(of: small), let measured = LogoPixels.measure(rgba: buffer, width: small.width, height: small.height) else { return nil }
        // R393 (item 6 b of the owner's review of the run on fd9731f): the picture is cut to its visible pixels, so
        // the logo's visible left edge lines up with the text under it (the run: the logo at 150 pt, the rest at
        // 80 pt; the file's own empty margin). The box is found on the small copy (`TitleLogoRules.inkBounds`) and
        // scaled to the full picture, one small pixel wider on every side so nothing visible is cut off.
        let shown: CGImage = trimmed(image, small: small, buffer: buffer)
        // The width check uses the full picture; transparency, brightness and coverage come from the small copy.
        let pixels = LogoPixels(width: shown.width, height: shown.height, hasTransparency: measured.hasTransparency && image.alphaInfo != .none,
                                meanLuminance: measured.meanLuminance, coverage: measured.coverage)
        return Loaded(image: shown, pixels: pixels)
    }

    /// `image` cut to the box of its visible pixels; `image` itself when there is no box or nothing to cut.
    private static func trimmed(_ image: CGImage, small: CGImage, buffer: [UInt8]) -> CGImage {
        guard let ink = TitleLogoRules.inkBounds(rgba: buffer, width: small.width, height: small.height) else { return image }
        let fx: Double = Double(image.width) / Double(small.width), fy: Double = Double(image.height) / Double(small.height)
        let x0: Double = max(0, Double(ink.x - 1) * fx), y0: Double = max(0, Double(ink.y - 1) * fy)
        let x1: Double = min(Double(image.width), Double(ink.x + ink.width + 1) * fx)
        let y1: Double = min(Double(image.height), Double(ink.y + ink.height + 1) * fy)
        let box = CGRect(x: x0.rounded(.down), y: y0.rounded(.down), width: (x1 - x0).rounded(.up), height: (y1 - y0).rounded(.up))
        guard box.width >= 1, box.height >= 1, box.width < CGFloat(image.width) || box.height < CGFloat(image.height) else { return image }
        return image.cropping(to: box) ?? image
    }

    /// Draws the picture into an RGBA buffer (premultiplied, as Core Graphics requires) and turns it back into straight
    /// colours for `LogoPixels.measure`.
    private static func rgba(of image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        var i = 0
        while i < buffer.count {
            let a = Int(buffer[i + 3])
            if a > 0 && a < 255 {
                for c in 0..<3 { buffer[i + c] = UInt8(min(255, Int(buffer[i + c]) * 255 / a)) }
            }
            i += 4
        }
        return buffer
    }
}
