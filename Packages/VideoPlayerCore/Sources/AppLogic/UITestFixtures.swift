#if DEBUG
import Foundation
import VideoPlayerCore
import LibraryIndex
import UserData

// SYNTHETIC sample library for UI-test screenshots (UITestLaunch.fixtures). Debug builds only: this whole file is inside
// `#if DEBUG`, so it is not in a Release build (UITestLaunchTests checks the guard).
//
// Strict rules (user request, 2026-11-18): invented generic titles only ("Sample Movie 1", "Sample Show 1"), pictures
// generated here as plain gradients, no real film, show, person or company name, no copied image, no network. The
// technical fields are realistic so the badges and version rows show real format names.
//
// The library is filled through the real path: `FixtureSource` is an in-memory `MediaSource`, `LibrarySyncer` scans it
// into the store exactly as it scans a server, then the technical details and watch states are written through the store's
// public calls. Reading a video file throws (there is no video), so pressing Play shows the playback error screen.

public enum UITestFixtures {
    public static let sourceID = "uitest-sample-library"
    public static let sourceName = "Sample Library"
    /// Rule D7: what a sample source says instead of its type's verification status.
    public static let sampleStatus = "Sample data: not tested against any server"
    /// True for the built-in sample sources; their ids start with "uitest-".
    public static func isSample(_ sourceID: String) -> Bool { sourceID.hasPrefix("uitest-") }
    /// A fixed date so the screenshots are the same on every run (the "added" order and the dates in file details).
    public static let referenceDate = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 00:00 UTC

    public static var definition: UDSourceDefinition {
        UDSourceDefinition(id: sourceID, kind: SourceKind.webdav.rawValue, name: sourceName, host: "sample.invalid", path: "/",
                           addedAt: referenceDate)
    }

    /// A Jellyfin source that is never scanned or contacted (UI-test launches do not scan; `.invalid` never resolves). It
    /// exists only so the source page with "Sort by Filename Instead of Server Library Types" can be drawn (addendum #18 B).
    public static let serverID = "uitest-sample-server"
    public static var serverDefinition: UDSourceDefinition {
        UDSourceDefinition(id: serverID, kind: SourceKind.jellyfin.rawValue, name: "Sample Server", host: "server.sample.invalid",
                           addedAt: referenceDate)
    }

    // MARK: Content

    /// Files that end in Needs Review (addendum #18 B): no episode marker, no year, no folder hint. One very long name (it
    /// must wrap, never be cut) and one plain name with no year. Synthetic names only.
    static let review: [String] = [
        "/Unsorted/Sample Clip.mkv",
        "/Unsorted/Sample Unsorted Recital.mkv",
        "/Unsorted/Sample Unsorted Birthday.mp4",
        "/Unsorted/Sample Unsorted Garden Walk.mkv",
        "/Unsorted/Sample Unsorted Holiday Morning.mkv",
        "/Unsorted/Sample Unsorted Lecture.m4v",
        "/Unsorted/Sample Unsorted Lone Show - 007.mkv",
        "/Unsorted/Sample Unsorted Road Trip.mkv",
        "/Unsorted/Sample Unsorted Clip With A Very Long File Name That Runs Far Past The Width Of One Row On The Screen And Keeps Going.mkv",
    ]

    struct Video {
        var path: String
        var size: Int64
        var technical: FileTechnicalInfo
    }

    enum Watch { case none, watched, progress(Double), favorite }

    struct Title {
        var folder: String
        var videos: [Video]
        var watch: Watch
        var hue: Double
        var subtitles: Bool
    }

    static func tech(_ height: Int, _ codec: String, _ hdr: Set<HDRFormat>, dv: Int? = nil, audio: String, channels: Int,
                     atmos: Bool = false, duration: Double, bitrate: Int64, container: ContainerFormat = .mkv) -> FileTechnicalInfo {
        FileTechnicalInfo(duration: duration, container: container, width: height * 16 / 9, height: height, hdrFormats: hdr,
                          dolbyVisionProfile: dv, videoCodec: codec, audioCodec: audio, audioChannels: channels, hasAtmos: atmos,
                          bitrate: bitrate)
    }

