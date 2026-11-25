import Foundation
import AppLogic
import LibraryIndex

/// R471 (24): what a Trailers or Bonus Content card plays: its file's link (or the converting player's loopback address).
/// No watch state, no progress, no Up Next and no watch sync: an extra is not a title of its own. PROVISIONAL.
struct ResolvedExtra: @unchecked Sendable {
    var url: URL
    var headers: [String: String]
    var title: String
    /// Set when the file plays through the converting player; the screen stops it when it closes.
    var remux: RemuxPlayback?
}

extension AppServices {
    /// The extra `extraID` of the title `itemID`, opened the way a title's file is (`resolvePlayback`): MKV and the other
    /// containers the converting player opens go through it, the rest plays from the source's own link. The file must be
    /// one of that title's extras now (`ExtraFiles.find`).
    /// R471 (39): with `seriesID`, a show's own extra (its folder or a season folder, `ShowExtras.find`).
    func resolveExtra(itemID: Int64, extraID: Int64, seriesID: Int64? = nil) async throws -> ResolvedExtra {
        let found: StoredFile?
        if let seriesID {
            found = try await ShowExtras.find(seriesID: seriesID, extraID: extraID, store: store)
        } else {
            found = try await ExtraFiles.find(itemID: itemID, extraID: extraID, store: store)
        }
        guard let file = found else { throw PlaybackError.noFile }
        let title = ExtraShelves.displayName(file.name)
        let route = PlaybackRoute.route(fileName: file.name)
        if case .unsupported(let failure) = route { throw failure }
        if route == .remux {
            let opened = try await RemuxPlayback.open(reader: try await sourceFactory.byteReader(for: file))
            return ResolvedExtra(url: opened.url, headers: [:], title: title, remux: opened)
        }
        guard let definition = definitions.first(where: { $0.id == file.sourceID }), let source = makeSource(definition) else {
            throw PlaybackError.sourceUnavailable
        }
        let access = try await source.playbackAccess(for: file.path)
        guard case .url(let url, let headers) = access else { throw PlaybackError.notReadable }
        return ResolvedExtra(url: url, headers: headers, title: title, remux: nil)
    }
}
