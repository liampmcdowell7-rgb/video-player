// swift-tools-version:5.9
import PackageDescription
import Foundation

// Pure-Swift logic (source contract, sources, file model, filename parser, matcher, ranking).
// Rules:
//  - No Apple-only frameworks here (SwiftUI, AVFoundation, AVKit, Security, MediaPlayer).
//    Anything platform-specific goes behind #if canImport(...). This keeps the package
//    buildable and testable on Linux (WSL) and on the Mac host.
//  - One target per source type (Source*). A source target depends on VideoPlayerCore only,
//    never on another source target. Native-library bindings (SMB, NFS, SFTP) go in their
//    own target and must be prebuilt binaries unless a C build was approved (docs/SOURCES.md).
let sourceNames: [String] = ["WebDAV", "Jellyfin", "Emby", "FTP", "UPnP", "Links", "OneDrive", "SFTP", "Plex"]

var products: [Product] = [.library(name: "VideoPlayerCore", targets: ["VideoPlayerCore"])]
var targets: [Target] = [
    .target(name: "VideoPlayerCore"),
    .testTarget(name: "VideoPlayerCoreTests", dependencies: ["VideoPlayerCore"])
]
var packageDependencies: [Package.Dependency] = []
for name in sourceNames {
    products.append(.library(name: "Source" + name, targets: ["Source" + name]))
    targets.append(.target(name: "Source" + name, dependencies: ["VideoPlayerCore"]))
    let own: Target.Dependency = .target(name: "Source" + name)
    // The Plex tests also run the one-time watch-state seed end to end (index, seed, no server write; R306).
    let extra: [Target.Dependency] = name == "Plex" ? ["AppLogic", "LibraryIndex", "UserData"] : []
    targets.append(.testTarget(name: "Source" + name + "Tests", dependencies: [own, "VideoPlayerCore"] + extra))
}

// --- Feature modules (library index, metadata, playback logic, subtitles, status). Pure Swift,
// each depends on VideoPlayerCore only. LibraryIndex additionally links SQLite (see below).
for name in ["MetadataLocal", "MetadataOnline", "PlaybackLogic", "Subtitles", "PlaybackStatus"] {
    products.append(.library(name: name, targets: [name]))
    targets.append(.target(name: name, dependencies: ["VideoPlayerCore"]))
    targets.append(.testTarget(name: name + "Tests", dependencies: [.target(name: name), "VideoPlayerCore"]))
}
// --- User data (the data that must survive a system cleanup of Caches): record types, merge rules, the CloudKit sync
// protocol with an in-memory fake, the small essentials copy and export/import. Foundation only, depends on VideoPlayerCore
// only; LibraryIndex depends on it to restore watch state after a purge (docs/STORAGE_MODEL.md).
products.append(.library(name: "UserData", targets: ["UserData"]))
targets.append(.target(name: "UserData", dependencies: ["VideoPlayerCore"]))
targets.append(.testTarget(name: "UserDataTests", dependencies: [.target(name: "UserData"), "VideoPlayerCore"]))
var libraryIndexDependencies: [Target.Dependency] = ["VideoPlayerCore", "UserData"]
// SQLITE-BLOCK-BEGIN (owned by the LibraryIndex work; Linux needs a system library shim, Apple has SQLite3 in the SDK)
var libraryIndexLinker: [LinkerSetting] = []
#if os(Linux)
// Linux (WSL) only: scripts/setup-sqlite.sh puts a libsqlite3.so link in $VP_TEST_HOME/sqlite/lib (default
// ~/video-player-test-servers/sqlite/lib); the header lives in Sources/CSQLiteSystem. test-core.sh runs the script.
targets.append(.systemLibrary(name: "CSQLite", path: "Sources/CSQLiteSystem"))
libraryIndexDependencies.append("CSQLite")
libraryIndexLinker.append(.unsafeFlags(["-L", (ProcessInfo.processInfo.environment["VP_TEST_HOME"] ?? (NSHomeDirectory() + "/video-player-test-servers")) + "/sqlite/lib"]))
#endif
// SQLITE-BLOCK-END
products.append(.library(name: "LibraryIndex", targets: ["LibraryIndex"]))
targets.append(.target(name: "LibraryIndex", dependencies: libraryIndexDependencies, linkerSettings: libraryIndexLinker))
targets.append(.testTarget(name: "LibraryIndexTests", dependencies: [.target(name: "LibraryIndex"), "VideoPlayerCore", "UserData", "LibraryBackup"]))