    static let movies: [Title] = [
        Title(folder: "/Movies/Sample Movie 1 (2021)", videos: [
            Video(path: "/Movies/Sample Movie 1 (2021)/Sample Movie 1 (2021) 2160p.mkv", size: 52_300_000_000,
                  technical: tech(2160, "hevc", [.dolbyVision, .hdr10], dv: 8, audio: "truehd", channels: 8, atmos: true,
                                  duration: 7260, bitrate: 57_600_000)),
        ], watch: .progress(0.4), hue: 0.58, subtitles: true),
        Title(folder: "/Movies/Sample Movie 2 (2019)", videos: [
            Video(path: "/Movies/Sample Movie 2 (2019)/Sample Movie 2 (2019) - 2160p.mkv", size: 61_000_000_000,
                  technical: tech(2160, "hevc", [.hdr10], audio: "dtshdma", channels: 6, duration: 8100, bitrate: 60_200_000)),
            Video(path: "/Movies/Sample Movie 2 (2019)/Sample Movie 2 (2019) - 1080p.mkv", size: 14_200_000_000,
                  technical: tech(1080, "h264", [], audio: "eac3", channels: 6, duration: 8100, bitrate: 14_000_000)),
        ], watch: .watched, hue: 0.05, subtitles: true),
        Title(folder: "/Movies/Sample Movie 3 (2018)", videos: [
            Video(path: "/Movies/Sample Movie 3 (2018)/Sample Movie 3 (2018) 1080p.mp4", size: 9_800_000_000,
                  technical: tech(1080, "h264", [], audio: "flac", channels: 2, duration: 5880, bitrate: 13_300_000, container: .mp4)),
        ], watch: .favorite, hue: 0.33, subtitles: false),
        Title(folder: "/Movies/Sample Movie 4 (2022)", videos: [
            Video(path: "/Movies/Sample Movie 4 (2022)/Sample Movie 4 (2022) 2160p.mkv", size: 21_400_000_000,
                  technical: tech(2160, "hevc", [.hdr10Plus], audio: "eac3", channels: 6, atmos: true, duration: 6900,
                                  bitrate: 24_800_000)),
        ], watch: .progress(0.75), hue: 0.80, subtitles: true),
        Title(folder: "/Movies/Sample Movie 5 (2020)", videos: [
            Video(path: "/Movies/Sample Movie 5 (2020)/Sample Movie 5 (2020) 720p.mp4", size: 3_100_000_000,
                  technical: tech(720, "h264", [], audio: "aac", channels: 2, duration: 5400, bitrate: 4_600_000, container: .mp4)),
        ], watch: .none, hue: 0.12, subtitles: false),
        Title(folder: "/Movies/Sample Movie 6 (2017)", videos: [
            Video(path: "/Movies/Sample Movie 6 (2017)/Sample Movie 6 (2017) 2160p.mkv", size: 18_900_000_000,
                  technical: tech(2160, "hevc", [.hlg], audio: "ac3", channels: 6, duration: 6300, bitrate: 24_000_000)),
        ], watch: .none, hue: 0.45, subtitles: false),
        // #17 C: a title far longer than a card is wide, so the Larger Text screenshots show how a card title scales and
        // keeps its side padding (rule S1, never cut). Synthetic, like the others.
        Title(folder: "/Movies/Sample Movie 7 With A Much Longer Title Than Any Card Is Wide (2023)", videos: [
            Video(path: "/Movies/Sample Movie 7 With A Much Longer Title Than Any Card Is Wide (2023)/Sample Movie 7 With A Much Longer Title Than Any Card Is Wide (2023) 2160p.mkv",
                  size: 23_700_000_000,
                  technical: tech(2160, "hevc", [.dolbyVision, .hdr10], dv: 8, audio: "truehd", channels: 8, atmos: true,
                                  duration: 7020, bitrate: 27_000_000)),
        ], watch: .progress(0.2), hue: 0.25, subtitles: false),
    ]

    /// (show folder, seasons with episode counts, hue). Show 1: season 1 watched, season 2 episode 1 half-way.
    static let shows: [(folder: String, seasons: [Int], hue: Double)] = [
        ("/Shows/Sample Show 1", [4, 3], 0.65),
        ("/Shows/Sample Show 2", [3], 0.95),
    ]

    static func episodePath(show: String, season: Int, episode: Int) -> String {
        let name = (show as NSString).lastPathComponent
        return "\(show)/Season \(season)/\(name) - S\(two(season))E\(two(episode)).mkv"
    }

    static func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    static var episodes: [Video] {
        var out: [Video] = []
        for (index, show) in shows.enumerated() {
            for (s, count) in show.seasons.enumerated() {
                for e in 1...count {
                    let t = index == 0
                        ? tech(1080, "hevc", [.hdr10], audio: "eac3", channels: 6, duration: 2580, bitrate: 12_000_000)
                        : tech(2160, "hevc", [.dolbyVision, .hdr10], dv: 8, audio: "eac3", channels: 6, atmos: true, duration: 3120,
                               bitrate: 16_000_000)
                    out.append(Video(path: episodePath(show: show.folder, season: s + 1, episode: e), size: index == 0 ? 3_900_000_000 : 6_200_000_000,
                                     technical: t))
                }
            }
        }
        return out
    }

