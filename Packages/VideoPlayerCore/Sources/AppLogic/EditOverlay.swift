import Foundation
import MetadataOnline
import UserData

/// R449: the user layer read on top of every source. `MetadataMerger.merge(user:)` puts it first (user > local sidecar >
/// online > embedded for each field), so a rescan, Fix Match, an online refresh or a Plex re-index only change the layers
/// below it and never an edited field. A reset field is simply absent here, so the next layer shows again.
public enum EditOverlay {
    /// The `MetadataFields` of the edits. Fields that `MetadataFields` has no place for (sort title, studio, crew,
    /// collections, labels, season and episode numbers and titles, air date) stay in `UDEditValues` for the screens.
    public static func fields(from edits: UDEditValues, userArtworkPrefix: String = "useredits") -> MetadataFields {
        var f = MetadataFields()
        f.title = edits[.title]?.text
        f.originalTitle = edits[.originalTitle]?.text
        f.tagline = edits[.tagline]?.text
        f.overview = edits[.overview]?.text
        if let d = edits[.releaseDate]?.text, let date = CalendarDate(d) { f.releaseDate = date }
        else if let y = edits[.year]?.number, (1800...2200).contains(Int(y)) { f.releaseDate = CalendarDate(year: Int(y), month: 1, day: 1) }
        f.runtimeMinutes = edits[.runtime]?.number.map { Int($0) }
        f.genres = edits[.genres]?.list ?? []
        f.certification = edits[.certification]?.text
        f.poster = ref(edits[.poster], prefix: userArtworkPrefix)
        f.backdrop = ref(edits[.backdrop], prefix: userArtworkPrefix)
        f.logo = ref(edits[.logo], prefix: userArtworkPrefix)
        f.cast = (edits[.cast]?.people ?? []).enumerated().map { Person(id: 0, name: $1.name, character: $1.role.isEmpty ? nil : $1.role, order: $0) }
        return f
    }

    /// Online choices stay supplier paths; a file of the user-artwork folder is a local reference by its content name.
    /// An address that has not been downloaded yet is not a picture yet (nil: the layer below shows).
    static func ref(_ value: UDEditValue?, prefix: String) -> ArtworkRef? {
        switch value?.artwork {
        case let .online(p)?: return .tmdb(p)
        case let .file(n)?: return .local(prefix + "/" + n)
        default: return nil
        }
    }

    /// Whether a field shows an edit (for the "Edited" marker beside it).
    public static func isEdited(_ field: UDEditField, in edits: UDEditValues) -> Bool { edits.isEdited(field) }
}
