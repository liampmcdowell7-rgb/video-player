import UIKit
import PlaybackLogic
import AppLogic

/// The player side of "Mark Intro / Recap / Credits" (docs/SEGMENTS.md). It reads the playhead from the player, calls
/// `AppServices.segmentMarks`, keeps the state the menu shows, and says what happened in the menu itself (a first line that cannot
/// be chosen), so there is no banner drawn over the video.
@MainActor
final class PlayerMarkController: PlayerMarkActions {
    private let itemID: Int64
    private let services: AppServices
    private let playhead: () -> TimeInterval?
    private let length: () -> TimeInterval?

    private(set) var markMenuState = MarkMenuState()
    /// What the last action did, in plain words. Shown as the first line of the menu.
    private(set) var lastMessage: String?
    /// Called after every action: the menu has to be built again.
    var onMenuChanged: () -> Void = {}
    /// Called after a mark was saved, deleted or undone: the segments of this playback have to be collected again.
    var onMarksChanged: () -> Void = {}

    init(itemID: Int64, services: AppServices, playhead: @escaping () -> TimeInterval?, length: @escaping () -> TimeInterval?) {
        self.itemID = itemID
        self.services = services
        self.playhead = playhead
        self.length = length
    }

    /// Reads the saved marks. Call once when playback starts.
    func refresh() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.markMenuState = await self.services.segmentMarks.menuState(itemID: self.itemID)
            self.onMenuChanged()
        }
    }

    func mark(_ kind: SegmentType) {
        let position = playhead()
        let duration = length()
        perform { marks, id in await marks.mark(kind: kind, itemID: id, at: position, duration: duration) }
    }

    func deleteMark(_ kind: SegmentType) { perform { marks, id in await marks.deleteMark(kind: kind, itemID: id) } }
    func cancelPendingMark() { perform { marks, id in await marks.cancelPendingMark(itemID: id) } }
    func undoLastMark() { perform { marks, id in await marks.undoLastMark(itemID: id) } }

    /// Call when playback ends.
    func end() { services.segmentMarks.endPlayback(itemID: itemID) }

    private func perform(_ work: @escaping @MainActor (SegmentMarks, Int64) async -> MarkOutcome) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let marks = self.services.segmentMarks
            let outcome = await work(marks, self.itemID)
            self.lastMessage = outcome.message
            self.markMenuState = await marks.menuState(itemID: self.itemID)
            if outcome.changedMarks { self.onMarksChanged() }
            self.onMenuChanged()
        }
    }
}

/// Builds the transport bar menu for the mark actions. Flat on purpose: the player shows one level of menu items.
@MainActor
enum PlayerMarkMenu {
    static func menu(for controller: PlayerMarkController) -> UIMenu {
        let state = controller.markMenuState
        var items: [UIMenuElement] = []
        if let message = controller.lastMessage {
            items.append(UIAction(title: message, attributes: .disabled) { _ in })
        }
        for kind in SegmentType.allCases {
            items.append(UIAction(title: state.title(for: kind), image: UIImage(systemName: "flag")) { [weak controller] _ in
                Task { @MainActor [weak controller] in controller?.mark(kind) }
            })
        }
        if state.pending != nil {
            items.append(UIAction(title: "Cancel Start Mark", image: UIImage(systemName: "xmark")) { [weak controller] _ in
                Task { @MainActor [weak controller] in controller?.cancelPendingMark() }
            })
        }
        for kind in SegmentType.allCases {
            guard let range = state.marks[kind] else { continue }
            let title = "Delete \(name(of: kind)) Mark (\(MarkText.clock(range.start)) to \(MarkText.clock(range.end)))"
            items.append(UIAction(title: title, image: UIImage(systemName: "trash")) { [weak controller] _ in
                Task { @MainActor [weak controller] in controller?.deleteMark(kind) }
            })
        }
        if state.canUndo {
            items.append(UIAction(title: "Undo Last Mark", image: UIImage(systemName: "arrow.uturn.backward")) { [weak controller] _ in
                Task { @MainActor [weak controller] in controller?.undoLastMark() }
            })
        }
        return UIMenu(title: "Mark Skip Points", image: UIImage(systemName: "flag"), children: items)
    }

    private static func name(of kind: SegmentType) -> String { kind.rawValue.capitalized }
}