    /// Every file of the sample source with its bytes (pictures and subtitles) or its size only (videos and picture subtitles).
    static func files() -> [String: FixtureSource.File] {
        var files: [String: FixtureSource.File] = [:]
        for movie in movies {
            for video in movie.videos { files[video.path] = .init(size: video.size, data: nil) }
            files[movie.folder + "/poster.png"] = .init(data: GradientPNG.make(width: 240, height: 360, hue: movie.hue))
            files[movie.folder + "/fanart.png"] = .init(data: GradientPNG.make(width: 480, height: 270, hue: movie.hue + 0.08))
            if movie.subtitles, let first = movie.videos.first {
                let stem = ((first.path as NSString).lastPathComponent as NSString).deletingPathExtension
                files[movie.folder + "/" + stem + ".en.srt"] = .init(data: Data(sampleSubtitles.utf8))
                files[movie.folder + "/" + stem + ".en.sup"] = .init(size: 2_400_000, data: nil)
            }
        }
        for show in shows {
            files[show.folder + "/poster.png"] = .init(data: GradientPNG.make(width: 240, height: 360, hue: show.hue))
            files[show.folder + "/fanart.png"] = .init(data: GradientPNG.make(width: 480, height: 270, hue: show.hue + 0.08))
        }
        for (folder, logo) in logos { files[folder + "/clearlogo.png"] = .init(data: logo.png) }
        for episode in episodes { files[episode.path] = .init(size: episode.size, data: nil) }
        for (i, path) in review.enumerated() { files[path] = .init(size: 700_000_000 + Int64(i) * 10_000_000, data: nil) }
        return files
    }

    /// #15 9.6 and D7: generated title logos (no real artwork). Movie 2 and Show 1 get a good one (the screenshots of their
    /// pages, and the accessibility set 90/96/107 and 91/97/108, show it); Movie 3 a dark one, Movie 5 one with a solid
    /// background, Movie 6 a tiny one: all three are rejected by `TitleLogoRules.check`, so those pages keep the text title.
    /// The other titles have none.
    static let logos: [(folder: String, logo: LogoPNG)] = [
        ("/Movies/Sample Movie 2 (2019)", LogoPNG(width: 800, height: 200, ink: (245, 245, 245), background: nil)),
        ("/Shows/Sample Show 1", LogoPNG(width: 900, height: 240, ink: (250, 236, 200), background: nil)),
        ("/Movies/Sample Movie 3 (2018)", LogoPNG(width: 800, height: 200, ink: (25, 20, 35), background: nil)),
        ("/Movies/Sample Movie 5 (2020)", LogoPNG(width: 800, height: 200, ink: (245, 245, 245), background: (40, 40, 40))),
        ("/Movies/Sample Movie 6 (2017)", LogoPNG(width: 120, height: 40, ink: (245, 245, 245), background: nil)),
    ]

    static let sampleSubtitles = "1\n00:00:01,000 --> 00:00:04,000\nSample subtitle line one.\n\n2\n00:00:05,000 --> 00:00:08,000\nSample subtitle line two.\n"

    // MARK: Seeding

    /// Scans the sample source into `store` and writes the technical details and watch states. `now` is the time the watch
    /// states are stamped with (recent, so Continue Watching shows them).
    public static func seed(into store: SQLiteLibraryStore, now: Date = Date()) async throws {
        try await store.upsertSource(LibrarySourceRecord(id: sourceID, kind: .webdav, name: sourceName, addedAt: referenceDate))
        try await LibrarySyncer(store: store, source: FixtureSource(), sourceID: sourceID, clock: { referenceDate }).sync()

        var technical: [String: FileTechnicalInfo] = [:]
        for movie in movies { for v in movie.videos { technical[v.path] = v.technical } }
        for v in episodes { technical[v.path] = v.technical }

        let items = try await allItems(store)
        for item in items {
            for file in try await store.versions(of: item.id) {
                if let t = technical[file.path] { try await store.setTechnicalInfo(fileID: file.id, t) }
            }
        }
        // Watch states, matched by the folder the item's file is in.
        for item in items {
            guard let file = try await store.versions(of: item.id).first else { continue }
            if let movie = movies.first(where: { file.path.hasPrefix($0.folder + "/") }) {
                let duration = movie.videos[0].technical.duration ?? 0
                switch movie.watch {
                case .none: break
                case .watched: try await store.markWatched(itemIDs: [item.id], watched: true, at: now.addingTimeInterval(-86_400 * 3))
                case .progress(let f): try await store.updateProgress(itemID: item.id, position: duration * f, duration: duration, at: now.addingTimeInterval(-3_600))
                case .favorite: try await store.setFavorite(itemID: item.id, favorite: true)
                }
            } else if file.path.hasPrefix(shows[0].folder + "/Season 1/") {
                try await store.markWatched(itemIDs: [item.id], watched: true, at: now.addingTimeInterval(-86_400 * 2))
            } else if file.path == episodePath(show: shows[0].folder, season: 2, episode: 1) {
                try await store.updateProgress(itemID: item.id, position: 2580 * 0.3, duration: 2580, at: now.addingTimeInterval(-7_200))
            }
        }
    }

