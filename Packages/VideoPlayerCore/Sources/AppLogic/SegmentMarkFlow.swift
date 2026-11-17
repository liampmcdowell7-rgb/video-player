import Foundation
import PlaybackLogic
import UserData

// "Mark Intro / Recap / Credits" while playing: the pure flow behind the player's mark menu (docs/SEGMENTS.md).
//
// First press of "Mark Intro" remembers the start (the playhead). The second press of the same item saves the segment
// [start, playhead] with confidence 1.0 as a user mark in the ledger (synced like watch state). Marks can be deleted, a pending
// start can be cancelled, and the last change can be undone. Nothing here knows about the player; the player passes the playhead.
//
// PROVISIONAL decisions, each with its alternative:
//  - A mark belongs to the item (one episode or film). Alternative (not built): "apply to the rest of this season".
//  - Pressing a different kind while a start is pending replaces the pending start. Alternative: keep one pending start per kind.
//  - Credits need an end mark like the other kinds. Alternative (not built): one press for "credits start, runs to the end".
//  - Undo covers the changes made during this playback only (the flow is per playback). Alternative: a persistent history.
//  - The same limits as for every other source apply (B4, SEG-13): a mark that breaks them is refused with the reason, not stored.

/// A saved range, in seconds.
public struct MarkedRange: Equatable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }
}

/// What a mark action did. `message` is the text to show the user (plain words, no claims beyond what happened).
public enum MarkOutcome: Equatable, Sendable {
    case startMarked(SegmentType, at: TimeInterval)
    case saved(SegmentType, MarkedRange)
    /// The second press came at or before the start; the pending start is kept.
    case endNotAfterStart(SegmentType, start: TimeInterval)
    /// A limit refused the range. `reason` is a sentence.
    case refused(SegmentType, reason: String)
    case deleted(SegmentType)
    case pendingCancelled(SegmentType)
    /// The last change was reverted. `restored` is the range that is saved again, nil when the mark was removed.
    case undone(SegmentType, restored: MarkedRange?)
    case nothingToUndo
    case nothingToDelete(SegmentType)
    case noPendingMark
    /// The playhead is not known yet (playback has not started).
    case noPlayhead
    /// The ledger could not store the mark (the item has no stable key yet).
    case notStored

    public var message: String {
        switch self {
        case .startMarked(let t, let at): return "\(t.markName) start marked at \(MarkText.clock(at)). Choose Mark \(t.markName) again where it ends."
        case .saved(let t, let r): return "\(t.markName) saved: \(MarkText.clock(r.start)) to \(MarkText.clock(r.end))."
        case .endNotAfterStart(let t, let s): return "The end has to be after the start (\(MarkText.clock(s))). Move forward and choose Mark \(t.markName) again."
        case .refused(let t, let reason): return "\(t.markName) not saved. \(reason)"
        case .deleted(let t): return "\(t.markName) mark deleted."
        case .pendingCancelled(let t): return "\(t.markName) start cancelled."
        case .undone(let t, let r):
            if let r { return "Restored the earlier \(t.markName.lowercased()) mark: \(MarkText.clock(r.start)) to \(MarkText.clock(r.end))." }
            return "\(t.markName) mark removed."
        case .nothingToUndo: return "Nothing to undo."
        case .nothingToDelete(let t): return "There is no \(t.markName.lowercased()) mark to delete."
        case .noPendingMark: return "There is no start to cancel."
        case .noPlayhead: return "Playback has not started yet."
        case .notStored: return "The mark could not be saved because this title has no stored identity yet."
        }
    }

    /// True when the saved marks changed (the player rebuilds its skip data).
    public var changedMarks: Bool {
        switch self {
        case .saved, .deleted, .undone: return true
        default: return false
        }
    }
}

public enum MarkText {
    /// 65 -> "1:05", 3725 -> "1:02:05".
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? "\(h):\(two(m)):\(two(s))" : "\(m):\(two(s))"
    }
    private static func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
}

