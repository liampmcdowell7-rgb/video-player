import Foundation

/// Why iCloud cannot be used at all by this copy of the app (not a passing state such as "signed out" or "offline").
/// Example: a build that carries no iCloud capability (the unsigned CI simulator build), where creating the CloudKit
/// container is refused. The text is shown in Settings (Storage and iCloud, Backup).
public struct CloudUnavailable: Error, Equatable, Sendable {
    public var reason: String
    public init(_ reason: String) { self.reason = reason }

    /// The default wording when the platform object could not be created.
    public static let notInThisBuild = CloudUnavailable("iCloud is not available in this copy of the app (no iCloud capability).")
}

/// Creates a platform object (the CloudKit container) the first time it is needed, never while the app is starting, and
/// only once: later calls get the same object, or the same reason it could not be made. Launch-safety rule
/// (docs/API_USAGE.md "Launch safety"): nothing that needs an entitlement is created in an initializer on the launch path,
/// so a missing iCloud capability can never stop the first frame from being drawn.
public final class LazyCloudResource<Value>: @unchecked Sendable {
    public typealias Maker = @Sendable () -> Result<Value, CloudUnavailable>

    private let lock = NSLock()
    private let make: Maker
    private var outcome: Result<Value, CloudUnavailable>?
    private var attempts = 0

    public init(_ make: @escaping Maker) { self.make = make }

    /// A resource that is never available (UI-test modes, tests, and builds that must not touch iCloud).
    public static func unavailable(_ reason: CloudUnavailable) -> LazyCloudResource<Value> {
        LazyCloudResource { .failure(reason) }
    }

    /// The object, made on the first call. Throws `CloudUnavailable` when it could not be made (every later call too).
    public func value() throws -> Value {
        try resolve().get()
    }

    /// Nil when the object exists (or can be made now); the reason otherwise. Makes the object if that was not tried yet.
    public func unavailableReason() -> CloudUnavailable? {
        if case .failure(let reason) = resolve() { return reason }
        return nil
    }

    /// True once a creation was tried (for tests: proves nothing was made at construction time).
    public var wasAttempted: Bool { lock.withLock { attempts > 0 } }

    private func resolve() -> Result<Value, CloudUnavailable> {
        lock.lock()
        defer { lock.unlock() }
        if let outcome { return outcome }
        attempts += 1
        let made = make()
        outcome = made
        return made
    }
}