    static func allItems(_ store: SQLiteLibraryStore) async throws -> [LibraryItem] {
        var out: [LibraryItem] = []
        while true {
            let page = try await store.page(ItemQuery(), limit: 200, offset: out.count)
            out += page
            if page.count < 200 { return out }
        }
    }

    /// Every title, show and person-free text in the sample library, for the test that checks only generic names are used.
    static var allNames: [String] { Array(files().keys) + [sourceName, serverDefinition.name, sampleSubtitles] }
}

/// In-memory source with the sample files. Lists folders, gives the bytes of pictures and subtitles, and refuses to read a
/// video (there is none).
public struct FixtureSource: MediaSource {
    struct File: Sendable {
        var size: Int64
        var data: Data?
        init(size: Int64, data: Data?) { self.size = size; self.data = data }
        init(data: Data) { self.size = Int64(data.count); self.data = data }
    }

    let files: [String: File]
    let children: [String: [SourceEntry]]

    public init() {
        let files = UITestFixtures.files()
        var children: [String: Set<SourceEntry>] = [:]
        let date = UITestFixtures.referenceDate
        for (path, file) in files {
            var current = path
            var entry = SourceEntry(path: path, name: (path as NSString).lastPathComponent, isDirectory: false, size: file.size,
                                    modified: date)
            while current != "/" {
                let parent = (current as NSString).deletingLastPathComponent
                let parentPath = parent.isEmpty ? "/" : parent
                children[parentPath, default: []].insert(entry)
                current = parentPath
                entry = SourceEntry(path: parentPath, name: (parentPath as NSString).lastPathComponent, isDirectory: true, modified: date)
            }
        }
        self.files = files
        self.children = children.mapValues { $0.sorted { $0.name < $1.name } }
    }

    public var kind: SourceKind { .webdav }
    public var capabilities: SourceCapabilities {
        SourceCapabilities(authMethods: [.none], byteRanges: true, changeSignals: [.size, .modified])
    }

    public func authenticate() async throws {}

    public func list(_ path: String) async throws -> [SourceEntry] {
        if let list = children[path] { return list }
        if files[path] != nil { throw SourceError.unsupported("Not a folder.") }
        throw SourceError.notFound
    }

    public func info(_ path: String) async throws -> SourceEntry {
        let name = (path as NSString).lastPathComponent
        if let file = files[path] {
            return SourceEntry(path: path, name: name, isDirectory: false, size: file.size, modified: UITestFixtures.referenceDate)
        }
        if children[path] != nil {
            return SourceEntry(path: path, name: path == "/" ? "" : name, isDirectory: true, modified: UITestFixtures.referenceDate)
        }
        throw SourceError.notFound
    }

    public func read(_ path: String, range: ByteRange) async throws -> Data {
        guard let file = files[path] else { throw SourceError.notFound }
        guard let data = file.data else { throw SourceError.unsupported(Self.noVideo) }
        let start = Int(max(0, range.offset))
        guard start < data.count else { return Data() }
        let end = min(data.count, start + Int(max(0, range.length)))
        return data.subdata(in: start..<end)
    }

    public func playbackAccess(for path: String) async throws -> PlaybackAccess {
        throw SourceError.unsupported(Self.noVideo)
    }

    static let noVideo = "This is a sample file made for screenshots. It has no video."
}

/// A generated "title logo" (#15 9.6): blocky bars that stand in for lettering, in one ink colour, on a transparent background
/// (RGBA PNG) or on a solid one. Synthetic: no real title's artwork.
struct LogoPNG {
    var width: Int
    var height: Int
    var ink: (UInt8, UInt8, UInt8)
    var background: (UInt8, UInt8, UInt8)?

