import UIKit
import CoreGraphics
import Subtitles

/// Draws picture subtitles (bitmaps) over the video. The system player cannot show them, so this is the one custom subtitle
/// path (decision D1, PROVISIONAL). It is fed by `RemuxPlayback.pictureData` and the player's clock; it never touches the
/// player's own subtitle selection.
///
/// Limits (written down in docs/PLAYBACK_WIRING.md): after a jump into the middle of a subtitle epoch the first subtitle can be
/// missing if the stream relies on palette or bitmap data from before the jump; nothing is drawn then, never a wrong picture.
@MainActor
final class PictureSubtitleOverlay {
    private let playback: RemuxPlayback
    private weak var container: UIView?
    private var views: [UIImageView] = []
    private var track: Int?
    private var cuesByStart: [Int: PGSBitmapCue] = [:]
    private var sorted: [PGSBitmapCue] = []
    private var loadedSegments: Set<Int> = []
    private var loading = false
    private var epoch = 0
    private var shown: PGSBitmapCue?
    private var shownSize: CGSize = .zero

    init(playback: RemuxPlayback, container: UIView) {
        self.playback = playback
        self.container = container
    }

    var isShowing: Bool { track != nil }

    func show(track: Int) {
        self.track = track
        resetData()
    }

    func hide() {
        track = nil
        resetData()
    }

    /// Call after the player jumped to another position.
    func didSeek() {
        guard track != nil else { return }
        resetData()
    }

    /// Call about four times a second with the player's position (the same clock the video uses).
    func tick(_ seconds: TimeInterval) {
        guard track != nil, seconds.isFinite else { clearIfNeeded(); return }
        load(around: seconds)
        let cue = sorted.last(where: { $0.start <= seconds && seconds < $0.end })
        if cue == shown, shownSize == container?.bounds.size { return }
        draw(cue)
    }

    // MARK: Loading

    private func resetData() {
        epoch += 1
        cuesByStart.removeAll()
        sorted.removeAll()
        loadedSegments.removeAll()
        loading = false
        draw(nil)
    }

    private func load(around seconds: TimeInterval) {
        guard !loading, let track else { return }
        let current = epoch
        loading = true
        let playback = self.playback
        Task { @MainActor [weak self] in
            let index = await playback.segmentIndex(forPlayerSeconds: seconds)
            // The window after the current one is read too, so a subtitle that ends in the next window is closed properly.
            let wanted = [index, index + 1].filter { $0 < playback.segmentCount && !(self?.loadedSegments.contains($0) ?? true) }
            guard !wanted.isEmpty else { self?.loading = false; return }
            var data = Data()
            for k in [index, index + 1] where k < playback.segmentCount {
                if let part = await playback.pictureData(track: track, segment: k) { data.append(part) }
            }
            guard let self, self.epoch == current else { return }
            self.loading = false
            self.loadedSegments.formUnion(wanted)
            let result = PGSParser.parse(data)
            for cue in result.cues { self.cuesByStart[Int(cue.start * 1000)] = cue }
            // Keep memory small on long files: drop what ended well before the position.
            self.cuesByStart = self.cuesByStart.filter { $0.value.end > seconds - 60 }
            self.sorted = self.cuesByStart.values.sorted { $0.start < $1.start }
            // Windows far behind the position are forgotten so scrolling back loads them again.
            self.loadedSegments = self.loadedSegments.filter { $0 >= index - 1 }
        }
    }

    // MARK: Drawing

    private func clearIfNeeded() {
        if shown != nil { draw(nil) }
    }

    private func draw(_ cue: PGSBitmapCue?) {
        shown = cue
        shownSize = container?.bounds.size ?? .zero
        for view in views { view.removeFromSuperview() }
        views.removeAll()
        guard let cue, let container else { return }
        let rects = PGSPlacement.place(cue, containerWidth: Double(container.bounds.width), containerHeight: Double(container.bounds.height))
        for (object, rect) in zip(cue.objects, rects) {
            guard let image = Self.image(for: object) else { continue }
            let view = UIImageView(image: UIImage(cgImage: image))
            view.frame = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
            view.isUserInteractionEnabled = false
            container.addSubview(view)
            views.append(view)
        }
    }

    private static func image(for object: PGSBitmapObject) -> CGImage? {
        guard object.width > 0, object.height > 0, object.indices.count == object.width * object.height else { return nil }
        let rgba = object.rgba()
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        // Straight (not premultiplied) alpha, 8 bits per channel. PROVISIONAL: checked on a device (docs/DEVICE_TEST_CHECKLIST_PLAYBACK.md).
        return CGImage(width: object.width, height: object.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: object.width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
