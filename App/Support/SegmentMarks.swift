import Foundation
import VideoPlayerCore
import PlaybackLogic
import UserData
import AppLogic

/// The "Mark Intro / Recap / Credits" action while playing (docs/SEGMENTS.md). The player calls `mark(kind:itemID:at:)` with its
/// playhead: the first call of a kind remembers where the part starts, the second call saves where it ends.
///
/// PROVISIONAL: a mark belongs to the item (this episode or film). Alternative: apply it to the rest of the season; not built.
///
/// The per-item state (a pending start, the undo step) lives in `MarkRegistry`, because `AppServices` has no stored property for it.
@MainActor
struct SegmentMarks {
    let services: AppServices

    /// Marks the playhead. `duration` is the length of the file when the player knows it; without it the library's length is used.
    @discardableResult
    func mark(kind: SegmentType, itemID: Int64, at position: TimeInterval?, duration: TimeInterval? = nil) async -> MarkOutcome {
        guard let session = await self.session(forItem: itemID) else { return .notStored }
        let length = await lengthOfFile(itemID: itemID, given: duration)
        return session.press(kind, at: position, duration: length)
    }

    /// Removes the saved mark of this kind.
    @discardableResult
    func deleteMark(kind: SegmentType, itemID: Int64) async -> MarkOutcome {
        guard let session = await self.session(forItem: itemID) else { return .notStored }
        return session.delete(kind)
    }

    /// Forgets a start that was marked and not finished.
    @discardableResult
    func cancelPendingMark(itemID: Int64) async -> MarkOutcome {
        guard let session = await self.session(forItem: itemID) else { return .notStored }
        return session.cancelPending()
    }

    /// Reverts the last change made in this playback.
    @discardableResult
    func undoLastMark(itemID: Int64) async -> MarkOutcome {
        guard let session = await self.session(forItem: itemID) else { return .notStored }
        return session.undo()
    }

    /// What the menu shows now (the pending start, the saved marks, whether Undo is available).
    func menuState(itemID: Int64) async -> MarkMenuState {
        await session(forItem: itemID)?.state ?? MarkMenuState()
    }

    /// Call when playback of the item ends: the pending start and the undo step are for this playback only.
    func endPlayback(itemID: Int64) {
        MarkRegistry.shared.forget(itemID: itemID)
    }

    // MARK: Private

    private func session(forItem itemID: Int64) async -> SegmentMarkSession? {
        let registry = MarkRegistry.shared
        registry.use(ledger: services.ledger)
        if let existing = registry.session(for: itemID) { return existing }
        guard let key = try? await services.sqlite.userDataKey(forItem: itemID) else { return nil }
        // Another call may have made the session while the key was being read.
        if let existing = registry.session(for: itemID) { return existing }
        return registry.make(itemID: itemID, itemKey: key, ledger: services.ledger)
    }

    private func lengthOfFile(itemID: Int64, given: TimeInterval?) async -> TimeInterval? {
        if let given, given.isFinite, given > 0 { return given }
        guard let item = try? await services.store.item(id: itemID) else { return nil }
        let files = (try? await services.store.versions(of: itemID)) ?? []
        let file = files.first(where: { $0.id == item.preferredFileID }) ?? files.first
        let length = file?.technical?.duration ?? item.runtime ?? item.watch.duration
        return length.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
    }
}

extension AppServices {
    /// The mark action for the player. A computed property: `AppServices` gets no stored property for it.
    var segmentMarks: SegmentMarks { SegmentMarks(services: self) }
}

/// Holds the mark sessions of the items being played, for the whole app. Main actor only.
@MainActor
final class MarkRegistry {
    static let shared = MarkRegistry()
    private var sessions: [Int64: SegmentMarkSession] = [:]
    private weak var ledger: UserDataLedger?

    /// A different ledger (the app was reset) drops every session, so none writes to an old ledger.
    func use(ledger: UserDataLedger) {
        if let current = self.ledger, current !== ledger { sessions.removeAll() }
        self.ledger = ledger
    }

    func session(for itemID: Int64) -> SegmentMarkSession? { sessions[itemID] }

    func make(itemID: Int64, itemKey: String, ledger: UserDataLedger) -> SegmentMarkSession {
        let session = SegmentMarkSession(itemKey: itemKey, ledger: ledger)
        sessions[itemID] = session
        return session
    }

    func forget(itemID: Int64) { sessions[itemID] = nil }
}
