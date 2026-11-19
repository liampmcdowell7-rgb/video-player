import Foundation
import VideoPlayerCore
import LibraryIndex
import UserData
import MetadataOnline

// The app side of per-file sorting (docs/SORTING.md): the words for each signal, the "Sort by filename" source setting,
// the Move to Movies / Move to Shows form, the Needs Review list, and the online check (signal d). The decision itself is
// in LibraryIndex (MediaSorter); overrides are ledger records, read by the next scan.

// MARK: Texts

public enum SortTexts {
    /// A short name for the rule that decided, for the item info ("Sorted By").
    public static func title(_ signal: SortSignal) -> String {
        switch signal {
        case .episodePattern: return "Episode Pattern in the File Name"
        case .moviePattern: return "Year in the File Name"
        case .folderHint: return "Folder Hint"
        case .onlineLookup: return "Online Lookup"
        case .serverType: return "Server Library Type"
        case .filenameOverServer: return "File Name, Not the Server"
        case .manual: return "Moved by Hand"
        case .undecided: return "Needs Review"
        }
    }

    /// One line for the item info: the rule, then why.
    public static func line(_ record: FileSortRecord) -> String {
        let note = record.note.trimmingCharacters(in: .whitespaces)
        return note.isEmpty ? title(record.signal) : title(record.signal) + ". " + note
    }

    /// The log line written for every sorted file (Console, subsystem of the app; no secrets: path and rule only).
    public static func logLine(path: String, outcome: SortOutcome, signal: SortSignal, note: String) -> String {
        "sorted \(outcome.rawValue) by \(signal.rawValue): \(path) (\(note))"
    }

    public static let reviewFooter = "These files could not be sorted into Movies or Shows. They are not shown anywhere else until you move them."
}

// MARK: Source setting

/// "Sort by filename instead of server library types" (PROVISIONAL, default off, OPEN_QUESTIONS): only for sources whose
/// server has its own library types (Jellyfin, Emby). Kept in the source definition's options, so it syncs.
public enum SortSourceOption {
    public static let key = "sortByFilename"
    public static let title = "Sort by Filename Instead of Server Library Types"
    public static let footer = "When on, the file name decides Movies or Shows even where the server's own library says otherwise."

    public static func applies(toKind kind: String) -> Bool { kind == SourceKind.jellyfin.rawValue || kind == SourceKind.emby.rawValue }

    public static func preferFilename(_ definition: UDSourceDefinition) -> Bool {
        applies(toKind: definition.kind) && SourceOptions.parse(definition.options)[key] == "1"
    }

    public static func setting(_ on: Bool, on definition: UDSourceDefinition) -> UDSourceDefinition {
        var options = SourceOptions.parse(definition.options)
        options[key] = on ? "1" : nil
        var d = definition
        d.options = SourceOptions.format(options)
        return d
    }
}

// MARK: Move to Movies / Move to Shows

public enum SortMoveError: Error, Equatable, Sendable {
    case emptyTitle, badYear, badSeason, badEpisode, badEpisodeEnd
}

extension SortMoveError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyTitle: return "Enter a title."
        case .badYear: return "Enter a year from 1888 to 2100, or leave it empty."
        case .badSeason: return "Enter a season number from 0 to 999."
        case .badEpisode: return "Enter an episode number from 1 to 9999."
        case .badEpisodeEnd: return "The last episode must be after the first one, or leave it empty."
        }
    }
}

/// The fields of the Move sheet, as typed. Filled in from the file name; checked by `value(sourceID:path:)`.
public struct SortMoveDraft: Equatable, Sendable {
    public var kind: UDSortOverrideValue.Kind
    /// The movie title, or the show name.
    public var title: String
    public var year: String
    public var season: String
    public var episode: String
    public var episodeEnd: String

    public init(kind: UDSortOverrideValue.Kind, title: String, year: String = "", season: String = "", episode: String = "", episodeEnd: String = "") {
        self.kind = kind; self.title = title; self.year = year; self.season = season; self.episode = episode; self.episodeEnd = episodeEnd
    }

    /// Prefilled from what the file name says (the folders give a title only when the name has none).
    public init(kind: UDSortOverrideValue.Kind, fileName: String, folders: [String]) {
        let p = FilenameParser.parse(fileName: fileName, folders: folders, weakMarkers: kind == .episode)
        self.kind = kind
        title = p.title
        year = p.year.map(String.init) ?? ""
        if kind == .episode {
            season = String(p.season ?? 1)
            episode = (p.episodes.first ?? p.absoluteEpisode).map(String.init) ?? ""
            episodeEnd = p.episodes.count > 1 ? String(p.episodes.last!) : ""
        } else {
            season = ""; episode = ""; episodeEnd = ""
        }
    }

