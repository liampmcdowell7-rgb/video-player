import Foundation

/// Waits for slow work for a limited time without stopping it (launch time-box, OPEN_QUESTIONS R169).
///
/// At launch the iCloud start-up (account check, restore of an empty library, the start-up sync) can be slow or hang when
/// iCloud is slow or offline. The app waits for it at most a few seconds before its own launch work (the library scan) goes
/// on; the iCloud work is NOT cancelled and finishes in the background.
public enum TimeBox {
    /// How long the launch waits for the iCloud start-up before the library scan starts anyway.
    public static let launchWait: Double = 8

    /// Starts `operation` and waits for it at most `seconds`. Returns its result when it finished in time, nil when the time
    /// ran out; in that case `operation` keeps running to the end (it is an unstructured task, not a child of this call).
    /// `sleep` is injected so tests do not wait.
    public static func wait<T: Sendable>(
        atMost seconds: Double,
        sleep: @escaping @Sendable (Double) async -> Void = { s in try? await Task.sleep(nanoseconds: UInt64(max(0, s) * 1_000_000_000)) },
        _ operation: @escaping @Sendable () async -> T
    ) async -> T? {
        // Not a task group: a group returns only after ALL its children end, and a child awaiting `work.value` does not end
        // on cancellation, so the caller would wait for the slow work after all (caught by TimeBoxTests, 2026-11-18). Two
        // unstructured tasks race instead and the first one resumes the caller exactly once.
        let work = Task { await operation() }
        let once = ResumeOnce<T?>()
        return await withCheckedContinuation { continuation in
            once.set(continuation)
            let timer = Task { await sleep(seconds); once.resume(nil) }
            Task {
                let value = await work.value
                timer.cancel()
                once.resume(value)
            }
        }
    }
}

/// Resumes a continuation at most once, from whichever task gets there first. `set` is always called before either task
/// is created (inside the `withCheckedContinuation` body), so a `resume` never arrives before it; later calls do nothing.
private final class ResumeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    func set(_ c: CheckedContinuation<Value, Never>) {
        lock.lock(); continuation = c; lock.unlock()
    }

    func resume(_ value: Value) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: value)
    }
}
