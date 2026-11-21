import Foundation
import VideoPlayerCore

// The source forms as tvOS Settings rows (docs/SOURCE_SETUP_DESIGN.md, OPEN_QUESTIONS R320 to R325, all PROVISIONAL):
// what a field row shows, what its entry page's keyboard is, what the footer says, and where the focus goes. Plain data, so
// the Linux tests prove it; the SwiftUI screens only apply it.

/// The keyboard of a field's entry page (R323). HIG Text fields: "show the appropriate keyboard type".
public enum SourceFieldKeyboard: Equatable, Sendable {
    case standard
    /// The URL keyboard (HIG Virtual keyboards: "URL").
    case url
    /// The number pad (HIG Virtual keyboards: "Number pad").
    case numberPad
}

/// The semantic content of a field, so the system can offer what it has (R323, R330).
public enum SourceFieldContent: Equatable, Sendable {
    case none
    case username
    case password
    case url
}

/// How a field's entry page asks for its value (R321, R323).
public struct SourceFieldEntry: Equatable, Sendable {
    public var keyboard: SourceFieldKeyboard
    public var content: SourceFieldContent
    /// True only for Name ("Living Room"): words capitalised. Everything else is typed as is.
    public var capitalizesWords: Bool
    /// Autocorrection is off for every field: names, addresses, user names and folders are not dictionary words.
    public var autocorrects: Bool
    public var isSecret: Bool

    public init(keyboard: SourceFieldKeyboard, content: SourceFieldContent, capitalizesWords: Bool, autocorrects: Bool, isSecret: Bool) {
        self.keyboard = keyboard
        self.content = content
        self.capitalizesWords = capitalizesWords
        self.autocorrects = autocorrects
        self.isSecret = isSecret
    }

    public static func of(_ spec: SourceFieldSpec) -> SourceFieldEntry {
        switch spec.kind {
        case .name:
            return SourceFieldEntry(keyboard: .standard, content: .none, capitalizesWords: true, autocorrects: false, isSecret: false)
        case .address:
            return SourceFieldEntry(keyboard: .url, content: .url, capitalizesWords: false, autocorrects: false, isSecret: false)
        case .host:
            return SourceFieldEntry(keyboard: .url, content: .none, capitalizesWords: false, autocorrects: false, isSecret: false)
        case .port:
            return SourceFieldEntry(keyboard: .numberPad, content: .none, capitalizesWords: false, autocorrects: false, isSecret: false)
        case .share, .folder, .security:
            return SourceFieldEntry(keyboard: .standard, content: .none, capitalizesWords: false, autocorrects: false, isSecret: false)
        case .username:
            return SourceFieldEntry(keyboard: .standard, content: .username, capitalizesWords: false, autocorrects: false, isSecret: false)
        case .password:
            return SourceFieldEntry(keyboard: .standard, content: .password, capitalizesWords: false, autocorrects: false, isSecret: true)
        }
    }
}

/// Where a source form puts the focus (R325).
public enum SourceFormFocus: Hashable, Sendable {
    case field(SourceFieldKind)
    case connect
}

public enum SourceFormText {
    /// The words the catalog uses as prompts that are NOT examples (R322): they say whether a field must be filled, which
    /// the footer says now. Never shown as a prompt or a value.
    public static let notExamples: Set<String> = ["Optional", "Required"]

    /// The example shown as the entry page field's prompt ("https://nas.local"); nil for a picker, or when the catalog's
    /// prompt only says "Optional" or "Required".
    public static func example(_ spec: SourceFieldSpec) -> String? {
        guard spec.choices.isEmpty else { return nil }
        let prompt: String = spec.prompt.trimmingCharacters(in: .whitespaces)
        guard !prompt.isEmpty, !notExamples.contains(prompt) else { return nil }
        return prompt
    }

    /// What a field's row shows in its value position (R320): nothing when empty (never a placeholder, R322), dots for a
    /// password (never its length: always eight), the value otherwise. A picker shows its answer's title.
    public static func rowValue(_ spec: SourceFieldSpec, _ value: String) -> String {
        if !spec.choices.isEmpty {
            let current: String = value.isEmpty ? spec.prompt : value
            return spec.choices.first { $0.value == current }?.title ?? ""
        }
        if value.isEmpty { return "" }
        if spec.isSecret { return String(repeating: "\u{2022}", count: 8) }
        return value
    }

    /// What VoiceOver says as the row's value: a password is "Entered", never read out.
    public static func spokenValue(_ spec: SourceFieldSpec, _ value: String) -> String {
        if spec.isSecret { return value.isEmpty ? "" : "Entered" }
        return rowValue(spec, value)
    }

    /// The footer line that names the optional text fields once (R322): "Optional: Port, User Name and Password." Nil when
    /// every text field must be filled. Pickers always have an answer, so they are not listed.
    public static func optionalLine(_ fields: [SourceFieldSpec]) -> String? {
        let names: [String] = fields.filter { !$0.required && $0.choices.isEmpty }.map(\.title)
        guard !names.isEmpty else { return nil }
        return "Optional: " + joined(names) + "."
    }

    /// "A", "A and B", "A, B and C".
    static func joined(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }

    /// True when every required field of the draft's type has a value (spaces alone do not count).
    public static func requiredFilled(_ draft: SourceDraft) -> Bool {
        SourceCatalog.info(for: draft.kind).fields.allSatisfy { (spec: SourceFieldSpec) -> Bool in
            !spec.required || !draft[spec.kind].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Where the form's focus starts (R325): Connect when every required field is filled (a found server), otherwise the
    /// first empty required field, otherwise the first field.
    public static func firstFocus(_ draft: SourceDraft) -> SourceFormFocus {
        let fields: [SourceFieldSpec] = SourceCatalog.info(for: draft.kind).fields
        if requiredFilled(draft) && fields.contains(where: \.required) { return .connect }
        if let empty = fields.first(where: { $0.required && draft[$0.kind].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return .field(empty.kind)
        }
        if let first = fields.first { return .field(first.kind) }
        return .connect
    }

    /// Where the focus goes after Done on a field's entry page (R325): Connect when that Done filled the last empty
    /// required field; nil (the system keeps the focus on the row) otherwise.
    public static func focusAfterDone(before: SourceDraft, after: SourceDraft) -> SourceFormFocus? {
        guard !requiredFilled(before), requiredFilled(after) else { return nil }
        return .connect
    }

    /// The one sentence under the heading of a field's entry page. It does not say "Optional" (R322: only the form's footer
    /// does).
    public static func entrySummary(_ spec: SourceFieldSpec) -> String {
        "Type the \(spec.title.lowercased()) on the keyboard."
    }
}