// --- iCloud backup of generated data (docs/BACKUP.md): chunked, versioned snapshots of the library index, the metadata
// answers, the Fix Match file and the pictures read from sources. The engine talks to a `BackupCloud` protocol (an
// in-memory fake in tests); the CloudKit adapter in Sources/LibraryBackup/Apple compiles only where CloudKit exists.
products.append(.library(name: "LibraryBackup", targets: ["LibraryBackup"]))
targets.append(.target(name: "LibraryBackup", dependencies: ["VideoPlayerCore", "UserData", "LibraryIndex"]))
targets.append(.testTarget(name: "LibraryBackupTests", dependencies: [.target(name: "LibraryBackup"), "UserData", "LibraryIndex"]))

// --- Remux engine (pure Swift: segmenter, box writer/checker, seek mapping, read-ahead, loopback server behind
// a protocol). Depends on VideoPlayerCore only. FFmpeg itself is NOT a dependency here (see docs/ENGINE_DESIGN.md).
products.append(.library(name: "RemuxEngine", targets: ["RemuxEngine"]))
targets.append(.target(name: "RemuxEngine", dependencies: ["VideoPlayerCore"]))
// R471 (63): SourcePlex too, for the end-to-end test of the converted path over a fake Plex server.
targets.append(.testTarget(name: "RemuxEngineTests", dependencies: [.target(name: "RemuxEngine"), "VideoPlayerCore", "SourcePlex"]))

// DOLBYVISION-BLOCK-BEGIN (owned by the Dolby Vision work, docs/DOLBY_VISION.md): profile 7 to 8.1 RPU conversion.
// Apple: a prebuilt static library (Frameworks/DolbyVisionRPULib.xcframework, MIT, licence next to it); nothing is
// compiled from C or Rust by the app build. Linux (tests only): scripts/test-dovi.sh builds the same library version
// from source and sets VP_LIBDOVI; without it the target still builds and DolbyVisionProfile7Converter.native() is nil.
var dolbyVisionRPUDependencies: [Target.Dependency] = ["RemuxEngine", "VideoPlayerCore"]
#if os(Linux)
if ProcessInfo.processInfo.environment["VP_LIBDOVI"] != nil {
    targets.append(.systemLibrary(name: "CDolbyVisionRPU", path: "Sources/CDolbyVisionRPUSystem", pkgConfig: "vp-dovi"))
    dolbyVisionRPUDependencies.append("CDolbyVisionRPU")
}
#else
targets.append(.binaryTarget(name: "DolbyVisionRPULib", path: "Frameworks/DolbyVisionRPULib.xcframework"))
targets.append(.target(name: "CDolbyVisionRPU", dependencies: ["DolbyVisionRPULib"], path: "Sources/CDolbyVisionRPU"))
dolbyVisionRPUDependencies.append("CDolbyVisionRPU")
#endif
products.append(.library(name: "DolbyVisionRPU", targets: ["DolbyVisionRPU"]))
targets.append(.target(name: "DolbyVisionRPU", dependencies: dolbyVisionRPUDependencies))
targets.append(.testTarget(name: "DolbyVisionRPUTests", dependencies: [.target(name: "DolbyVisionRPU"), "RemuxEngine", "VideoPlayerCore"]))
// DOLBYVISION-BLOCK-END

// --- App-side logic: view models for the track pickers, Now Playing, skip / Up Next buttons and the library screens.
// This is the one package target allowed to depend on other feature targets (it is glue, tested in WSL; the Apple
// wrappers live in the app target behind the protocols it defines).
products.append(.library(name: "AppLogic", targets: ["AppLogic"]))
targets.append(.target(name: "AppLogic", dependencies: ["VideoPlayerCore", "LibraryIndex", "LibraryBackup", "PlaybackLogic", "Subtitles", "PlaybackStatus", "UserData", "MetadataLocal", "MetadataOnline", "RemuxEngine", "DolbyVisionRPU"]))
targets.append(.testTarget(name: "AppLogicTests", dependencies: [.target(name: "AppLogic"), "VideoPlayerCore", "UserData", "MetadataOnline", "MetadataLocal", "RemuxEngine", "DolbyVisionRPU"]))

