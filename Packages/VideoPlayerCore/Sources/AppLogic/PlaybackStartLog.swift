import Foundation

// R311 (owner's device test of build 5, 21 Nov 2026): playing an episode opened a black player that hung for about 30 seconds
// and then closed with no message. This file is the pure part of the answer, tested on Linux:
//  - every step of starting a playback has a name (`PlaybackStep`), so a failure says where it stopped;
//  - each step has a time limit (`PlaybackStartDeadline`), so a start that hangs ends with a plain message instead of a
//    black screen;
//  - the last problem is kept as a `PlaybackProblem` (step, source kind, container, codecs, error text with every token
//    removed), which Settings > Playback shows as "Last Playback Problem" so the owner can read it without a Mac;
//  - `PlaybackFailurePolicy` says that every failure is shown while the player screen is up (only a screen the person has
//    already closed shows nothing).

/// One step of starting a playback, in the order they run.
public enum PlaybackStep: String, Codable, CaseIterable, Sendable {
    case findFile, prepareSample, checkFormat, checkServer, openConverter, getLink, readSegments
    case openPlayer, playerReady, resumeSeek, startPlaying, playing

    /// What the step does, as the diagnostic row says it.
    public var title: String {
        switch self {
        case .findFile: return "Finding the file in the library"
        case .prepareSample: return "Preparing the sample clip"
        case .checkFormat: return "Checking the file’s format"
        case .checkServer: return "Asking the server about the file"
        case .openConverter: return "Opening the file in the converting player"
        case .getLink: return "Getting the file’s link from the source"
        case .readSegments: return "Reading intro and credits markers"
        case .openPlayer: return "Handing the file to the system player"
        case .playerReady: return "Waiting for the system player to open the file"
        case .resumeSeek: return "Moving to the saved position"
        case .startPlaying: return "Starting playback"
        case .playing: return "Playing"
        }
    }

    /// The steps that run before the player is on screen (the resolution of the file).
    public var isResolution: Bool {
        switch self {
        case .findFile, .prepareSample, .checkFormat, .checkServer, .openConverter, .getLink, .readSegments: return true
        default: return false
        }
    }
}

/// How long each part of a start may take before it is reported as a failure (R311, PROVISIONAL: the numbers are a first
/// guess; a slow server on a slow network may need more).
public enum PlaybackStartDeadline {
    /// Finding the file, asking the server and opening it (a Plex server that is still listing its library can be slow).
    public static let resolutionSeconds: Double = 60
    /// From the player getting the file to its item being ready to play.
    public static let readySeconds: Double = 30
    /// The move to the saved position.
    public static let seekSeconds: Double = 20
    /// From asking the player to play to the first moving picture.
    public static let playingSeconds: Double = 30

    /// The limit for a step, nil for a step that has none (playing).
    public static func limit(for step: PlaybackStep) -> Double? {
        switch step {
        case .playerReady, .openPlayer: return readySeconds
        case .resumeSeek: return seekSeconds
        case .startPlaying: return playingSeconds
        case .playing: return nil
        default: return resolutionSeconds
        }
    }

    /// True when `step`, started at `since`, has run past its limit at `now`.
    public static func isOverdue(_ step: PlaybackStep, since: Double, now: Double) -> Bool {
        guard let limit = limit(for: step) else { return false }
        return now - since >= limit
    }
}

extension PlaybackFailures {
    /// A step of the start did not finish in time (R311). Says which step, so the person (and the diagnostic row) knows
    /// where it stopped. "Try Again" is offered.
    public static func startTimedOut(_ step: PlaybackStep, seconds: Double) -> PlaybackFailure {
        PlaybackFailure(kind: .other,
                        message: "The video did not start. This step took longer than \(Int(seconds)) seconds: \(step.title.lowercasedFirst).",
                        advice: "Try again. Settings > Playback shows what went wrong.")
    }
}

/// When a failure is shown (R311). Before, a failure of kind `.cancelled` closed the player with no message; the device test
/// of build 5 showed that a start that is not the person's own leaving can end that way too.
public enum PlaybackFailurePolicy {
    /// Every failure is shown while the player screen is still up; nothing is shown for a screen the person closed.
    public static func shows(_ failure: PlaybackFailure, screenClosed: Bool) -> Bool { !screenClosed }
}

