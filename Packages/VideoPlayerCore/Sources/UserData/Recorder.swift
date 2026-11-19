import Foundation

/// What the library store calls (synchronously, from inside its own actor) every time the user changes something
/// that must survive a cleanup. The store has already applied the change to its own tables; this writes it to the ledger.
public protocol UserDataRecording: Sendable {
    /// A play, a stop, or "mark watched": the new state of the item as the store now holds it.
    func recordProgress(key: String, _ value: UDWatchValue, at date: Date)
    /// "Mark unwatched": a new play-count epoch starts at `date`, so older counts from other devices lose.
    /// `duration` is the item's known length, which an unwatch keeps (only position, flags and counts are cleared).
    func recordReset(key: String, duration: Double?, at date: Date)
    func recordFavorite(key: String, favorite: Bool, at date: Date)
    func recordHidden(key: String, hidden: Bool, at date: Date)
    func recordView(_ value: UDViewValue, at date: Date)
    func recordViewDeleted(uid: String, at date: Date)
}

/// Writes everything into a `UserDataLedger`.
public final class LedgerRecorder: UserDataRecording, @unchecked Sendable {
    public let ledger: UserDataLedger

    public init(ledger: UserDataLedger) {
        self.ledger = ledger
    }

    public func recordProgress(key: String, _ value: UDWatchValue, at date: Date) {
        let epoch = UDWatch.epoch(of: ledger.record(type: UDSchema.watch, id: key))
        ledger.apply(UDWatch.progressPatch(key: key, value, epoch: epoch, at: ledger.stamp(date)))
    }

    public func recordReset(key: String, duration: Double?, at date: Date) {
        let reset = UDWatchValue(position: 0, duration: duration, watched: false, playCount: 0, lastPlayed: nil, favorite: false, hidden: false)
        ledger.apply(UDWatch.progressPatch(key: key, reset, epoch: date.timeIntervalSince1970, at: ledger.stamp(date)))
    }

    public func recordFavorite(key: String, favorite: Bool, at date: Date) {
        ledger.apply(UDWatch.favoritePatch(key: key, favorite: favorite, at: ledger.stamp(date)))
    }

    public func recordHidden(key: String, hidden: Bool, at date: Date) {
        ledger.apply(UDWatch.hiddenPatch(key: key, hidden: hidden, at: ledger.stamp(date)))
    }

    public func recordView(_ value: UDViewValue, at date: Date) {
        ledger.apply(UDView.patch(value, at: ledger.stamp(date)))
    }

    public func recordViewDeleted(uid: String, at date: Date) {
        ledger.apply(UDView.tombstone(uid: uid, at: ledger.stamp(date)))
    }
}

/// Does nothing. For callers that have no ledger (and for tests that must prove the store works without one).
public struct NullRecorder: UserDataRecording {
    public init() {}
    public func recordProgress(key: String, _ value: UDWatchValue, at date: Date) {}
    public func recordReset(key: String, duration: Double?, at date: Date) {}
    public func recordFavorite(key: String, favorite: Bool, at date: Date) {}
    public func recordHidden(key: String, hidden: Bool, at date: Date) {}
    public func recordView(_ value: UDViewValue, at date: Date) {}
    public func recordViewDeleted(uid: String, at date: Date) {}
}

/// Typed reads of the ledger, for the restore path.
public extension UserDataLedger {
    func watchEntries() -> [(key: String, value: UDWatchValue)] {
        records(ofType: UDSchema.watch).compactMap { r in UDWatch.value(of: r).map { (r.id, $0) } }
    }

    func viewValues() -> [UDViewValue] {
        records(ofType: UDSchema.view).compactMap { UDView.value(of: $0) }
    }

    /// uids of saved views that were deleted (tombstones), so a restore does not bring them back.
    func deletedViewUIDs() -> [String] {
        allRecords().filter { $0.type == UDSchema.view && $0.isDeleted }.map(\.id)
    }

    func sourceDefinitions() -> [UDSourceDefinition] {
        records(ofType: UDSchema.source).compactMap { UDSource.value(of: $0) }
    }

    func settingValues() -> [String: UDValue] {
        UDSettings.values(of: record(type: UDSchema.settings, id: UDSettings.recordID))
    }

    func setSetting(_ key: String, _ value: UDValue, at date: Date? = nil) {
        apply(UDSettings.patch(key, value, at: stamp(date)))
    }

    func upsertSource(_ s: UDSourceDefinition, at date: Date? = nil) {
        apply(UDSource.patch(s, at: stamp(date)))
    }

    func removeSource(id: String, at date: Date? = nil) {
        apply(UDSource.tombstone(id: id, at: stamp(date)))
    }

    /// Every live "Move to Movies / Move to Shows" override (docs/SORTING.md).
    func sortOverrides() -> [UDSortOverrideValue] {
        records(ofType: UDSchema.sorting).compactMap { UDSortOverride.value(of: $0) }
    }

    func setSortOverride(_ value: UDSortOverrideValue, at date: Date? = nil) {
        apply(UDSortOverride.patch(value, at: stamp(date)))
    }

    func removeSortOverride(sourceID: String, path: String, at date: Date? = nil) {
        apply(UDSortOverride.tombstone(sourceID: sourceID, path: path, at: stamp(date)))
    }
}