    public var sheetTitle: String { kind == .movie ? "Move to Movies" : "Move to Shows" }
    public var titleLabel: String { kind == .movie ? "Title" : "Show" }

    public func value(sourceID: String, path: String, signal: SortSignal = .manual) throws -> UDSortOverrideValue {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw SortMoveError.emptyTitle }
        let y = try Self.number(year, in: 1888...2100, error: .badYear)
        guard kind == .episode else {
            return UDSortOverrideValue(sourceID: sourceID, path: path, kind: .movie, title: name, year: y, signal: signal.rawValue)
        }
        guard let s = try Self.number(season, in: 0...999, error: .badSeason) else { throw SortMoveError.badSeason }
        guard let e = try Self.number(episode, in: 1...9999, error: .badEpisode) else { throw SortMoveError.badEpisode }
        let end = try Self.number(episodeEnd, in: 1...9999, error: .badEpisodeEnd)
        if let end, end < e { throw SortMoveError.badEpisodeEnd }
        return UDSortOverrideValue(sourceID: sourceID, path: path, kind: .episode, title: name, year: y, season: s, episode: e,
                                   episodeEnd: end == e ? nil : end, signal: signal.rawValue)
    }

    private static func number(_ text: String, in range: ClosedRange<Int>, error: SortMoveError) throws -> Int? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        guard let n = Int(t), range.contains(n) else { throw error }
        return n
    }
}

/// Where Move choices are kept: the synced user-data ledger. A protocol so the logic is tested without one.
public protocol SortOverrideWriting: Sendable {
    func setSortOverride(_ value: UDSortOverrideValue)
    func removeSortOverride(sourceID: String, path: String)
    func sortOverrides() -> [UDSortOverrideValue]
}

extension UserDataLedger: SortOverrideWriting {
    public func setSortOverride(_ value: UDSortOverrideValue) { setSortOverride(value, at: nil) }
    public func removeSortOverride(sourceID: String, path: String) { removeSortOverride(sourceID: sourceID, path: path, at: nil) }
}

/// Moves a library item (every version of it) or one Needs Review file. The next scan files it as asked.
public struct SortMover: Sendable {
    public let store: any LibraryStore
    public let writer: any SortOverrideWriting

    public init(store: any LibraryStore, writer: any SortOverrideWriting) {
        self.store = store
        self.writer = writer
    }

    /// The Move sheet for an item already in Movies or Shows, filled from its first file. Nil when it has no file.
    public func draft(itemID: Int64, to kind: UDSortOverrideValue.Kind) async throws -> SortMoveDraft? {
        guard let file = try await store.versions(of: itemID).first else { return nil }
        var d = SortMoveDraft(kind: kind, fileName: file.name, folders: Self.folders(of: file.path))
        if let item = try await store.item(id: itemID) {
            // The item's own title is better than the file name's (it may come from the folder or an earlier move); an
            // episode moved to Movies takes its show's name.
            let shown = item.seriesTitle ?? item.title
            if !shown.isEmpty { d.title = shown }
            if d.year.isEmpty, let y = item.year { d.year = String(y) }
        }
        return d
    }

    public func draft(for entry: ReviewEntry, to kind: UDSortOverrideValue.Kind) -> SortMoveDraft {
        SortMoveDraft(kind: kind, fileName: entry.fileName, folders: Self.folders(of: entry.path))
    }

    /// Saves the choice for every version of the item. Returns how many files it covers.
    @discardableResult
    public func move(itemID: Int64, _ draft: SortMoveDraft) async throws -> Int {
        let files = try await store.versions(of: itemID)
        for file in files { writer.setSortOverride(try draft.value(sourceID: file.sourceID, path: file.path)) }
        return files.count
    }

    public func move(_ entry: ReviewEntry, _ draft: SortMoveDraft) throws {
        writer.setSortOverride(try draft.value(sourceID: entry.sourceID, path: entry.path))
    }

    /// Takes back every Move choice for the item's files, so the rules decide again on the next scan.
    public func sortAutomatically(itemID: Int64) async throws {
        for file in try await store.versions(of: itemID) { writer.removeSortOverride(sourceID: file.sourceID, path: file.path) }
    }

    /// Ancestor folder names, nearest first.
    public static func folders(of path: String) -> [String] {
        Array(path.split(separator: "/").dropLast().reversed()).map(String.init)
    }
}

// MARK: Needs Review list

public struct NeedsReviewViewModel: Sendable {
    public static let limit = 500
    public let store: any LibraryStore
    public private(set) var state: ViewState<[ReviewEntry]> = .idle

    public init(store: any LibraryStore) { self.store = store }

