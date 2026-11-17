import Foundation

public enum FileKind: String, Sendable, Equatable {
    case directory, video, subtitle, image, nfo, other
}

public enum FileClassifier {
    public static let videoExtensions: Set<String> = [
        "mkv", "mp4", "m4v", "mov", "ts", "m2ts", "mts", "avi", "wmv", "flv", "webm", "mpg", "mpeg", "vob", "ogv"
    ]
    public static let subtitleExtensions: Set<String> = ["srt", "ass", "ssa", "vtt", "sub", "idx", "sup"]
    public static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "tbn"]

    public static func fileExtension(of name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return String(name[name.index(after: dot)...]).lowercased()
    }

    public static func kind(forName name: String, isDirectory: Bool) -> FileKind {
        if isDirectory { return .directory }
        let ext = fileExtension(of: name)
        if videoExtensions.contains(ext) { return .video }
        if subtitleExtensions.contains(ext) { return .subtitle }
        if imageExtensions.contains(ext) { return .image }
        if ext == "nfo" { return .nfo }
        return .other
    }
}

public struct FileItem: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public var path: String
    public var name: String
    public var kind: FileKind
    public var size: Int64?
    public var modified: Date?
    public var etag: String?

    public init(path: String, name: String, kind: FileKind, size: Int64? = nil, modified: Date? = nil, etag: String? = nil) {
        self.path = path
        self.name = name
        self.kind = kind
        self.size = size
        self.modified = modified
        self.etag = etag
    }

    public init(entry: SourceEntry) {
        self.init(
            path: entry.path,
            name: entry.name,
            kind: FileClassifier.kind(forName: entry.name, isDirectory: entry.isDirectory),
            size: entry.size,
            modified: entry.modified,
            etag: entry.etag
        )
    }

    public var isDirectory: Bool { kind == .directory }
    public var isVideo: Bool { kind == .video }

    /// Path of the folder that contains this item ("/" for the root).
    public var parentPath: String {
        let parts = path.split(separator: "/")
        return "/" + parts.dropLast().joined(separator: "/")
    }

    /// Names of the folders above this item, nearest first (input for `FilenameParser`).
    public var ancestorFolderNames: [String] {
        Array(path.split(separator: "/").dropLast().reversed()).map(String.init)
    }
}

public enum FileSortKey: String, Sendable, CaseIterable {
    case name, dateModified, size, kind
}

public struct FileSort: Sendable, Equatable {
    public var key: FileSortKey
    public var ascending: Bool

    public init(key: FileSortKey = .name, ascending: Bool = true) {
        self.key = key
        self.ascending = ascending
    }

    /// Folders always come first. Names compare naturally ("Episode 2" before "Episode 10").
    public func apply(to items: [FileItem]) -> [FileItem] {
        items.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            let order = compare(a, b)
            if order == .orderedSame { return naturalCompare(a.name, b.name) == .orderedAscending }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }

    private func compare(_ a: FileItem, _ b: FileItem) -> ComparisonResult {
        switch key {
        case .name:
            return naturalCompare(a.name, b.name)
        case .dateModified:
            return compareOptional(a.modified, b.modified)
        case .size:
            return compareOptional(a.size, b.size)
        case .kind:
            let c = a.kind.rawValue.compare(b.kind.rawValue)
            return c == .orderedSame ? naturalCompare(FileClassifier.fileExtension(of: a.name), FileClassifier.fileExtension(of: b.name)) : c
        }
    }

    private func naturalCompare(_ a: String, _ b: String) -> ComparisonResult {
        a.compare(b, options: [.caseInsensitive, .numeric, .diacriticInsensitive])
    }

    private func compareOptional<T: Comparable>(_ a: T?, _ b: T?) -> ComparisonResult {
        switch (a, b) {
        case let (x?, y?): return x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedAscending
        case (_, nil): return .orderedDescending
        }
    }
}

public enum FileSearch {
    /// Case- and diacritic-insensitive match on every whitespace-separated word of the query.
    public static func filter(_ items: [FileItem], query: String) -> [FileItem] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.isEmpty { return items }
        return items.filter { item in
            words.allSatisfy { item.name.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}
