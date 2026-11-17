import Foundation

/// What the Top Shelf extension shows, written by the app into the App Group container as one small JSON file plus
/// artwork files. The container is NOT durable storage on tvOS: the system may delete any of it when space is low and the
/// app is not running (docs/STORAGE_MODEL.md). So the extension reads defensively: a missing, empty, damaged, oversized
/// or unknown-version file, or a missing image, means "show nothing", never a crash and never a half row.
public struct TopShelfSnapshot: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var subtitle: String?
        /// File name inside the snapshot folder (never a path).
        public var imageFile: String
        /// A link the app opens (a deep link), never a file path or a server address with a password.
        public var link: String
        /// 0...1, or nil.
        public var progress: Double?

        public init(id: String, title: String, subtitle: String? = nil, imageFile: String, link: String, progress: Double? = nil) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.imageFile = imageFile
            self.link = link
            self.progress = progress
        }
    }

    public static let currentVersion = 1
    public var version: Int
    public var generatedAt: Double
    public var items: [Item]

    public init(generatedAt: Date, items: [Item]) {
        self.version = Self.currentVersion
        self.generatedAt = generatedAt.timeIntervalSince1970
        self.items = items
    }

    public static let empty = TopShelfSnapshot(generatedAt: Date(timeIntervalSince1970: 0), items: [])
}

public enum TopShelfSnapshotStore {
    public static let fileName = "topshelf.json"
    /// A snapshot file larger than this is treated as damaged (a real one is a few kilobytes).
    public static let maxBytes = 512_000
    public static let maxItems = 24

    /// One item the extension can draw: its artwork exists.
    public struct ReadyItem: Equatable, Sendable {
        public var item: TopShelfSnapshot.Item
        public var imageURL: URL
    }

    public enum ReadOutcome: Equatable, Sendable {
        case items([ReadyItem])
        /// Nothing to show, and why (for the log; the extension just shows nothing).
        case nothing(reason: String)
    }

    public static func write(_ snapshot: TopShelfSnapshot, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }

    /// Never throws, never traps. Items whose artwork is missing are left out (a Top Shelf item without a picture is worse than none).
    public static func read(from directory: URL, fileManager: FileManager = .default) -> ReadOutcome {
        let file = directory.appendingPathComponent(fileName)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: file.path, isDirectory: &isDirectory) else { return .nothing(reason: "no snapshot file") }
        guard !isDirectory.boolValue else { return .nothing(reason: "snapshot path is a folder") }
        guard let attributes = try? fileManager.attributesOfItem(atPath: file.path), let size = attributes[.size] as? NSNumber else {
            return .nothing(reason: "snapshot file unreadable")
        }
        guard size.intValue > 0 else { return .nothing(reason: "snapshot file empty") }
        guard size.intValue <= maxBytes else { return .nothing(reason: "snapshot file too large") }
        guard let data = try? Data(contentsOf: file) else { return .nothing(reason: "snapshot file unreadable") }
        guard let snapshot = try? JSONDecoder().decode(TopShelfSnapshot.self, from: data) else { return .nothing(reason: "snapshot file damaged") }
        guard snapshot.version == TopShelfSnapshot.currentVersion else { return .nothing(reason: "snapshot version \(snapshot.version) not understood") }
        var ready: [ReadyItem] = []
        for item in snapshot.items.prefix(maxItems) {
            // The image name must be a plain file name inside the folder (no path tricks).
            guard !item.imageFile.isEmpty, !item.imageFile.contains("/"), !item.imageFile.contains(".."), !item.title.isEmpty else { continue }
            let image = directory.appendingPathComponent(item.imageFile)
            var imageIsDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: image.path, isDirectory: &imageIsDirectory), !imageIsDirectory.boolValue,
                  let attrs = try? fileManager.attributesOfItem(atPath: image.path), let n = attrs[.size] as? NSNumber, n.intValue > 0 else { continue }
            ready.append(ReadyItem(item: item, imageURL: image))
        }
        return ready.isEmpty ? .nothing(reason: "no item with artwork") : .items(ready)
    }
}