extension SegmentType {
    /// "Recap", "Intro", "Credits".
    var markName: String {
        switch self {
        case .recap: return "Recap"
        case .intro: return "Intro"
        case .credits: return "Credits"
        }
    }
}

/// What the mark menu shows.
public struct MarkMenuState: Equatable, Sendable {
    public var pending: PendingMark?
    public var marks: [SegmentType: MarkedRange]
    public var canUndo: Bool

    public struct PendingMark: Equatable, Sendable {
        public var kind: SegmentType
        public var start: TimeInterval
    }

    public init(pending: PendingMark? = nil, marks: [SegmentType: MarkedRange] = [:], canUndo: Bool = false) {
        self.pending = pending
        self.marks = marks
        self.canUndo = canUndo
    }

    /// The row title for a kind: "Mark Intro Start", or "Mark Intro End" while a start for that kind is pending.
    public func title(for kind: SegmentType) -> String {
        if let pending, pending.kind == kind { return "Mark \(kind.markName) End" }
        return "Mark \(kind.markName) Start"
    }
}

/// The player side of the mark menu. The player reads its own playhead and length, calls `SegmentMarks`, and shows the outcome.
/// `App/Features/Player/PlayerMarkMenu.swift` has a ready implementation (`PlayerMarkController`) and the menu that uses it.
@MainActor
public protocol PlayerMarkActions: AnyObject {
    /// The current menu state (cached; refreshed after every action).
    var markMenuState: MarkMenuState { get }
    func mark(_ kind: SegmentType)
    func deleteMark(_ kind: SegmentType)
    func cancelPendingMark()
    func undoLastMark()
}

/// The marks of one item during one playback. Thread-safe (one lock). Reads and writes the ledger directly.
public final class SegmentMarkSession: @unchecked Sendable {
    private enum Undo: Equatable {
        /// A save: put `previous` back (nil removes the mark).
        case restore(SegmentType, previous: MarkedRange?, duration: TimeInterval?)
    }

    private let itemKey: String
    private let ledger: UserDataLedger
    private let limits: SegmentLimits
    private let lock = NSLock()
    private var pending: MarkMenuState.PendingMark?
    private var undoStack: [Undo] = []

    public init(itemKey: String, ledger: UserDataLedger, limits: SegmentLimits = SegmentLimits()) {
        self.itemKey = itemKey
        self.ledger = ledger
        self.limits = limits
    }

    // MARK: Reading

    public var state: MarkMenuState {
        let saved = Dictionary(uniqueKeysWithValues: savedMarks().map { ($0.0, $0.1) })
        return lock.withLock { MarkMenuState(pending: pending, marks: saved, canUndo: !undoStack.isEmpty) }
    }

    private func savedMarks() -> [(SegmentType, MarkedRange)] {
        ledger.segmentMarks(forItemKey: itemKey).compactMap { m in
            SegmentType(rawValue: m.kind).map { ($0, MarkedRange(start: m.start, end: m.end)) }
        }
    }

    private func savedMark(_ kind: SegmentType) -> MarkedRange? { savedMarks().first { $0.0 == kind }?.1 }

    // MARK: Actions

    /// One press of "Mark <kind>" at `position`. `duration` is the length of the title (needed to check the limits when the range is completed).
    @discardableResult
    public func press(_ kind: SegmentType, at position: TimeInterval?, duration: TimeInterval?, date: Date? = nil) -> MarkOutcome {
        guard let position, position.isFinite, position >= 0 else { return .noPlayhead }
        let current = lock.withLock { pending }
        guard let current, current.kind == kind else {
            lock.withLock { pending = MarkMenuState.PendingMark(kind: kind, start: position) }
            return .startMarked(kind, at: position)
        }
        guard position > current.start + 0.5 else { return .endNotAfterStart(kind, start: current.start) }
        guard let duration, duration > 0, duration.isFinite else {
            return .refused(kind, reason: "The length of this title is not known yet, so the range cannot be checked. Try again in a moment.")
        }
        let range = MarkedRange(start: current.start, end: min(position, duration))
        if let reason = refusal(kind, range, duration: duration) {
            // The pending start stays, so the user can mark a better end without starting over.
            return .refused(kind, reason: reason)
        }
        let previousStored = ledger.segmentMarks(forItemKey: itemKey).first { $0.kind == kind.rawValue }
        let previous = previousStored.map { MarkedRange(start: $0.start, end: $0.end) }
        let mark = UDSegmentMark(itemKey: itemKey, kind: kind.rawValue, start: range.start, end: range.end, fileDuration: duration, createdAt: date)
        ledger.saveSegmentMark(mark, at: date)
        lock.withLock {
            pending = nil
            undoStack.append(.restore(kind, previous: previous, duration: previousStored?.fileDuration))
        }
        return .saved(kind, range)
    }