    public mutating func load() async {
        state = .loading
        do {
            let entries = try await store.needsReview(limit: Self.limit)
            state = entries.isEmpty
                ? .empty(EmptyState(reason: .noMatches, title: "Nothing to Review", message: "Every video file is in Movies or Shows."))
                : .loaded(entries)
        } catch {
            state = .failed(ErrorState.from(error, doing: "load Needs Review"))
        }
    }

    /// Takes a moved file off the list at once (the next scan files it).
    public mutating func remove(_ entry: ReviewEntry) {
        guard case .loaded(var entries) = state else { return }
        entries.removeAll { $0.id == entry.id }
        state = entries.isEmpty
            ? .empty(EmptyState(reason: .noMatches, title: "Nothing to Review", message: "Every video file is in Movies or Shows."))
            : .loaded(entries)
    }
}

// MARK: Online check (signal d)

/// One title search, as the matcher does it. `MatchEngine` is the real one; tests use a fake.
public protocol SortLookup: Sendable {
    func lookUp(_ input: MatchInput) async throws -> MatchOutcome
}

extension MatchEngine: SortLookup {
    public func lookUp(_ input: MatchInput) async throws -> MatchOutcome { try await match(input) }
}

/// Signal d (docs/SORTING.md): for each Needs Review file, a TMDB title search as a movie and, only when the name has
/// episode numbers, as a show. Exactly one side confirmed at 0.8 or more moves the file (an "onlineLookup" override in the
/// ledger, so it syncs and survives rescans); both or neither leaves it in Needs Review. Runs only when the user entered
/// their own key (the app builds the lookup only then); there is no separate on/off switch for online lookups.
public struct OnlineSortResolver: Sendable {
    public static let threshold = 0.8
    /// At most this many files per run, so a large unsorted folder does not send hundreds of searches at once.
    public static let perRun = 40

    public let lookup: any SortLookup
    public let writer: any SortOverrideWriting

    public init(lookup: any SortLookup, writer: any SortOverrideWriting) {
        self.lookup = lookup
        self.writer = writer
    }

    /// What the check decided for one file; nil when it stays in Needs Review.
    public func decide(_ entry: ReviewEntry) async -> UDSortOverrideValue? {
        let folders = SortMover.folders(of: entry.path)
        var asMovie = FilenameParser.parse(fileName: entry.fileName, folders: folders, weakMarkers: false)
        asMovie.kind = .movie
        guard !MediaSorter.showKey(asMovie.title).isEmpty else { return nil }
        let movie = await confirmed(MatchInput(parsed: asMovie, folderNames: folders))

        var asShow = FilenameParser.parse(fileName: entry.fileName, folders: folders)
        let numbers = !asShow.episodes.isEmpty || asShow.absoluteEpisode != nil
        var show: MatchResult?
        if numbers, !MediaSorter.showKey(asShow.title).isEmpty {
            asShow.kind = .episode
            show = await confirmed(MatchInput(parsed: asShow, folderNames: folders))
        }

        switch (movie, show) {
        case (let m?, nil):
            return UDSortOverrideValue(sourceID: entry.sourceID, path: entry.path, kind: .movie, title: asMovie.title,
                                       year: asMovie.year ?? m.year, signal: SortSignal.onlineLookup.rawValue)
        case (nil, _?):
            let first = asShow.episodes.first ?? asShow.absoluteEpisode ?? 1
            let last = asShow.episodes.count > 1 ? asShow.episodes.last : nil
            return UDSortOverrideValue(sourceID: entry.sourceID, path: entry.path, kind: .episode, title: asShow.title,
                                       year: asShow.year, season: asShow.season ?? 1, episode: first, episodeEnd: last,
                                       signal: SortSignal.onlineLookup.rawValue)
        default:
            return nil
        }
    }

    /// Checks up to `perRun` files and saves what it confirmed. Returns the saved choices (the caller scans again when any).
    public func run(_ entries: [ReviewEntry], skipping tried: Set<String> = []) async -> [UDSortOverrideValue] {
        var saved: [UDSortOverrideValue] = []
        for entry in entries.filter({ !tried.contains(Self.key($0)) }).prefix(Self.perRun) {
            if Task.isCancelled { break }
            if let value = await decide(entry) {
                writer.setSortOverride(value)
                saved.append(value)
            }
        }
        return saved
    }

    public static func key(_ entry: ReviewEntry) -> String { entry.sourceID + "\n" + entry.path }

    private func confirmed(_ input: MatchInput) async -> MatchResult? {
        guard case .matched(let result)? = try? await lookup.lookUp(input), result.confidence >= Self.threshold else { return nil }
        return result
    }
}
