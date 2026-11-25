import Foundation

/// R471 (24): a video file that is a trailer or bonus content for a title, not a title of its own. The common naming of
/// media servers: a tag at the end of the file's name ("Hexfall (1995)-trailer.mkv"), or a folder of extras next to the
/// title's file ("Hexfall (1995)/Trailers/Teaser.mkv"). Such a file gets no item of its own; the title's page lists it on
/// its Trailers or Bonus Content shelf. PROVISIONAL (OPEN_QUESTIONS R471 (24)).
public enum ExtraVideo {
    public enum Role: Equatable, Sendable { case trailer, bonus }

    /// The name tags, lower case, each after a hyphen at the very end of the name (before the extension).
    static let trailerTags = ["-trailer", "-teaser"]
    static let bonusTags = ["-featurette", "-behindthescenes", "-deleted", "-deletedscene", "-interview", "-scene", "-short", "-clip", "-extra"]
    /// The extras folders, lower case. "Other", "Shorts" and "Scenes" are left out: they are common names for folders of
    /// real titles too (OPEN_QUESTIONS R471 (24), alternatives).
    static let trailerFolders: Set<String> = ["trailers"]
    static let bonusFolders: Set<String> = ["featurettes", "extras", "behind the scenes", "deleted scenes", "interviews"]
    public static var folderNames: Set<String> { trailerFolders.union(bonusFolders) }

    /// The role of a video file, or nil for a title of its own. `parentPath` is the folder that holds the file.
    public static func role(name: String, parentPath: String) -> Role? {
        let stem = LibraryPath.stem(name).lowercased()
        if trailerTags.contains(where: { stem.hasSuffix($0) && stem.count > $0.count }) { return .trailer }
        if bonusTags.contains(where: { stem.hasSuffix($0) && stem.count > $0.count }) { return .bonus }
        return folderRole(parentPath)
    }

    /// The role every video in this folder has by the folder's name alone.
    public static func folderRole(_ folderPath: String) -> Role? {
        let folder = (folderPath.split(separator: "/").last.map(String.init) ?? "").lowercased()
        if trailerFolders.contains(folder) { return .trailer }
        if bonusFolders.contains(folder) { return .bonus }
        return nil
    }
}
