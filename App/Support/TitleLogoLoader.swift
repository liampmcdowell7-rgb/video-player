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
        guard let measured = measure(small) else { return nil }
        // The width check uses the full picture; transparency, brightness and coverage come from the small copy.
        let pixels = LogoPixels(width: image.width, height: image.height, hasTransparency: measured.hasTransparency && image.alphaInfo != .none,
                                meanLuminance: measured.meanLuminance, coverage: measured.coverage)
        return Loaded(image: image, pixels: pixels)
    }

    /// Draws the picture into an RGBA buffer (premultiplied, as Core Graphics requires) and turns it back into straight
    /// colours for `LogoPixels.measure`.
    private static func measure(_ image: CGImage) -> LogoPixels? {
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
        return LogoPixels.measure(rgba: buffer, width: w, height: h)
    }
}