/// The last playback that failed, as Settings > Playback shows it (R311). Kept on this Apple TV only (never synced, never in
/// a backup); every token is removed before it is stored.
public struct PlaybackProblem: Codable, Equatable, Sendable {
    public var step: PlaybackStep
    /// The source type as the app names it ("Plex", "SMB"), nil when not known yet.
    public var sourceKind: String?
    /// The file's container ("MKV", "MP4"), nil when not known yet.
    public var container: String?
    /// Video and audio codecs as far as known ("HEVC, E-AC-3"), nil when not known.
    public var codecs: String?
    /// The error, already redacted.
    public var error: String
    public var at: Date
    /// R386: the system player's error (domain, code, underlying errors), already redacted; nil when there was none.
    /// Optional, so a problem stored by an earlier version still decodes.
    public var player: PlayerErrorReport?
    /// R386: the player's last events, newest last, already redacted; nil or empty when the player never opened.
    public var events: [PlaybackEvent]?
    /// R390: the checkpoints of the start (file opened, item ready, first frame, ...) and the path; nil for a problem stored
    /// by an earlier version.
    public var checkpoints: PlaybackCheckpoints?

    public init(step: PlaybackStep, sourceKind: String?, container: String?, codecs: String?, error: String, at: Date,
                player: PlayerErrorReport? = nil, events: [PlaybackEvent]? = nil, checkpoints: PlaybackCheckpoints? = nil) {
        self.step = step
        self.sourceKind = sourceKind
        self.container = container
        self.codecs = codecs
        self.error = error
        self.at = at
        self.player = player
        self.events = events
        self.checkpoints = checkpoints
    }

    /// R386: the last event the player reported, with its time.
    public var lastEvent: PlaybackEvent? { events?.last }

    /// The rows of the diagnostic section, label and value; unknown values say "Not known". The error text is last.
    /// R390: the path, the start result and each checkpoint (reached with its time, or not reached) come before it.
    public var rows: [(label: String, value: String)] {
        [("Step", step.title),
         ("Source", sourceKind ?? Self.notKnown),
         ("Container", container ?? Self.notKnown),
         ("Codecs", codecs ?? Self.notKnown),
         ("Error Code", player?.codeLine ?? Self.notKnown),
         ("Underlying Error", player?.underlyingText ?? Self.notKnown),
         ("Last Event", lastEvent?.line() ?? Self.notKnown)]
            + (checkpoints?.rows ?? [])
            + [("Error", error)]
    }

    /// R386: the lines under the failure's sentence on the failure screen, in plain text the owner can photograph: the
    /// system player's error domain and code, its message, each underlying error, and the last event with its time.
    public func screenLines(timeZone: TimeZone = .current) -> [String] {
        var lines: [String] = []
        if let player {
            lines.append("Error: " + player.codeLine)
            if !player.message.isEmpty { lines.append("Message: " + player.message) }
            for inner in player.underlying { lines.append("Underlying: " + inner) }
        }
        if let last = lastEvent { lines.append("Last event: " + last.line(timeZone: timeZone)) }
        lines.append("Step: " + step.title)
        // R390: how far the start got (never ready / ready, no frame / a frame, then stopped) and each checkpoint.
        if let checkpoints { lines += checkpoints.screenLines }
        return lines
    }

    /// R386: everything known, for the full report page in Settings (the recent events oldest first).
    public func fullText(timeZone: TimeZone = .current) -> String {
        var out = rows.map { "\($0.label): \($0.value)" }
        if let player, !player.message.isEmpty { out.append("Player Message: " + player.message) }
        if let notes = checkpoints?.notes, !notes.isEmpty {
            out.append("")
            out.append("Notes:")
            out += notes
        }
        let recent = events ?? []
        if !recent.isEmpty {
            out.append("")
            out.append("Recent Events:")
            out += recent.map { $0.line(timeZone: timeZone) }
        }
        out.append("")
        out.append("Recorded: " + PlaybackEvent.time(at, timeZone: timeZone))
        return out.joined(separator: "\n")
    }

    public static let notKnown = "Not known"
    public static let fullReportTitle = "Full Problem Report"
    public static let sectionTitle = "Last Playback Problem"
    public static let noneText = "No playback problem recorded on this Apple TV."
    public static let storageKey = "lastPlaybackProblem"

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    public static func decoded(_ data: Data?) -> PlaybackProblem? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(PlaybackProblem.self, from: data)
    }
}

