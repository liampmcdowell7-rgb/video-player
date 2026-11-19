import Foundation
import UserData

/// When a backup runs (docs/BACKUP.md "When it runs"): after a library change has settled (debounced), at launch when the
/// last backup is old, and on demand. Never through background sync (decision D8). Pure logic, tested in WSL.
public actor BackupScheduler {
    public static let settleDelay: Double = 120
    public static let staleAfter: Double = 24 * 3600

    private let run: @Sendable () async -> Void
    private let sleep: @Sendable (Double) async throws -> Void
    private var pending: Task<Void, Never>?
    private var running = false
    private var again = false
    public private(set) var runs = 0

    public init(sleep: @escaping @Sendable (Double) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
                run: @escaping @Sendable () async -> Void) {
        self.sleep = sleep
        self.run = run
    }

    /// The library changed. Each call restarts the settle timer, so a scan of 1,000 files causes one backup, not 1,000.
    public func libraryChanged() {
        pending?.cancel()
        pending = Task(priority: .background) { [sleep] in
            do { try await sleep(Self.settleDelay) } catch { return }
            await self.fire()
        }
    }

    /// App launch: back up now when the last successful backup is older than a day (or there is none).
    public func appLaunched(lastSuccess: Date?, now: Date) async {
        if let lastSuccess, now.timeIntervalSince(lastSuccess) < Self.staleAfter { return }
        await fire()
    }

    /// "Back Up Now".
    public func backUpNow() async { await fire() }

    /// Waits for a pending settle timer (tests).
    public func waitForPending() async { await pending?.value }

    private func fire() async {
        if running { again = true; return }
        running = true
        repeat {
            again = false
            runs += 1
            await run()
        } while again
        running = false
    }
}

/// The sentences the Backup screen shows. English placeholders until localisation, like `UDStatusText`.
public enum BackupStatusText {
    public static let intro = "Back up what Video Player has built from your videos (the library, details, matches and pictures) to your own iCloud storage, so the library comes back in seconds after a cleanup, a reinstall or on a new Apple TV. Your videos themselves are never uploaded."
    public static let storageNote = "This uses your own iCloud storage, which other iCloud features share. It is stored in your private iCloud database through Apple's CloudKit, not on a server of the developer."
    public static let libraryDetail = "The library index, details and ratings found online, your Fix Match choices and the files read next to your videos."
    public static let artworkDetail = "Posters, backgrounds and other pictures read from your sources. A picture used twice is stored once."
    public static let userDataDetail = "Watch history, saved views, your sources (without passwords) and settings. These are kept in iCloud by Video Player's iCloud sync."
    public static let neverIncluded = "Never included: your videos, passwords, sign-in tokens and API keys."
    public static let restoreConfirmation = "Restore from iCloud replaces the library index, details and pictures on this Apple TV with the copy in iCloud. Your watch history and anything you changed more recently on this Apple TV are kept."
    public static let restoringBanner = "Restoring your library from iCloud"

    // #15 3.9 and #17 D: the Backup page keeps one summary sentence and short lines; the complete explanation (the texts
    // above, unchanged) is on its "Learn More" page.
    public static let summary = "A copy in your own iCloud of what the app built from your videos. Your videos are never uploaded."
    public static let whatShort = "The library and pictures. Never your videos, passwords, sign-in tokens or API keys."
    public static let learnMoreTitle = "About Backup"
    public static var learnMore: String {
        [intro, storageNote, "Library Data: " + libraryDetail, "Artwork: " + artworkDetail,
         "Settings and Watch State: " + userDataDetail, neverIncluded].joined(separator: "\n\n")
    }

    public static func line(_ status: BackupStatus) -> String {
        switch status {
        case .idle: return ""
        case .signedOut: return "Sign in to iCloud in the Settings app on this Apple TV to back up your library."
        case .iCloudFull: return "Your iCloud storage is full, so the backup could not finish. Free up space in iCloud, or turn off the artwork backup."
        case .offline: return "iCloud could not be reached. The backup will try again later."
        case .newerBackup: return "The backup in iCloud was made by a newer version of Video Player. Update Video Player on this Apple TV to restore it."
        case .backingUp(let p): return "Backing up \(p.set == .library ? "the library" : "pictures"): \(Int((p.fraction * 100).rounded())) %"
        case .restoring(let p): return "Restoring \(p.set == .library ? "the library" : "pictures"): \(Int((p.fraction * 100).rounded())) %"
        case .failed(let message): return "The last backup did not finish: \(message)"
        }
    }

    /// The size the screen shows, measured from the stored chunks.
    public static func size(_ bytes: Int) -> String {
        let units = ["bytes", "KB", "MB", "GB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1000, unit < units.count - 1 { value /= 1000; unit += 1 }
        guard unit > 0 else { return "\(bytes) bytes" }
        return (value < 10 ? String(format: "%.1f", value) : String(format: "%.0f", value)) + " " + units[unit]
    }

    public static func skippedLine(_ skipped: [BackupSkip]) -> String? {
        guard !skipped.isEmpty else { return nil }
        let bytes = skipped.reduce(0) { $0 + $1.size }
        let full = skipped.contains { $0.reason == .iCloudFull }
        return "\(skipped.count) \(skipped.count == 1 ? "file was" : "files were") left out (\(size(bytes)))\(full ? " because iCloud is full" : ""). They will be fetched again from your sources when needed."
    }

    static func describe(_ e: UDCloudError) -> String {
        switch e {
        case .limitExceeded: return "a request was too large for iCloud"
        case .rateLimited: return "iCloud asked to wait"
        case .quotaExceeded: return "iCloud is full"
        case .notAuthenticated: return "not signed in to iCloud"
        case .networkUnavailable: return "no network"
        case .changeTokenExpired: return "iCloud needs a full refresh"
        case .recordTooLarge(let k): return "an item is too large (\(k))"
        case .other(let s): return s
        }
    }

    static func describe(_ e: BackupError) -> String {
        switch e {
        case .cloud(let c): return describe(c)
        case .checksumMismatch: return "a part of the backup was damaged in transfer"
        case .newerBackup: return "made by a newer version"
        case .secretDetected: return "a file held a password or key, so nothing was uploaded"
        case .nothingToRestore: return "there is no backup in iCloud yet"
        case .backupChanged: return "the backup changed while it was being read; try again"
        case .local(let s): return s
        }
    }
}
