import Foundation
import VideoPlayerCore
import LibraryIndex
import MetadataLocal

/// R471 item 4 (PROVISIONAL): the sections under the hero of the product pages, built only from data we hold.
/// Layout from the reference frames (episode t02s, movie t04s and t06s); wording our own.

/// "How to Watch": one card per page, from the item's own source. A generic symbol for the KIND of source (never a
/// service's logo), the source's name, and the action with what is left ("Resume", "18m left") or the length ("Play",
/// "43m"); a show's card says which seasons the library holds.
public struct HowToWatch: Equatable, Sendable {
    public var symbol: String
    public var spokenKind: String
    public var sourceName: String
    public var action: String
    public var detail: String?

    public init(symbol: String, spokenKind: String, sourceName: String, action: String, detail: String?) {
        self.symbol = symbol; self.spokenKind = spokenKind; self.sourceName = sourceName; self.action = action; self.detail = detail
    }

    public static let heading = "How to Watch"

    /// Nil when the item has no file on any source (nothing to watch it from).
    public static func make(sourceKind: SourceKind?, sourceName: String?, progress: Double?, durationSeconds: Double?,
                            seasonsLine: String? = nil) -> HowToWatch? {
        let name = sourceName?.trimmingCharacters(in: .whitespaces)
        guard sourceKind != nil || !(name ?? "").isEmpty else { return nil }
        let symbol = sourceKind.map(SourceGlyph.symbol) ?? "play.rectangle"
        let spoken = sourceKind.map(SourceGlyph.spoken) ?? "Library"
        let shownName = (name?.isEmpty == false ? name : nil) ?? spoken
        let capsule = PlayCapsule.make(progress: progress, durationSeconds: durationSeconds)
        let resuming = capsule.progress != nil
        var detail: String?
        if let seasonsLine { detail = seasonsLine }
        else if resuming, let left = capsule.timeLeft { detail = left + " left" }
        else if let d = durationSeconds, d > 0 { detail = ShortDuration.text(d) }
        return HowToWatch(symbol: symbol, spokenKind: spoken, sourceName: shownName, action: resuming ? "Resume" : "Play", detail: detail)
    }

    /// "Season 1", "Seasons 1–4", "Seasons 1, 3, 5", with "Specials" for season 0; nil for none.
    public static func seasonsLine(_ numbers: [Int]) -> String? {
        let sorted = Array(Set(numbers)).sorted()
        let specials = sorted.contains(0)
        let real = sorted.filter { $0 > 0 }
        var parts: [String] = []
        if real.count == 1 {
            parts.append("Season \(real[0])")
        } else if real.count > 1 {
            let contiguous = real.last! - real.first! == real.count - 1
            parts.append(contiguous ? "Seasons \(real.first!)–\(real.last!)" : "Seasons " + real.map(String.init).joined(separator: ", "))
        }
        if specials { parts.append("Specials") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// One line of a column under the hero: a label, the value as shown, and the whole list when the value is shortened
/// ("More" opens it). Never cut mid-word: a long list shows its first `visibleLimit` entries, then More.
public struct InfoEntry: Equatable, Sendable, Identifiable {
    public var id: String { label }
    public var label: String
    public var value: String
    public var full: [String]?

    public init(label: String, value: String, full: [String]? = nil) {
        self.label = label; self.value = value; self.full = full
    }
}

public enum ProductInfo {
    public static let informationHeading = "Information"
    public static let languagesHeading = "Languages"
    public static let accessibilityHeading = "Accessibility"
    /// How many languages a value lists before More.
    public static let visibleLimit = 3

    /// Information: Released, Run Time, Rated, Content Advisories, Region of Origin; each only when we hold it.
    public static func information(released: PartialDate?, year: Int?, durationSeconds: Double?, rating: String?,
                                   advisories: [String], regions: [String], locale: Locale = .current) -> [InfoEntry] {
        var out: [InfoEntry] = []
        if let released { out.append(InfoEntry(label: "Released", value: InfoDateText.text(released, locale: locale))) }
        else if let year, year > 0 { out.append(InfoEntry(label: "Released", value: String(year))) }
        if let d = durationSeconds, d > 0 { out.append(InfoEntry(label: "Run Time", value: DisplayText.runtime(d))) }
        if let r = rating?.trimmingCharacters(in: .whitespaces), !r.isEmpty { out.append(InfoEntry(label: "Rated", value: r)) }
        let advice = unique(advisories)
        if !advice.isEmpty { out.append(listed("Content Advisories", advice)) }
        let places = unique(regions)
        if !places.isEmpty { out.append(listed("Region of Origin", places)) }
        return out
    }

    /// Languages: Original Audio (the catalogue's original language when known, else the file's default audio track),
    /// Audio and Subtitles (each language once, in the file's order). Tracks of no stated language are left out.
    public static func languages(tracks: FileTrackDetails?, originalLanguage: String? = nil) -> [InfoEntry] {
        guard let tracks else { return [] }
        var out: [InfoEntry] = []
        let speech = tracks.audio.filter { !$0.isCommentary }
        let original = originalLanguage.flatMap(name) ?? (speech.first(where: \.isDefault) ?? speech.first)?.language.flatMap(name)
        if let original { out.append(InfoEntry(label: "Original Audio", value: original)) }
        let audio = unique(speech.compactMap { $0.language.flatMap(name) })
        if !audio.isEmpty { out.append(listed("Audio", audio)) }
        let subtitles = unique(tracks.subtitles.compactMap { $0.language.flatMap(name) })
        if !subtitles.isEmpty { out.append(listed("Subtitles", subtitles)) }
        return out
    }

    /// Accessibility: each feature the file carries, with our own one-line explanation.
    public static func accessibility(_ features: [AccessFeature]) -> [InfoEntry] {
        features.map { InfoEntry(label: $0.spoken, value: $0.explanation) }
    }

    /// A language's English name, nil for "undetermined" and "no linguistic content".
    static func name(_ code: String) -> String? {
        let key = code.lowercased().split(separator: "-").first.map(String.init) ?? ""
        if key.isEmpty || ["und", "zxx", "mis"].contains(key) { return nil }
        return MatroskaTrack.languageName(for: code)
    }

    static func listed(_ label: String, _ values: [String]) -> InfoEntry {
        if values.count <= visibleLimit { return InfoEntry(label: label, value: values.joined(separator: ", ")) }
        return InfoEntry(label: label, value: values.prefix(visibleLimit).joined(separator: ", "), full: values)
    }

    static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}
