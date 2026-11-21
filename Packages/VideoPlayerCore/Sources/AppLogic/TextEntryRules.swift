import Foundation
import VideoPlayerCore
import UserData

// R333 (PROVISIONAL): the two last screens with text fields drawn in a row, Settings > Online Lookup's key (36) and the Move
// cover (66), use the source forms' pattern (R320, R321): a tvOS Settings value row, Select opens an entry page headed by
// the field's name with the right keyboard. Plain data, so the Linux tests prove it; the SwiftUI screens only apply it.
public enum TextEntryRules {
    /// What a value row shows (R320): nothing when empty, eight dots for a secret (never the key or its length), the value
    /// otherwise.
    public static func rowValue(_ value: String, isSecret: Bool) -> String {
        if value.isEmpty { return "" }
        return isSecret ? String(repeating: "\u{2022}", count: 8) : value
    }

    /// What VoiceOver says as the row's value: a secret is "Entered", never read out.
    public static func spokenValue(_ value: String, isSecret: Bool) -> String {
        if isSecret { return value.isEmpty ? "" : "Entered" }
        return value
    }

    /// R352 (compile run of 21 Nov 2026, R262): an entry page's description with its example, when the field has one:
    /// "Type the name on the keyboard. For example, Living Room." The example is no longer the text field's prompt, which
    /// tvOS 27 drew as the KEYBOARD screen's heading (11-form-webdav-keyboard-name showed "Living Room" where the field's
    /// name belongs).
    public static func description(_ summary: String, example: String?) -> String {
        guard let example = example?.trimmingCharacters(in: .whitespaces), !example.isEmpty else { return summary }
        return summary + " For example, " + example + "."
    }

    /// The one sentence under an entry page's heading ("Type the title on the keyboard.").
    public static func summary(_ title: String) -> String {
        "Type the \(title.lowercased()) on the keyboard."
    }

    // MARK: Settings > Online Lookup, the key (36)

    /// The key: a secret, typed as is (no capitalisation, no autocorrection), standard keyboard. No password content type:
    /// the system should not offer saved passwords for an API key.
    public static let keyEntry = SourceFieldEntry(keyboard: .standard, content: .none, capitalizesWords: false,
                                                  autocorrects: false, isSecret: true)

    /// The key's entry page sentence ("Type the TMDB key on the keyboard."). The key itself is never shown on the row.
    public static func keySummary(_ service: String) -> String {
        "Type the \(service) key on the keyboard."
    }

    // MARK: The Move cover (66)

    /// One field of the Move cover, in screen order.
    public enum MoveField: String, CaseIterable, Sendable {
        case title, year, season, episode, episodeEnd
    }

    /// The fields the Move cover shows for a target kind: a movie has no season or episode.
    public static func moveFields(_ kind: UDSortOverrideValue.Kind) -> [MoveField] {
        kind == .episode ? MoveField.allCases : [.title, .year]
    }

    /// The row title and entry page heading of a field. No "(Optional)" in the name: the footer says it once (R322).
    public static func moveTitle(_ field: MoveField, kind: UDSortOverrideValue.Kind) -> String {
        switch field {
        case .title: return kind == .movie ? "Title" : "Show"
        case .year: return "Year"
        case .season: return "Season"
        case .episode: return "Episode"
        case .episodeEnd: return "Last Episode"
        }
    }

    /// The keyboard of a field (R323 rules): the title capitalised as words, every number on the number pad.
    public static func moveEntry(_ field: MoveField) -> SourceFieldEntry {
        switch field {
        case .title:
            return SourceFieldEntry(keyboard: .standard, content: .none, capitalizesWords: true, autocorrects: false, isSecret: false)
        case .year, .season, .episode, .episodeEnd:
            return SourceFieldEntry(keyboard: .numberPad, content: .none, capitalizesWords: false, autocorrects: false, isSecret: false)
        }
    }

    /// The footer line that names the optional fields once (R322).
    public static func moveOptionalLine(_ kind: UDSortOverrideValue.Kind) -> String {
        kind == .episode ? "Optional: Year and Last Episode." : "Optional: Year."
    }
}
