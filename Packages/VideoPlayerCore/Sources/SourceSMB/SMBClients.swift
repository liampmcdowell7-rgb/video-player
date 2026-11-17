import Foundation

public enum SMBClients {
    /// A client backed by the real SMB library, or nil in a build that does not link it (the plain Linux unit-test run).
    /// The app uses this so it never needs to know whether the library was vendored (same idea as `NFSBackends.libnfs()`).
    public static func real(_ configuration: SMBConfiguration) -> SMBClient? {
        #if canImport(AMSMB2)
        return SMBClient.amsmb2(configuration)
        #else
        return nil
        #endif
    }
}
