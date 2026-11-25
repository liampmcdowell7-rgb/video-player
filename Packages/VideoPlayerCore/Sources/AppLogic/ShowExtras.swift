import Foundation
import LibraryIndex
import MetadataLocal

/// R471 (39), PROVISIONAL: a show's own Trailers and Bonus Content (frames show t06s and t16s: both shelves under the
/// episodes). Found from where the show's episodes are kept: the show's folder (the one above a season folder, or the
/// episodes' own folder when they sit loose) and each season folder, each with its tagged extras and its extras
/// subfolders (`SQLiteLibraryStore.extraVideos`). An extra named after one episode stays on that episode's page only.
public enum ShowExtras {
    /// One extra of the show: nil season for the whole show, else the season whose folder holds it.
    public struct Found: Equatable, Sendable {
        public var row: ExtraRow
        public var season: Int?
        public var file: StoredFile
    }

    /// A folder to read: the show's own (season nil) or one season's.
    struct Place: Hashable {
        var sourceID: String
        var folder: String
        var season: Int?
    }

    /// The show's folder and its season folders, from the folders that hold its episodes' files.
    static func places(episodeFiles: [(season: Int?, file: StoredFile)]) -> [Place] {
        var out: [Place] = []
        for (season, file) in episodeFiles {
            let folder = file.parentPath
            let last = String(folder.split(separator: "/").last ?? "")
            let show: String
            if SidecarImageFinder.seasonNumber(ofFolder: last) != nil {
                show = parent(of: folder)
                let place = Place(sourceID: file.sourceID, folder: folder, season: season ?? SidecarImageFinder.seasonNumber(ofFolder: last))
                if !out.contains(place) { out.append(place) }
            } else {
                show = folder
            }
            let showPlace = Place(sourceID: file.sourceID, folder: show, season: nil)
            if !out.contains(showPlace) { out.append(showPlace) }
        }
        // The show's folder first, then the seasons in order.
        return out.filter { $0.season == nil } + out.filter { $0.season != nil }.sorted { ($0.season ?? 0) < ($1.season ?? 0) }
    }

    /// Every extra of the show, once each; those named after an episode are left to the episode's page.
    public static func load(seriesID: Int64, store: any LibraryStore) async throws -> [Found] {
        var episodeFiles: [(season: Int?, file: StoredFile)] = []
        for episode in try await store.episodes(ofSeries: seriesID) {
            for file in try await store.versions(of: episode.id) { episodeFiles.append((episode.season, file)) }
        }
        let stems = Set(episodeFiles.map { stem($0.file.name) }.filter { !$0.isEmpty })
        var seen = Set<Int64>()
        var out: [Found] = []
        for place in places(episodeFiles: episodeFiles) {
            for file in try await store.extraVideos(sourceID: place.sourceID, folder: place.folder) where !seen.contains(file.id) {
                guard !stems.contains(where: { file.name.hasPrefix($0) }) else { continue }
                seen.insert(file.id)
                let role = ExtraVideo.role(name: file.name, parentPath: file.parentPath)
                let row = ExtraRow(id: file.id, name: file.name, kindText: "Video", sizeText: file.size.map(DisplayText.fileSize),
                                   isVideo: true, isTrailer: role == .trailer)
                out.append(Found(row: row, season: place.season, file: file))
            }
        }
        return out
    }

    /// The rows of the page for the season on screen: the whole show's first, then that season's own.
    public static func rows(_ found: [Found], season: Int?) -> [ExtraRow] {
        found.filter { $0.season == nil }.map(\.row) + found.filter { $0.season != nil && $0.season == season }.map(\.row)
    }

    /// The extra `extraID` of the show, found again before it plays; nil when the show has no such extra now.
    public static func find(seriesID: Int64, extraID: Int64, store: any LibraryStore) async throws -> StoredFile? {
        try await load(seriesID: seriesID, store: store).first { $0.file.id == extraID }?.file
    }

    static func parent(of path: String) -> String {
        let parts = path.split(separator: "/").dropLast()
        return parts.isEmpty ? "/" : "/" + parts.joined(separator: "/")
    }

    static func stem(_ name: String) -> String { (name as NSString).deletingPathExtension }
}