/// Removes tokens and passwords from text before it is stored or shown (R311). Known secrets (the header values the player
/// was given) are replaced wherever they appear; token-looking query items and authorization headers are replaced even
/// when their value is not known here.
public enum PlaybackRedaction {
    public static let placeholder = "<removed>"

    public static func redact(_ text: String, secrets: [String] = []) -> String {
        var out = text
        for secret in secrets where secret.count >= 4 {
            out = out.replacingOccurrences(of: secret, with: placeholder)
        }
        let patterns = [
            "(?i)((?:x-plex-token|token|access_token|api_key|apikey|password|auth)=)[^&\\s\"'<>]+",
            "(?i)((?:x-plex-token|authorization|cookie)\"?\\s*[:=]\\s*\"?)(?:bearer\\s+|basic\\s+)?[^\\s\"',;}&<>]+",
            "(?i)(bearer\\s+)[\\w.~+/=-]+",
            "(://[^/\\s:@]+:)[^/\\s@]+(@)",
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let template = pattern.hasSuffix("(@)") ? "$1" + placeholder + "$2" : "$1" + placeholder
            out = regex.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: template)
        }
        return out
    }
}

/// Follows one start through its steps and builds the problem when it fails (R311). The player screen owns one per start.
public final class PlaybackStartTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var current: PlaybackStep = .findFile
    private var since: Double
    private var sourceKind: String?
    private var container: String?
    private var codecs: String?
    private var secrets: [String] = []
    private var line: String?
    /// R390: the checkpoints of this start, timed from when the start was asked for (`startedAt`).
    private var marks = PlaybackCheckpoints()
    private let startedAt: Double
    private let clock: @Sendable () -> Double

    public init(clock: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
        let now = clock()
        self.since = now
        self.startedAt = now
    }

    /// R390: marks a checkpoint reached now (the first time counts).
    public func reach(_ kind: PlaybackCheckpointKind, detail: String? = nil) {
        let now = clock()
        lock.withLock { marks.reach(kind, at: now - startedAt, detail: detail) }
    }

    /// R390: what was found at a checkpoint that was not reached.
    public func describe(_ kind: PlaybackCheckpointKind, detail: String) {
        lock.withLock { marks.describe(kind, detail: detail) }
    }

    /// R390: a plain sentence for the report (a video track that cannot be shown, what the loopback served).
    public func note(_ text: String) {
        lock.withLock { marks.note(text) }
    }

    /// R390: which way the file reaches the player.
    public func setPath(_ path: PlaybackPath) {
        lock.withLock { marks.path = path }
    }

    /// R390: the checkpoints as they stand.
    public var checkpoints: PlaybackCheckpoints { lock.withLock { marks } }

    /// The step running now and when it started (for the deadline check).
    public var step: (step: PlaybackStep, since: Double) { lock.withLock { (current, since) } }

    public func enter(_ step: PlaybackStep) {
        let now = clock()
        lock.withLock {
            current = step
            since = now
        }
    }

    /// What is known about the file. Nil arguments keep what was known before.
    public func describe(sourceKind: String? = nil, container: String? = nil, codecs: String? = nil, secrets: [String] = []) {
        lock.withLock {
            if let sourceKind { self.sourceKind = sourceKind }
            if let container { self.container = container }
            if let codecs, !codecs.isEmpty { self.codecs = codecs }
            self.secrets += secrets.filter { !$0.isEmpty }
        }
    }

    /// R313: which episode is being started ("Show · S1, E3 · Name"), for the first line of the error; nil for a film.
    public var itemLine: String? {
        get { lock.withLock { line } }
        set { lock.withLock { line = newValue } }
    }

    /// True when the running step has passed its limit.
    public var isOverdue: Bool {
        let (step, since) = self.step
        return PlaybackStartDeadline.isOverdue(step, since: since, now: clock())
    }

    /// The problem for a failure at the running step. `detail` is the underlying error's own text, when it says more than
    /// the failure's sentence.
    /// R386: `player` and `events` are kept too, every string redacted the same way.
    public func problem(_ failure: PlaybackFailure, detail: String? = nil, player: PlayerErrorReport? = nil,
                        events: [PlaybackEvent] = [], at date: Date = Date()) -> PlaybackProblem {
        lock.withLock {
            var text = failure.message
            if let detail, !detail.isEmpty, !text.contains(detail) { text += " (" + detail + ")" }
            let secrets = self.secrets
            let clean: (String) -> String = { PlaybackRedaction.redact($0, secrets: secrets) }
            var kept = events
            for i in kept.indices { kept[i].name = clean(kept[i].name) }
            return PlaybackProblem(step: current, sourceKind: sourceKind, container: container, codecs: codecs,
                                   error: clean(text), at: date, player: player?.mapped(clean),
                                   events: kept.isEmpty ? nil : kept, checkpoints: marks.mapped(clean))
        }
    }

    /// R386: the problem for `diagnostics` (the player's report and events).
    public func problem(_ failure: PlaybackFailure, diagnostics: PlaybackDiagnostics, at date: Date = Date()) -> PlaybackProblem {
        problem(failure, detail: diagnostics.detail, player: diagnostics.player, events: diagnostics.events, at: date)
    }

    /// Codec names joined for the row ("HEVC, E-AC-3"), empty names left out, each name once.
    public static func codecText(_ names: [String?]) -> String? {
        var seen = Set<String>()
        let kept = names.compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && seen.insert($0).inserted }
        return kept.isEmpty ? nil : kept.joined(separator: ", ")
    }

    /// The container named from the file name's extension ("MKV"), nil when there is none.
    public static func containerName(fileName: String) -> String? {
        let ext = (fileName as NSString).pathExtension
        return ext.isEmpty ? nil : ext.uppercased()
    }
}

