import Foundation
import LibraryIndex

/// R471 (24): the file behind a card on a title's Trailers or Bonus Content shelf. It is looked up again among the title's
/// own extras (the same list the page shows), so a card can play only a video that belongs to that title. PROVISIONAL.
public enum ExtraFiles {
    /// The extra video `extraID` of the item, or nil when the item has no such extra now (removed, rescanned as a title).
    public static func find(itemID: Int64, extraID: Int64, store: any LibraryStore) async throws -> StoredFile? {
        guard let item = try await store.item(id: itemID) else { return nil }
        var fileID = item.preferredFileID
        if fileID == nil { fileID = try await store.versions(of: itemID).first?.id }
        guard let fileID else { return nil }
        return try await store.sidecars(for: fileID).first { $0.id == extraID && $0.kind == .video }
    }
}
