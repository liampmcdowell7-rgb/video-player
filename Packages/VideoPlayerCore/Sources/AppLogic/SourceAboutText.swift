import Foundation
import VideoPlayerCore

/// One titled part of a source type's About page (R329, PROVISIONAL).
public struct SourceAboutSection: Equatable, Sendable {
    public var header: String
    public var text: String

    public init(header: String, text: String) {
        self.header = header
        self.text = text
    }
}

// About Source Types as a hierarchy of lists (docs/SOURCE_SETUP_DESIGN.md, OPEN_QUESTIONS R329): one page per type instead
// of one long text about every type. Built from the catalog, so it always matches the forms; the same words as the one-page
// text it replaces (`SourceSetupText.learnMore`), split into sections.
public enum SourceAboutText {
    /// The title of a type's About page and of the row that opens it ("About WebDAV").
    public static func title(_ info: SourceKindInfo) -> String { "About " + info.title }

    /// The page's sections, under the summary that the page header shows. An available type: how it was tested, then what
    /// was not (when there is something). A type that is not available: why, and what to use instead.
    public static func sections(_ info: SourceKindInfo) -> [SourceAboutSection] {
        if let note = info.unavailableNote {
            return [SourceAboutSection(header: "Not Available Yet", text: reason(note))]
        }
        var parts: [SourceAboutSection] = [SourceAboutSection(header: "Tested", text: info.statusLine + ".")]
        if let caveat = info.caveat { parts.append(SourceAboutSection(header: "Not Tested", text: caveat)) }
        return parts
    }

    /// The catalog note without its machine prefix ("blocked: needs …" becomes "Needs …").
    static func reason(_ note: String) -> String {
        var text: String = note
        if text.hasPrefix("blocked: ") { text.removeFirst("blocked: ".count) }
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
