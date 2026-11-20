import XCTest
import CoreGraphics

/// #33: the bridge from XCTest to the plain-Swift checks in Packages/VideoPlayerCore/Sources/ScreenChecks (compiled into
/// this target by path, project.yml), which the Linux tests prove on the notes and pictures of a CI run.
extension RGBImage {
    /// The screenshot as RGB bytes. CoreGraphics draws it into an 8-bit RGBA buffer in the device RGB space; alpha is
    /// dropped. Nil when the picture cannot be read.
    init?(screenshot: XCUIScreenshot) {
        guard let cgImage = screenshot.image.cgImage else { return nil }
        let width: Int = cgImage.width
        let height: Int = cgImage.height
        var rgba: [UInt8] = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = rgba.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var rgb: [UInt8] = [UInt8](repeating: 0, count: width * height * 3)
        for index in 0..<(width * height) {
            rgb[index * 3] = rgba[index * 4]
            rgb[index * 3 + 1] = rgba[index * 4 + 1]
            rgb[index * 3 + 2] = rgba[index * 4 + 2]
        }
        self.init(width: width, height: height, bytes: rgb)
    }
}

extension AXRect {
    init(_ rect: CGRect) {
        self.init(x: Double(rect.minX), y: Double(rect.minY), width: Double(rect.width), height: Double(rect.height))
    }
}

extension CheckResult {
    /// The verdict line (the last line), for a test failure message.
    var verdict: String { lines.last ?? "" }
}