extension String {
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}

/// How a watched start ended (R311).
public enum PlaybackStartOutcome<Value: Sendable>: Sendable {
    case finished(Value)
    case failed(any Error)
    /// The step ran past its limit (`PlaybackStartDeadline`); the work was cancelled and is no longer waited for.
    case overdue(PlaybackStep, seconds: Double)
}

/// Runs the resolution of a playback while checking the running step's time limit once per `tick` (R311). Before, a step
/// that never finished (a server that does not answer, a store busy with a long scan) left the spinner up for good, and the
/// person's only way out closed the player with no message. Two unstructured tasks race, as in `TimeBox`; a value that
/// arrives after the limit was reported goes to `onLate`, so the caller can close what it opened.
public enum PlaybackStartWatch {
    public static func run<Value: Sendable>(
        tracker: PlaybackStartTracker,
        every tick: Double = 1,
        sleep: @escaping @Sendable (Double) async -> Void = { s in try? await Task.sleep(nanoseconds: UInt64(max(0, s) * 1_000_000_000)) },
        onTick: @escaping @Sendable (PlaybackStep) async -> Void = { _ in },
        onLate: @escaping @Sendable (Value) async -> Void = { _ in },
        _ operation: @escaping @Sendable () async throws -> Value
    ) async -> PlaybackStartOutcome<Value> {
        let work = Task { try await operation() }
        let once = OutcomeOnce<PlaybackStartOutcome<Value>>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                once.set(continuation)
                let watch = Task {
                    while !Task.isCancelled {
                        await sleep(tick)
                        if Task.isCancelled { return }
                        let step = tracker.step.step
                        await onTick(step)
                        if tracker.isOverdue {
                            work.cancel()
                            once.resume(.overdue(step, seconds: PlaybackStartDeadline.limit(for: step) ?? 0))
                            return
                        }
                    }
                }
                Task {
                    let outcome: PlaybackStartOutcome<Value>
                    do {
                        let value = try await work.value
                        outcome = .finished(value)
                        watch.cancel()
                        if !once.resume(outcome) { await onLate(value) }
                    } catch {
                        watch.cancel()
                        once.resume(.failed(error))
                    }
                }
            }
        } onCancel: {
            work.cancel()
        }
    }
}

/// Resumes a continuation at most once; `resume` says whether this call was the one that did.
private final class OutcomeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?
    private var done = false

    func set(_ c: CheckedContinuation<Value, Never>) {
        lock.withLock { continuation = c }
    }

    @discardableResult
    func resume(_ value: Value) -> Bool {
        let c: CheckedContinuation<Value, Never>? = lock.withLock {
            guard !done else { return nil }
            done = true
            let c = continuation
            continuation = nil
            return c
        }
        guard let c else { return false }
        c.resume(returning: value)
        return true
    }
}