    @discardableResult
    public func delete(_ kind: SegmentType, date: Date? = nil) -> MarkOutcome {
        guard let stored = ledger.segmentMarks(forItemKey: itemKey).first(where: { $0.kind == kind.rawValue }) else { return .nothingToDelete(kind) }
        ledger.deleteSegmentMark(itemKey: itemKey, kind: kind.rawValue, at: date)
        lock.withLock {
            undoStack.append(.restore(kind, previous: MarkedRange(start: stored.start, end: stored.end), duration: stored.fileDuration))
        }
        return .deleted(kind)
    }

    @discardableResult
    public func cancelPending() -> MarkOutcome {
        lock.withLock {
            guard let p = pending else { return .noPendingMark }
            pending = nil
            return .pendingCancelled(p.kind)
        }
    }

    /// Reverts the latest save or delete of this playback. A later edit stamp is used, so the revert wins over what it reverts, also on
    /// other devices.
    @discardableResult
    public func undo(date: Date? = nil) -> MarkOutcome {
        guard let step = lock.withLock({ undoStack.popLast() }) else { return .nothingToUndo }
        switch step {
        case .restore(let kind, let previous, let duration):
            if let previous {
                let known = ledger.segmentMarks(forItemKey: itemKey).first { $0.kind == kind.rawValue }?.fileDuration
                ledger.saveSegmentMark(UDSegmentMark(itemKey: itemKey, kind: kind.rawValue, start: previous.start, end: previous.end,
                                                     fileDuration: duration ?? known, createdAt: date), at: date)
                return .undone(kind, restored: previous)
            }
            ledger.deleteSegmentMark(itemKey: itemKey, kind: kind.rawValue, at: date)
            return .undone(kind, restored: nil)
        }
    }

    // MARK: Limits

    /// The sentence for a range the limits refuse, nil when the range is fine. Uses the real resolver, so the answer is the one the
    /// player would give when it loads the mark later.
    func refusal(_ kind: SegmentType, _ range: MarkedRange, duration: TimeInterval) -> String? {
        let file = FileIdentity(path: "mark", size: 0, duration: duration)
        let candidate = SkipSegment(type: kind, start: range.start, end: range.end, source: .userMarked, confidence: SegmentCollector.userMarkConfidence, file: file)
        let result = SegmentResolver.resolve(file: file, candidates: [candidate], limits: limits)
        if !result.segments.isEmpty { return nil }
        switch result.rejected.first?.reason {
        case .introLength?: return "An intro has to be between \(Int(limits.introLength.lowerBound)) seconds and \(Int(limits.introLength.upperBound) / 60) minutes long."
        case .recapStartsTooLate?: return "A recap has to start within the first \(Int(limits.recapMaxStart)) seconds."
        case .recapTooLong?: return "A recap can be at most \(Int(limits.recapMaxLength) / 60) minutes long."
        case .creditsStartTooEarly?: return "Credits have to start in the last \(Int(((1 - limits.creditsMinStartFraction) * 100).rounded())) percent of the title."
        case .emptyOrInverted?: return "The end has to be after the start."
        default: return "That range cannot be used."
        }
    }
}
