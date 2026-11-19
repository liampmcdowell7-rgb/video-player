import Foundation
import VideoPlayerCore

/// The file tree we show for a media server. A media server has no folder listing of its own, so
/// the tree is built from each item's file path: `/<Library name>/<path inside the library>`.
/// Folders are made up from the paths. Titles from the server are never used (our metadata rules).
struct EMLibrary: Equatable {
    var name: String
    /// Folder paths of the library as server path components.
    var roots: [[String]]
}

struct EMTree: Sendable {
    struct Node: Sendable {
        var entry: SourceEntry
        var itemID: String?
        var mediaSourceID: String?
    }

    private(set) var nodes: [String: Node] = [
        "/": Node(entry: SourceEntry(path: "/", name: "", isDirectory: true))
    ]
    private var childPaths: [String: Set<String>] = [:]
    /// Items whose file is outside every library folder (not shown).
    private(set) var skippedItems = 0

    // MARK: Paths

    /// Leading "/", no trailing "/", no empty components (except the root, which is "/").
    static func normalize(_ path: String) -> String {
        "/" + path.split(separator: "/", omittingEmptySubsequences: true).joined(separator: "/")
    }

    /// Server paths may be POSIX or Windows (`C:\Media\Movies`). Both become component lists.
    static func components(of serverPath: String) -> [String] {
        serverPath.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    private static func dirname(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/"), slash != path.startIndex else { return "/" }
        return String(path[..<slash])
    }

    // MARK: Building

    static func make(libraries: [EMLibrary], items: [EMItem]) -> EMTree {
        var tree = EMTree()
        var usedNames: Set<String> = []
        var named: [(name: String, roots: [[String]])] = []
        for library in libraries {
            var name = library.name.replacingOccurrences(of: "/", with: "-")
            if name.isEmpty { name = "Library" }
            var unique = name, n = 2
            while usedNames.contains(unique.lowercased()) { unique = "\(name) (\(n))"; n += 1 }
            usedNames.insert(unique.lowercased())
            named.append((unique, library.roots))
            tree.addDirectory("/" + unique)
        }
        for item in items {
            var files: [(path: String, id: String?, size: Int64?, container: String?, etag: String?)] = []
            for source in item.mediaSources ?? [] {
                guard let path = source.path, !path.isEmpty else { continue }
                if let kind = source.protocolName, kind != "File" { continue }
                files.append((path, source.id, source.size, source.container, source.etag ?? item.etag))
            }
            if files.isEmpty, let path = item.path, !path.isEmpty {
                files.append((path, nil, nil, nil, item.etag))
            }
            for file in files {
                let parts = components(of: file.path)
                guard let (library, relative) = match(parts, in: named), !relative.isEmpty else {
                    tree.skippedItems += 1
                    continue
                }
                let full = "/" + ([library] + relative).joined(separator: "/")
                tree.addFile(
                    path: full, name: relative[relative.count - 1], itemID: item.id, mediaSourceID: file.id,
                    size: (file.size ?? 0) > 0 ? file.size : nil,   // 0 means "not measured yet" on some servers
                    contentType: file.container.flatMap(contentType(forContainer:)), token: file.etag,
                    serverType: serverItemType(item.type))
            }
        }
        return tree
    }

    /// Longest library folder that contains the file. Falls back to a case-insensitive match
    /// because a Windows server may report the same folder in different letter case.
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
        let parent = EMTree.dirname(path)
        if parent != "/" { addDirectory(parent) }
        let name = String(path.split(separator: "/").last ?? "")
        nodes[path] = Node(entry: SourceEntry(path: path, name: name, isDirectory: true))
        childPaths[parent, default: []].insert(path)
    }

    private mutating func addFile(
        path: String, name: String, itemID: String, mediaSourceID: String?,
        size: Int64?, contentType: String?, token: String?, serverType: ServerItemType? = nil
    ) {
        if nodes[path] != nil { return }   // two items claiming one path: the first one stays
        let parent = EMTree.dirname(path)
        addDirectory(parent)
        nodes[path] = Node(
            entry: SourceEntry(path: path, name: name, isDirectory: false, size: size, contentType: contentType, serverToken: token, serverItemType: serverType),
            itemID: itemID, mediaSourceID: mediaSourceID)
        childPaths[parent, default: []].insert(path)
    }

    // MARK: Reading

    func node(at path: String) -> Node? { nodes[EMTree.normalize(path)] }

    func children(of path: String) -> [SourceEntry] {
        (childPaths[EMTree.normalize(path)] ?? [])
            .compactMap { nodes[$0]?.entry }
            .sorted {
                let order = $0.name.localizedCaseInsensitiveCompare($1.name)
                return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
            }
    }

    var fileCount: Int { nodes.values.filter { !$0.entry.isDirectory }.count }

    /// The deepest folder that holds every path. Used when the server will not list its libraries.
    static func commonFolder(of paths: [String]) -> [String] {
        let lists = paths.map(components(of:)).map { Array($0.dropLast()) }
        guard var common = lists.first else { return [] }
        for list in lists.dropFirst() {
            var length = 0
            while length < min(common.count, list.count), common[length] == list[length] { length += 1 }
            common = Array(common[..<length])
        }
        return common
    }
}

func contentType(forContainer container: String) -> String? {
    switch container.lowercased().split(separator: ",").first.map(String.init) ?? "" {
    case "mkv", "matroska": return "video/x-matroska"
    case "mp4", "m4v", "mov": return "video/mp4"
    case "avi": return "video/x-msvideo"
    case "webm": return "video/webm"
    case "ts", "mpegts": return "video/mp2t"
    default: return nil
    }
}

/// The server's item type as a sorting hint (docs/SORTING.md): only "Movie" and "Episode" mean anything.
func serverItemType(_ type: String?) -> ServerItemType? {
    switch type {
    case "Movie": return .movie
    case "Episode": return .episode
    default: return nil
    }
}
