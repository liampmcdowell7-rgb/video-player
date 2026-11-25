import SwiftUI
import Foundation
import CoreGraphics
import ImageIO
import AppLogic

/// R471 (48), PROVISIONAL (owner's scroll report, 25 Nov 2026): a picture decoded at the pixels its frame shows
/// (`ImageSizing.maxPixelSize`), off the main thread, and kept in memory, in place of `AsyncImage`, which decodes the whole
/// file. It reads the file's size from its header first (no decode), then asks ImageIO for a copy of that size
/// (`CGImageSourceCreateThumbnailAtIndex`, decoded at once: `kCGImageSourceShouldCacheImmediately`), so the system never
/// scales a large bitmap down while a shelf or grid scrolls. Remote pictures still come through the capped image session
/// (its disk cache, D-DS5). Like `AsyncImage` in an overlay, it takes the size it is offered; `content` draws the picture
/// (aspect fill, a cover over it) and `placeholder` shows until it is ready or when it cannot be read.
struct FittedImage<Content: View, Placeholder: View>: View {
    let url: URL
    let session: URLSession
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder
    @Environment(\.displayScale) private var scale
    /// The offered size, in whole points; written only when it changes by a point or more.
    @State private var size: CGSize = .zero
    @State private var picture: DecodedPictures.Picture?

    var body: some View {
        Color.clear
            .overlay {
                if let picture {
                    content(Image(decorative: picture.image, scale: 1))
                } else {
                    placeholder()
                }
            }
            .onGeometryChange(for: CGSize.self) { CGSize(width: $0.size.width.rounded(), height: $0.size.height.rounded()) } action: { (new: CGSize) in
                if new != size { size = new }
            }
            .task(id: "\(url.absoluteString)|\(Int(size.width))x\(Int(size.height))|\(scale)") {
                guard size.width > 0, size.height > 0 else { return }
                let loaded = await DecodedPictures.load(url: url, points: size, scale: Double(scale), session: session)
                if !Task.isCancelled { picture = loaded }
            }
    }
}

/// R471 (48): the decoded copies, by address and size (`ImageSizing.cacheKey`). The cache gives memory back by itself when
/// the system asks (NSCache), and its cost is the copy's bytes.
enum DecodedPictures {
    struct Picture: @unchecked Sendable {
        let image: CGImage
    }

    private final class Box {
        let picture: Picture
        init(_ picture: Picture) { self.picture = picture }
    }

    private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.totalCostLimit = 160 * 1024 * 1024
        return cache
    }()

    /// The picture at `url`, decoded to fill `points` on a screen of `scale`; nil when it cannot be read.
    static func load(url: URL, points: CGSize, scale: Double, session: URLSession) async -> Picture? {
        guard let data = await bytes(url, session: session),
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let pixels = pixelSize(source),
              let maxPixel = ImageSizing.maxPixelSize(frameWidth: Double(points.width), frameHeight: Double(points.height),
                                                      imageWidth: pixels.width, imageHeight: pixels.height, scale: scale) else { return nil }
        let key = ImageSizing.cacheKey(url: url, maxPixelSize: maxPixel) as NSString
        if let hit = cache.object(forKey: key) { return hit.picture }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceShouldCacheImmediately: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let picture = Picture(image: image)
        cache.setObject(Box(picture), forKey: key, cost: image.bytesPerRow * image.height)
        return picture
    }

    /// The file's own size in pixels, from its header (no decode); nil when the header has none.
    private static func pixelSize(_ source: CGImageSource) -> (width: Double, height: Double)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue else { return nil }
        // An EXIF orientation of 5 to 8 turns the picture a quarter: the shown width is the stored height.
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return orientation >= 5 ? (width: height, height: width) : (width: width, height: height)
    }

    private static func bytes(_ url: URL, session: URLSession) async -> Data? {
        if url.isFileURL { return try? Data(contentsOf: url, options: .mappedIfSafe) }
        guard let (data, response) = try? await session.data(from: url) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        return data
    }
}
