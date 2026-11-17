import Foundation

/// A rectangle in the output (container) coordinate space, origin top-left.
public struct PlacedRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
}

public struct PGSPlacementOptions: Equatable, Sendable {
    public enum AspectMode: String, Sendable {
        /// One scale for both axes; the stream frame is centred in the container (bars where the aspects differ).
        case fit
        /// Separate scales per axis; the stream frame fills the container.
        case stretch
    }

    public var aspect: AspectMode
    /// The user's vertical-position setting: a fraction of the container height; positive moves the subtitles up,
    /// negative moves them down. 0.05 is five percent of the height. Clamped to -0.5...0.5.
    public var verticalOffset: Double
    /// When false (default), subtitles that sit in the upper half of the frame (signs, top-placed dialogue) keep
    /// their authored position and only lower subtitles follow the setting.
    public var moveTopSubtitles: Bool

    public init(aspect: AspectMode = .fit, verticalOffset: Double = 0, moveTopSubtitles: Bool = false) {
        self.aspect = aspect
        self.verticalOffset = verticalOffset
        self.moveTopSubtitles = moveTopSubtitles
    }
}

/// Maps PGS bitmaps from the stream's frame to an output rectangle.
public enum PGSPlacement {

    /// Rectangles for every object of `cue`, in the same order, inside a container of the given size.
    /// The whole cue moves as one block (so a two-line subtitle sent as two bitmaps keeps its spacing) and the
    /// block is kept inside the container. Degenerate sizes give an empty list.
    public static func place(
        _ cue: PGSBitmapCue,
        containerWidth: Double,
        containerHeight: Double,
        options: PGSPlacementOptions = PGSPlacementOptions()
    ) -> [PlacedRect] {
        guard cue.frameWidth > 0, cue.frameHeight > 0, containerWidth > 0, containerHeight > 0,
              containerWidth.isFinite, containerHeight.isFinite, !cue.objects.isEmpty else { return [] }
        let sw = Double(cue.frameWidth), sh = Double(cue.frameHeight)
        let sx: Double, sy: Double, ox: Double, oy: Double
        switch options.aspect {
        case .stretch:
            sx = containerWidth / sw
            sy = containerHeight / sh
            ox = 0
            oy = 0
        case .fit:
            let s = min(containerWidth / sw, containerHeight / sh)
            sx = s
            sy = s
            ox = (containerWidth - sw * s) / 2
            oy = (containerHeight - sh * s) / 2
        }
        var rects = cue.objects.map {
            PlacedRect(x: ox + Double($0.x) * sx, y: oy + Double($0.y) * sy, width: Double($0.width) * sx, height: Double($0.height) * sy)
        }

        let offset = max(-0.5, min(0.5, options.verticalOffset.isFinite ? options.verticalOffset : 0))
        if offset != 0 {
            let top = rects.map(\.y).min() ?? 0
            let bottom = rects.map(\.maxY).max() ?? 0
            let centre = (top + bottom) / 2
            let inUpperHalf = centre < containerHeight / 2
            if !inUpperHalf || options.moveTopSubtitles {
                var delta = -offset * containerHeight
                if top + delta < 0 { delta = -top }
                if bottom + delta > containerHeight { delta = containerHeight - bottom }
                // A block taller than the container cannot be kept inside; do not move it at all.
                if bottom - top > containerHeight { delta = 0 }
                for i in rects.indices { rects[i].y += delta }
            }
        }
        return rects
    }
}
