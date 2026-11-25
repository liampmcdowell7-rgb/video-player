import SwiftUI
import QuartzCore
import Observation
import AppLogic

/// R471 (51), PROVISIONAL: the focus moves and slow frames for Settings > Playback (`FocusTrail`, `SlowFrames`), in memory
/// only, cleared when the app closes. Nothing here is saved, synced or backed up, and no title is kept.
@MainActor @Observable
final class ScrollDiagnosticsStore {
    static let shared = ScrollDiagnosticsStore()
    private(set) var trail = FocusTrail()
    private(set) var frames = SlowFrames()

    func record(_ step: FocusStep) { trail.record(step) }
    /// One scroll's frames, added when the scroll ends (not on every frame, so nothing observes a per-frame change).
    func add(_ scroll: SlowFrames) { frames.merge(scroll) }
}

/// Which card has the focus: its screen (our own name), its shelf on Home (from 1) and its place in its grid or shelf
/// (from 0). Published by the card (`focusCell(index:)`), read by the page's recorder.
struct FocusCell: Equatable {
    let screen: String
    let shelf: Int?
    let index: Int
}

private struct FocusCellKey: FocusedValueKey {
    typealias Value = FocusCell
}

extension FocusedValues {
    var focusCell: FocusCell? {
        get { self[FocusCellKey.self] }
        set { self[FocusCellKey.self] = newValue }
    }
}

private struct DiagnosticsScreenKey: EnvironmentKey {
    static let defaultValue = ""
}

private struct FocusShelfKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    /// The recorder's screen name, for the cards under it ("" where nothing records).
    var diagnosticsScreen: String {
        get { self[DiagnosticsScreenKey.self] }
        set { self[DiagnosticsScreenKey.self] = newValue }
    }

    /// Home: the shelf a card is on, from 1.
    var focusShelf: Int? {
        get { self[FocusShelfKey.self] }
        set { self[FocusShelfKey.self] = newValue }
    }
}

/// On a card: publishes its place while it (or a view in it) has the focus.
private struct FocusCellPublisher: ViewModifier {
    let index: Int
    @Environment(\.diagnosticsScreen) private var screen
    @Environment(\.focusShelf) private var shelf

    func body(content: Content) -> some View {
        content.focusedValue(\.focusCell, FocusCell(screen: screen, shelf: shelf, index: index))
    }
}

/// On a page's scroll view: records each focus move of the cards under it with the scroll offset at that moment, and times
/// the frames while the page scrolls. The offset is kept in a plain object (no view update); the display link runs only
/// between the start and the end of a scroll.
private struct ScrollDiagnosticsRecorder: ViewModifier {
    let screen: String
    /// Cards a row on a grid; nil on Home, where the row is the shelf and the column the place in it.
    let columns: Int?
    @State private var offset = OffsetBox()
    @State private var timer = FrameTimer()
    @FocusedValue(\.focusCell) private var cell: FocusCell?

    func body(content: Content) -> some View {
        content
            .environment(\.diagnosticsScreen, screen)
            .onScrollGeometryChange(for: Int.self) { Int($0.contentOffset.y.rounded()) } action: { (_: Int, now: Int) in
                offset.value = now
            }
            .onScrollPhaseChange { (_: ScrollPhase, now: ScrollPhase) in
                if now.isScrolling, !screen.isEmpty { timer.start(screen: screen) } else { timer.stop() }
            }
            .onChange(of: cell) { (_: FocusCell?, now: FocusCell?) in
                guard let now, !screen.isEmpty, now.screen == screen else { return }
                let place: (row: Int, column: Int) = columns.map { FocusStep.cell(index: now.index, columns: $0) }
                    ?? (row: now.shelf ?? 0, column: now.index + 1)
                ScrollDiagnosticsStore.shared.record(FocusStep(screen: screen, row: place.row, column: place.column, offset: offset.value))
            }
            .onDisappear { timer.stop() }
    }
}

/// The page's last scroll offset, written while it scrolls without updating any view.
private final class OffsetBox {
    var value: Int = 0
}

/// Frame times from the display link while a page scrolls; handed to the store when the scroll ends.
@MainActor
private final class FrameTimer: NSObject {
    private var link: CADisplayLink?
    private var screen = ""
    private var last: CFTimeInterval = 0
    private var scroll = SlowFrames()

    func start(screen: String) {
        guard link == nil else { return }
        self.screen = screen
        last = 0
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        guard let link else { return }
        link.invalidate()
        self.link = nil
        ScrollDiagnosticsStore.shared.add(scroll)
        scroll = SlowFrames()
    }

    @objc private func tick(_ link: CADisplayLink) {
        if last > 0 {
            scroll.record(screen: screen, seconds: link.timestamp - last, frameSeconds: link.targetTimestamp - link.timestamp)
        }
        last = link.timestamp
    }
}

extension View {
    /// R471 (51): on a card in a grid or a shelf, its place (from 0).
    func focusCell(index: Int) -> some View { modifier(FocusCellPublisher(index: index)) }

    /// R471 (51): on a page's scroll view, the focus moves and slow frames for the diagnostics page.
    func scrollDiagnostics(screen: String, columns: Int?) -> some View {
        modifier(ScrollDiagnosticsRecorder(screen: screen, columns: columns))
    }
}