// --- #33: the verdicts of the screenshot UI tests (accessibility dump, cover pixels, menus, toolbar groups) as plain
// Swift. No product: the app never links it. The UI-test target compiles these files by path (project.yml), and
// ScreenChecksTests runs the same code on Linux against fixtures and, when VP_RUN_ARTIFACTS names an unzipped CI run,
// against that run's pictures and notes.
targets.append(.target(name: "ScreenChecks"))
targets.append(.testTarget(name: "ScreenChecksTests", dependencies: [.target(name: "ScreenChecks")], resources: [.copy("Fixtures")]))

// CITADEL-BLOCK-BEGIN (owned by the SFTP/Citadel work: the Citadel backend target and its test target; conditional on a
// patched local copy under Vendor/, like AMSMB2 below, so the base manifest never needs the network)
// `bash scripts/setup-citadel.sh` creates Vendor/Citadel (0.12.1, pinned commit) and Vendor/swift-nio-ssh (the Wellz26
// fork at a pinned commit plus scripts/patches/swift-nio-ssh-0.3.4-cdispatch.patch). Without both copies the target
// is not declared at all, and SourceSFTP keeps working against its in-memory backend tests.
let citadelDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
if FileManager.default.fileExists(atPath: citadelDirectory + "/Vendor/Citadel/Package.swift"),
   FileManager.default.fileExists(atPath: citadelDirectory + "/Vendor/swift-nio-ssh/Package.swift") {
    packageDependencies.append(.package(path: "Vendor/Citadel"))
    packageDependencies.append(.package(path: "Vendor/swift-nio-ssh"))
    packageDependencies.append(.package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"))
    packageDependencies.append(.package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"))
    products.append(.library(name: "SourceSFTPCitadel", targets: ["SourceSFTPCitadel"]))
    targets.append(.target(name: "SourceSFTPCitadel", dependencies: [
        "VideoPlayerCore", "SourceSFTP",
        .product(name: "Citadel", package: "Citadel"),
        .product(name: "NIOSSH", package: "swift-nio-ssh"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOFoundationCompat", package: "swift-nio"),
        .product(name: "Crypto", package: "swift-crypto"),
    ]))
    targets.append(.testTarget(name: "SourceSFTPCitadelTests", dependencies: [
        .target(name: "SourceSFTPCitadel"), "SourceSFTP", "VideoPlayerCore",
        .product(name: "Citadel", package: "Citadel"),
    ]))
}
// CITADEL-BLOCK-END

// --- SMB: AMSMB2 4.0.3 with a recorded patch (scripts/patches/AMSMB2-4.0.3-swift6.4.patch).
// The real backend is compiled only when a patched copy exists at Vendor/AMSMB2
// (scripts/test-smb.sh and the first compile check create it). Without it the module still
// builds and its 20 unit tests run against a fake.
let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
var smbDependencies: [Target.Dependency] = ["VideoPlayerCore"]
if FileManager.default.fileExists(atPath: packageDirectory + "/Vendor/AMSMB2/Package.swift") {
    packageDependencies.append(.package(path: "Vendor/AMSMB2"))
    smbDependencies.append(.product(name: "AMSMB2", package: "AMSMB2"))
}
products.append(.library(name: "SourceSMB", targets: ["SourceSMB"]))
targets.append(.target(name: "SourceSMB", dependencies: smbDependencies))
targets.append(.testTarget(name: "SourceSMBTests", dependencies: [.target(name: "SourceSMB"), "VideoPlayerCore"]))

// --- NFS: the only source with a native library, so it is wired by hand ---
var nfsDependencies: [Target.Dependency] = ["VideoPlayerCore"]
#if os(Linux)
// Linux is for tests only. scripts/test-nfs.sh builds libnfs and sets VP_LIBNFS.
if ProcessInfo.processInfo.environment["VP_LIBNFS"] != nil {
    targets.append(.systemLibrary(name: "CLibnfs", path: "Sources/CLibnfsSystem", pkgConfig: "libnfs"))
    nfsDependencies.append("CLibnfs")
}
#else
targets.append(.binaryTarget(name: "Libnfs", path: "Frameworks/Libnfs.xcframework"))
targets.append(.target(name: "CLibnfs", dependencies: ["Libnfs"], path: "Sources/CLibnfs"))
nfsDependencies.append("CLibnfs")
#endif
products.append(.library(name: "SourceNFS", targets: ["SourceNFS"]))
targets.append(.target(name: "SourceNFS", dependencies: nfsDependencies))
targets.append(.testTarget(name: "SourceNFSTests", dependencies: [.target(name: "SourceNFS"), "VideoPlayerCore"]))

// --- Range proxy (SOURCES): serves one file of a source without a URL (SMB, NFS, SFTP, FTP) as a loopback http resource with byte
// ranges, on top of RemuxEngine's loopback server and ByteRangeReader. It changes nothing in RemuxEngine (docs/SOURCES_WIRING.md).
products.append(.library(name: "SourceRangeProxy", targets: ["SourceRangeProxy"]))
targets.append(.target(name: "SourceRangeProxy", dependencies: ["VideoPlayerCore", "RemuxEngine"]))
targets.append(.testTarget(name: "SourceRangeProxyTests", dependencies: [.target(name: "SourceRangeProxy"), "RemuxEngine", "VideoPlayerCore"]))

// AUDIO-DECODE-BLOCK-BEGIN (owned by the audio pipeline work, docs/AUDIO_PIPELINE.md)
// AudioDecode: DTS / DTS-HD / TrueHD / MLP / Opus / Vorbis decoded and repackaged as FLAC, behind RemuxEngine's AudioTranscoding.
// CMediaCodecs is the small C layer over the codec library. Apple platforms link the vendored dynamic frameworks in
// Frameworks/MediaCodecs (LGPL-2.1-or-later, device and simulator slices only; licences and the build record next to them).
// Linux is for tests only: scripts/test-audio.sh builds the same library version as shared libraries and sets VP_MEDIACODECS
// (its install prefix); without it the targets are not declared, like NFS above.
var audioDecodeDeclared = false
#if os(Linux)
if let mediaCodecsPrefix = ProcessInfo.processInfo.environment["VP_MEDIACODECS"] {
    targets.append(.systemLibrary(name: "CMediaCodecsSystem", path: "Sources/CMediaCodecsSystem", pkgConfig: "libavcodec"))
    targets.append(.target(name: "CMediaCodecs", dependencies: ["CMediaCodecsSystem"], path: "Sources/CMediaCodecs",
                           cSettings: [.unsafeFlags(["-I", mediaCodecsPrefix + "/include"])],
                           linkerSettings: [.unsafeFlags(["-L", mediaCodecsPrefix + "/lib"])]))
    audioDecodeDeclared = true
}
#else
let mediaCodecFrameworks = ["AetherLibavcodec", "AetherLibavutil", "AetherLibswresample", "AetherLibdav1d", "AetherLibzvbi"]
for name in mediaCodecFrameworks {
    // Binary target names equal the framework names (PROVISIONAL: SwiftPM matches them to the bundle inside the xcframework).
    targets.append(.binaryTarget(name: name, path: "Frameworks/MediaCodecs/\(name).xcframework"))
}
targets.append(.target(name: "CMediaCodecs", dependencies: mediaCodecFrameworks.map { .byName(name: $0) }, path: "Sources/CMediaCodecs"))
audioDecodeDeclared = true
#endif
if audioDecodeDeclared {
    products.append(.library(name: "AudioDecode", targets: ["AudioDecode"]))
    targets.append(.target(name: "AudioDecode", dependencies: ["CMediaCodecs", "RemuxEngine", "VideoPlayerCore"]))
    targets.append(.testTarget(name: "AudioDecodeTests", dependencies: [.target(name: "AudioDecode"), "RemuxEngine", "VideoPlayerCore"]))
}
// AUDIO-DECODE-BLOCK-END

let package = Package(
    name: "VideoPlayerCore",
    platforms: [.tvOS("27.0"), .macOS(.v14)],
    products: products,
    dependencies: packageDependencies,
    targets: targets
)