    /// The pixels, row after row, RGBA (what `LogoPixels.measure` reads; the fixture tests check them).
    var rgba: [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(width * height * 4)
        let letters = 7
        let cell = max(1, width / (letters * 3 + 1))
        let top = height / 5, bottom = height - height / 5
        for y in 0..<height {
            for x in 0..<width {
                // Letter k covers columns [cell*(3k+1), cell*(3k+3)); every other letter has a gap in its middle third.
                let k = x / cell
                let inLetter = k % 3 != 0 && k / 3 < letters && y >= top && y < bottom
                let gap = (k / 3) % 2 == 1 && y >= top + (bottom - top) / 3 && y < bottom - (bottom - top) / 3 && k % 3 == 1
                if inLetter && !gap {
                    out += [ink.0, ink.1, ink.2, 255]
                } else if let b = background {
                    out += [b.0, b.1, b.2, 255]
                } else {
                    out += [0, 0, 0, 0]
                }
            }
        }
        return out
    }

    var png: Data {
        let pixels = rgba
        var raw = Data(capacity: height * (1 + width * 4))
        for y in 0..<height {
            raw.append(0) // filter: none
            raw.append(contentsOf: pixels[(y * width * 4)..<((y + 1) * width * 4)])
        }
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var header = Data()
        header.append(GradientPNG.be32(UInt32(width))); header.append(GradientPNG.be32(UInt32(height)))
        header.append(contentsOf: [8, 6, 0, 0, 0]) // 8-bit, truecolour with alpha, deflate, adaptive filter, no interlace
        png.append(GradientPNG.chunk("IHDR", header))
        png.append(GradientPNG.chunk("IDAT", GradientPNG.zlibStored(raw)))
        png.append(GradientPNG.chunk("IEND", Data()))
        return png
    }
}

/// A small RGB PNG with a vertical two-colour gradient, encoded here (stored deflate blocks, no compression library).
enum GradientPNG {
    static func make(width: Int, height: Int, hue: Double) -> Data {
        let top = rgb(hue: hue, saturation: 0.55, value: 0.85)
        let bottom = rgb(hue: hue + 0.1, saturation: 0.75, value: 0.30)
        var raw = Data(capacity: height * (1 + width * 3))
        for y in 0..<height {
            raw.append(0) // filter: none
            let t = height > 1 ? Double(y) / Double(height - 1) : 0
            let r = UInt8(Double(top.0) * (1 - t) + Double(bottom.0) * t)
            let g = UInt8(Double(top.1) * (1 - t) + Double(bottom.1) * t)
            let b = UInt8(Double(top.2) * (1 - t) + Double(bottom.2) * t)
            for _ in 0..<width { raw.append(contentsOf: [r, g, b]) }
        }
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var header = Data()
        header.append(be32(UInt32(width))); header.append(be32(UInt32(height)))
        header.append(contentsOf: [8, 2, 0, 0, 0]) // 8-bit, truecolour, deflate, adaptive filter, no interlace
        png.append(chunk("IHDR", header))
        png.append(chunk("IDAT", zlibStored(raw)))
        png.append(chunk("IEND", Data()))
        return png
    }

    static func rgb(hue: Double, saturation s: Double, value v: Double) -> (UInt8, UInt8, UInt8) {
        let h = (hue - hue.rounded(.down)) * 6
        let i = Int(h) % 6
        let f = h - Double(Int(h))
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        let (r, g, b): (Double, Double, Double)
        switch i {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
        return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))
    }

    static func zlibStored(_ data: Data) -> Data {
        var out = Data([0x78, 0x01])
        let bytes = [UInt8](data)
        var offset = 0
        repeat {
            let length = min(65_535, bytes.count - offset)
            let final: UInt8 = offset + length >= bytes.count ? 1 : 0
            out.append(final)
            out.append(contentsOf: [UInt8(length & 0xFF), UInt8(length >> 8), UInt8(~length & 0xFF), UInt8((~length >> 8) & 0xFF)])
            out.append(contentsOf: bytes[offset..<(offset + length)])
            offset += length
        } while offset < bytes.count
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in bytes { a = (a + UInt32(byte)) % 65_521; b = (b + a) % 65_521 }
        out.append(be32((b << 16) | a))
        return out
    }

    static func chunk(_ type: String, _ body: Data) -> Data {
        var out = be32(UInt32(body.count))
        var typed = Data(type.utf8)
        typed.append(body)
        out.append(typed)
        out.append(be32(crc32(typed)))
        return out
    }

    static func be32(_ v: UInt32) -> Data { Data([UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]) }

    static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for byte in data { c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }
}
#endif
