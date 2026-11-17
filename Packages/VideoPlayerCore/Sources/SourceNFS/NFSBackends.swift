import Foundation

public enum NFSBackends {
    /// The libnfs-backed backend, or nil in a build that does not link libnfs (plain Linux unit-test runs).
    public static func libnfs() -> NFSBackend? {
        #if canImport(CLibnfs)
        return LibnfsBackend()
        #else
        return nil
        #endif
    }
}
