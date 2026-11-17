import Foundation
import RemuxEngine

// The ONE custom menu for picture subtitles (decision D1, PROVISIONAL).
//
// Text subtitles (SRT, ASS, WebVTT) are WebVTT renditions and live only in the system subtitle menu. Picture subtitles
// (PGS) cannot be renditions, so they get one menu of their own in the transport bar. The two sources are mutually
// exclusive: choosing a picture track turns the text track off, and choosing a text track turns the picture track off.
// This model holds that rule as plain state so it is tested on Linux; the app target draws the menu and carries out the
// effects.
//
// Alternative to D1 (not chosen): one merged menu that lists both kinds. That needs the system menu replaced, which the
// system player does not allow.

public struct PictureSubtitleChoice: Equatable, Identifiable, Sendable {
    /// The Matroska track number.
    public var id: Int
    public var title: String
    /// BCP 47 tag or empty.
    public var language: String
    public var isDefault: Bool
    public var isForced: Bool
    public var isHearingImpaired: Bool

    public init(id: Int, title: String, language: String = "", isDefault: Bool = false, isForced: Bool = false, isHearingImpaired: Bool = false) {
        self.id = id; self.title = title; self.language = language
        self.isDefault = isDefault; self.isForced = isForced; self.isHearingImpaired = isHearingImpaired
    }

    /// Second line of a menu row: "Forced", "For the deaf and hard of hearing", or nil.
    public var detail: String? {
        var parts: [String] = []
        if isForced { parts.append("Forced") }
        if isHearingImpaired { parts.append("For the deaf and hard of hearing") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

public struct PictureSubtitleMenuModel: Equatable, Sendable {
    public enum Effect: Equatable, Sendable {
        /// Start drawing this track's pictures.
        case showPicture(track: Int)
        /// Stop drawing pictures.
        case hidePicture
        /// Turn off the text subtitle the system menu has selected.
        case turnOffText
    }

    public struct Row: Equatable, Identifiable, Sendable {
        /// nil is the "Off" row.
        public var track: Int?
        public var title: String
        public var detail: String?
        public var isSelected: Bool
        public var id: Int { track ?? -1 }
    }

    public static let menuTitle = "Picture Subtitles"
    public static let offTitle = "Off"

    public private(set) var choices: [PictureSubtitleChoice]
    public private(set) var selected: Int?
    public private(set) var textIsOn: Bool

    public init(choices: [PictureSubtitleChoice]) {
        self.choices = choices
        self.selected = nil
        self.textIsOn = false
    }

    public init(info: [PictureSubtitleInfo]) {
        self.init(choices: info.map {
            PictureSubtitleChoice(id: $0.trackNumber, title: $0.name, language: $0.language, isDefault: $0.isDefault,
                                  isForced: $0.isForced, isHearingImpaired: $0.isHearingImpaired)
        })
    }

    /// The menu is only shown when the file has picture subtitles (nothing is added to the transport bar otherwise).
    public var isVisible: Bool { !choices.isEmpty }

    /// "Off" first, then every track in file order. Exactly one row is selected.
    public var rows: [Row] {
        var out = [Row(track: nil, title: Self.offTitle, detail: nil, isSelected: selected == nil)]
        for c in choices { out.append(Row(track: c.id, title: c.title, detail: c.detail, isSelected: selected == c.id)) }
        return out
    }

    /// The person picked a row (nil is "Off"). Picking a track that is not in the file does nothing.
    public mutating func choose(_ track: Int?) -> [Effect] {
        guard let track else {
            guard selected != nil else { return [] }
            selected = nil
            return [.hidePicture]
        }
        guard choices.contains(where: { $0.id == track }), selected != track else { return [] }
        selected = track
        var effects: [Effect] = []
        if textIsOn { effects.append(.turnOffText); textIsOn = false }
        effects.append(.showPicture(track: track))
        return effects
    }

    /// The system subtitle menu changed: a text track is now selected (true) or none is (false).
    public mutating func textSelectionChanged(isOn: Bool) -> [Effect] {
        textIsOn = isOn
        guard isOn, selected != nil else { return [] }
        selected = nil
        return [.hidePicture]
    }

    /// Picture subtitles start off. PROVISIONAL: nothing is chosen for the person, not even a forced or default track; the
    /// system chooses a text track from the person's language settings, and a picture track is an explicit choice.
    /// Alternative: pick the default or forced picture track when no text track matches the preferred language.
    public var initialEffects: [Effect] { [] }
}
