import Foundation
import VideoPlayerCore

/// The file tree the app shows for a Plex server (docs/PLEX_SOURCE.md section 4; OPEN_QUESTIONS R304).
///
/// Like Jellyfin and Emby, a Plex server has no folder listing for clients, so the tree is built from each Part's `file`
/// (the path on the server, POSIX or Windows): `/<Section title>/<path inside the section's folder>`. The section folders
/// come from each section's `Location` list (field name UNVERIFIED). Titles from the server never name the files, so the
/// app's own scanner and matcher see the same names as on a network share (WebDAV and Plex copies of one file get one item
/// key). A Part whose file is outside every section folder is skipped and counted.
struct PlexLibrary: Equatable {
    var title: String
    /// Folder paths of the section as server path components.
    var roots: [[String]]
}

struct PlexTree: Sendable {
    struct Node: Sendable {
        var entry: SourceEntry
        /// The item's rating key and its Part (for reading and playing), nil for folders.
        var ratingKey: String?
        var part: PlexPart?
        var media: PlexMedia?
        /// Watch state as the server had it when the tree was read (stage 6, R306): seeded once, never written back.
        var viewOffsetSeconds: Double?
        var viewCount: Int?
        var lastViewedAt: Date?
        var metadata: PlexMetadata?
    }

    private(set) var nodes: [String: Node] = ["/": Node(entry: SourceEntry(path: "/", name: "", isDirectory: true))]
    private var childPaths: [String: Set<String>] = [:]
    private(set) var skippedParts = 0

    static func normalize(_ path: String) -> String {
        "/" + path.split(separator: "/", omittingEmptySubsequences: true).joined(separator: "/")
    }

    /// Server paths may be POSIX or Windows (`D:\Media\Movies`). Both become component lists.
    static func components(of serverPath: String) -> [String] {
        serverPath.replacingOccurrences(of: "\\", with: "/").split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    private static func dirname(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/"), slash != path.startIndex else { return "/" }
        return String(path[..<slash])
    }

    static func make(libraries: [PlexLibrary], items: [PlexMetadata]) -> PlexTree {
        var tree = PlexTree()
        var used: Set<String> = []
        var named: [(name: String, roots: [[String]])] = []
        for library in libraries {
            var name = library.title.replacingOccurrences(of: "/", with: "-")
            if name.isEmpty { name = "Library" }
            var unique = name, n = 2
            while used.contains(unique.lowercased()) { unique = "\(name) (\(n))"; n += 1 }
            used.insert(unique.lowercased())
            named.append((unique, library.roots))
            tree.addDirectory("/" + unique)
        }
        for item in items {
            for media in item.media {
                for part in media.parts {
                    guard let file = part.file, !file.isEmpty, part.key != nil else { continue }
                    let parts = components(of: file)
                    guard let (library, relative) = match(parts, in: named), !relative.isEmpty else {
                        tree.skippedParts += 1
                        continue
                    }
                    let path = "/" + ([library] + relative).joined(separator: "/")
                    let container = part.container ?? media.container
                    let entry = SourceEntry(path: path, name: relative[relative.count - 1], isDirectory: false,
                                            size: (part.size ?? 0) > 0 ? part.size : nil,
                                            contentType: container.flatMap(plexContentType(forContainer:)),
                                            // Changes when the server's Part changes (a replaced file gets a new Part id).
                                            serverToken: part.id.map { "part-\($0)" },
                                            serverItemType: plexItemType(item.type))
                    tree.addFile(entry, node: Node(entry: entry, ratingKey: item.ratingKey, part: part, media: media,
                                                   viewOffsetSeconds: item.viewOffset.map { Double($0) / 1000 },
                                                   viewCount: item.viewCount, lastViewedAt: item.lastViewedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                                                   metadata: item))
                }
            }
        }
        return tree
    }

    /// Longest section folder that contains the file; case-insensitive as a fallback (a Windows server may report the same
    /// folder in different letter case).
    private static func match(_ parts: [String], in libraries: [(name: String, roots: [[String]])]) -> (String, [String])? {
        for ignoreCase in [false, true] {
            var best: (name: String, depth: Int)?
            for library in libraries {
                for root in library.roots where parts.count > root.count {
                    let same = zip(root, parts).allSatisfy { ignoreCase ? $0.lowercased() == $1.lowercased() : $0 == $1 }
                    if same, root.count > (best?.depth ?? -1) { best = (library.name, root.count) }
                }
            }
            if let best { return (best.name, Array(parts[best.depth...])) }
        }
        return nil
    }

    private mutating func addDirectory(_ path: String) {
        if nodes[path] != nil { return }
        let parent = PlexTree.dirname(path)
        if parent != "/" { addDirectory(parent) }
        let name = String(path.split(separator: "/").last ?? "")
        nodes[path] = Node(entry: SourceEntry(path: path, name: name, isDirectory: true))
        childPaths[parent, default: []].insert(path)
    }

    private mutating func addFile(_ entry: SourceEntry, node: Node) {
        if nodes[entry.path] != nil { return }   // two Parts claiming one path: the first one stays
        let parent = PlexTree.dirname(entry.path)
        addDirectory(parent)
        nodes[entry.path] = node
        childPaths[parent, default: []].insert(entry.path)
    }

    func node(at path: String) -> Node? { nodes[PlexTree.normalize(path)] }

    func children(of path: String) -> [SourceEntry] {
        (childPaths[PlexTree.normalize(path)] ?? [])
            .compactMap { nodes[$0]?.entry }
            .sorted {
                let order = $0.name.localizedCaseInsensitiveCompare($1.name)
                return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
            }
    }

    var files: [Node] { nodes.values.filter { !$0.entry.isDirectory } }
}

func plexContentType(forContainer container: String) -> String? {
    switch container.lowercased().split(separator: ",").first.map(String.init) ?? "" {
    case "mkv", "matroska": return "video/x-matroska"
    case "mp4", "m4v": return "video/mp4"
    case "mov": return "video/quicktime"
    case "avi": return "video/x-msvideo"
    case "webm": return "video/webm"
    case "ts", "mpegts": return "video/mp2t"
    default: return nil
    }
}

/// Plex's item type as a sorting hint (docs/SORTING.md): type numbers read on the PMS reference are movie 1, show 2,
/// season 3, episode 4; the JSON `type` field carries the word ("movie", "episode").
func plexItemType(_ type: String?) -> ServerItemType? {
    switch type?.lowercased() {
    case "movie": return .movie
    case "episode": return .episode
    default: return nil
    }
}
