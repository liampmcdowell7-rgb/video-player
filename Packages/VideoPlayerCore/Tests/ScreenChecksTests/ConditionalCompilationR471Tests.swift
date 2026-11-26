import Foundation
import XCTest
@testable import ScreenChecks

/// R471 (111): the package tests run on Linux, so a branch under `#if os(tvOS)`, `#if canImport(...)` and the like is
/// only parsed there, never compiled. Every package source file that has such a branch is listed here; each is unchanged
/// since 96ebfea, which TestFlight run #8 built. A new file with a branch, or one that loses its branches, fails this test,
/// so the branch is read as the compiler would before the list is updated.
extension ScreenChecksTests {
    static let packageFilesWithConditionalBranches: Set<String> = [
        "AppLogic/SourceConnectionLogic.swift",
        "AppLogic/UITestFixtureDetails.swift",
        "AppLogic/UITestFixtureDiscover.swift",
        "AppLogic/UITestFixtures.swift",
        "AppLogic/UITestLaunch.swift",
        "DolbyVisionRPU/NativeRPUCodec.swift",
        "DolbyVisionRPU/Profile7Converter.swift",
        "LibraryBackup/Apple/CloudKitBackupCloud.swift",
        "LibraryBackup/BackupCloud.swift",
        "LibraryIndex/SQLiteSupport.swift",
        "MetadataLocal/NFOXML.swift",
        "RemuxEngine/Loopback.swift",
        "SourceFTP/FTPStream.swift",
        "SourceFTP/NetworkFTPStream.swift",
        "SourceFTP/POSIXFTPStream.swift",
        "SourceNFS/LibnfsBackend.swift",
        "SourceNFS/NFSBackends.swift",
        "SourceSMB/AMSMB2Backend.swift",
        "SourceSMB/SMBClients.swift",
        "SourceUPnP/SSDP.swift",
        "SourceUPnP/UPnPParsers.swift",
        "SourceWebDAV/PropfindParser.swift",
        "UserData/Apple/CloudKitContainers.swift",
        "UserData/Apple/CloudKitSecretCloud.swift",
        "UserData/Apple/CloudKitUserDataCloud.swift",
        "UserData/Apple/KeychainCredentialStore.swift",
        "VideoPlayerCore/HTTP/HTTPTransport.swift",
    ]

    func testEveryPackageFileWithABranchLinuxSkipsIsListed() throws {
        // Found the same way as appSource: VP_PROJECT_ROOT, else five levels up from this file.
        guard try appSource("Packages/VideoPlayerCore/Package.swift") != nil else { return }
        var roots: [URL] = []
        if let root = ProcessInfo.processInfo.environment["VP_PROJECT_ROOT"], !root.isEmpty {
            roots.append(URL(fileURLWithPath: root))
        }
        roots.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
        let sources = try XCTUnwrap(roots.map { $0.appendingPathComponent("Packages/VideoPlayerCore/Sources") }
            .first { FileManager.default.fileExists(atPath: $0.path) })
        let prefix = sources.standardizedFileURL.path + "/"
        var found: Set<String> = []
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let branches = text.split(separator: "\n").contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("#if") || trimmed.hasPrefix("#elseif")
            }
            if branches {
                let path = url.standardizedFileURL.path
                found.insert(path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path)
            }
        }
        XCTAssertEqual(found.subtracting(Self.packageFilesWithConditionalBranches).sorted(), [],
                       "new branches Linux does not compile: read them as the tvOS compiler would, then list them (R471 (111))")
        XCTAssertEqual(Self.packageFilesWithConditionalBranches.subtracting(found).sorted(), [],
                       "listed files no longer have a branch: take them off the list")
    }
}
