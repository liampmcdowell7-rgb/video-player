import Foundation

/// A language with an optional region or script, normalised: `language` is the ISO 639-1 code when one
/// exists, else the ISO 639-2 (terminologic) code. Examples: "en", "pt-BR", "zh-Hans", "fil".
public struct LanguageTag: Equatable, Hashable, Sendable, Codable, CustomStringConvertible {
    public var language: String
    public var region: String?
    public var script: String?

    public init(language: String, region: String? = nil, script: String? = nil) {
        self.language = language
        self.region = region
        self.script = script
    }

    public var description: String {
        var s = language
        if let script { s += "-" + script }
        if let region { s += "-" + region }
        return s
    }

    /// Parses codes (`en`, `eng`, `pt-BR`, `zh_Hans`, `chs`) and English or native names (`English`, `Español`).
    /// Returns nil for text that is not a language.
    public init?(_ text: String) {
        guard let parsed = LanguageTable.parse(text) else { return nil }
        self = parsed
    }

    /// How well a track in `self` satisfies a wish for `wanted`: 2 = same language and same region/script,
    /// 1 = same language (the wish or the track gave no region, or it differs), 0 = different language.
    public func match(wanted: LanguageTag) -> Int {
        guard language == wanted.language else { return 0 }
        if let r = wanted.region, region != r { return 1 }
        if let s = wanted.script, script != s { return 1 }
        return 2
    }
}

public enum LanguageTable {
    struct Entry {
        let iso1: String?
        let iso2: String      // terminologic (T)
        let iso2b: String?    // bibliographic (B) when different
        let names: [String]   // lowercase English name first, then other names
    }

    // iso1, iso2T, iso2B, names...
    static let entries: [Entry] = [
        e("en", "eng", nil, "english", "inglés", "anglais", "englisch"),
        e("ja", "jpn", nil, "japanese", "日本語", "japonais", "japanisch", "nihongo"),
        e("fr", "fra", "fre", "french", "français", "francais", "francés", "französisch"),
        e("de", "deu", "ger", "german", "deutsch", "alemán", "allemand"),
        e("es", "spa", nil, "spanish", "español", "espanol", "castellano", "espagnol"),
        e("it", "ita", nil, "italian", "italiano", "italien"),
        e("pt", "por", nil, "portuguese", "português", "portugues", "portugais"),
        e("ru", "rus", nil, "russian", "русский", "russe"),
        e("zh", "zho", "chi", "chinese", "中文", "mandarin", "chinois", "普通话", "國語"),
        e("ko", "kor", nil, "korean", "한국어", "coréen"),
        e("nl", "nld", "dut", "dutch", "nederlands", "flemish"),
        e("sv", "swe", nil, "swedish", "svenska"),
        e("no", "nor", nil, "norwegian", "norsk"),
        e("nb", "nob", nil, "norwegian bokmål", "bokmål", "bokmal"),
        e("nn", "nno", nil, "norwegian nynorsk", "nynorsk"),
        e("da", "dan", nil, "danish", "dansk"),
        e("fi", "fin", nil, "finnish", "suomi"),
        e("pl", "pol", nil, "polish", "polski"),
        e("cs", "ces", "cze", "czech", "čeština", "cesky", "česky"),
        e("sk", "slk", "slo", "slovak", "slovenčina", "slovensky"),
        e("hu", "hun", nil, "hungarian", "magyar"),
        e("ro", "ron", "rum", "romanian", "română", "romana"),
        e("bg", "bul", nil, "bulgarian", "български"),
        e("el", "ell", "gre", "greek", "ελληνικά", "grec"),
        e("tr", "tur", nil, "turkish", "türkçe", "turkce"),
        e("he", "heb", nil, "hebrew", "עברית"),
        e("ar", "ara", nil, "arabic", "العربية"),
        e("fa", "fas", "per", "persian", "farsi", "فارسی"),
        e("hi", "hin", nil, "hindi", "हिन्दी"),
        e("bn", "ben", nil, "bengali", "bangla", "বাংলা"),
        e("ta", "tam", nil, "tamil", "தமிழ்"),
        e("te", "tel", nil, "telugu", "తెలుగు"),
        e("ml", "mal", nil, "malayalam", "മലയാളം"),
        e("mr", "mar", nil, "marathi", "मराठी"),
        e("ur", "urd", nil, "urdu", "اردو"),
        e("th", "tha", nil, "thai", "ไทย"),
        e("vi", "vie", nil, "vietnamese", "tiếng việt", "tieng viet"),
        e("id", "ind", nil, "indonesian", "bahasa indonesia"),
        e("ms", "msa", "may", "malay", "bahasa melayu"),
        e("tl", "tgl", nil, "tagalog"),
        e("uk", "ukr", nil, "ukrainian", "українська"),
        e("be", "bel", nil, "belarusian", "беларуская"),
        e("sr", "srp", nil, "serbian", "српски", "srpski"),
        e("hr", "hrv", nil, "croatian", "hrvatski"),
        e("bs", "bos", nil, "bosnian", "bosanski"),
        e("sl", "slv", nil, "slovenian", "slovene", "slovenščina"),
        e("mk", "mkd", "mac", "macedonian", "македонски"),
        e("sq", "sqi", "alb", "albanian", "shqip"),
        e("lt", "lit", nil, "lithuanian", "lietuvių"),
        e("lv", "lav", nil, "latvian", "latviešu"),
        e("et", "est", nil, "estonian", "eesti"),
        e("is", "isl", "ice", "icelandic", "íslenska"),
        e("ga", "gle", nil, "irish", "gaeilge"),
        e("cy", "cym", "wel", "welsh", "cymraeg"),
        e("ca", "cat", nil, "catalan", "català"),
        e("eu", "eus", "baq", "basque", "euskara"),
        e("gl", "glg", nil, "galician", "galego"),
        e("af", "afr", nil, "afrikaans"),
        e("sw", "swa", nil, "swahili", "kiswahili"),
        e("ka", "kat", "geo", "georgian", "ქართული"),
        e("hy", "hye", "arm", "armenian", "հայերեն"),
        e("az", "aze", nil, "azerbaijani", "azərbaycanca"),
        e("kk", "kaz", nil, "kazakh", "қазақша"),
        e("uz", "uzb", nil, "uzbek"),
        e("mn", "mon", nil, "mongolian", "монгол"),
        e("ne", "nep", nil, "nepali"),
        e("si", "sin", nil, "sinhala", "sinhalese"),
        e("km", "khm", nil, "khmer"),
        e("my", "mya", "bur", "burmese"),
        e("lo", "lao", nil, "lao"),
        e("la", "lat", nil, "latin"),
        e("yue", "yue", nil, "cantonese", "粵語", "廣東話"),
        e("fil", "fil", nil, "filipino"),
        e("mt", "mlt", nil, "maltese"),
        e("lb", "ltz", nil, "luxembourgish"),
    ]

    private static func e(_ iso1: String?, _ iso2: String, _ iso2b: String?, _ names: String...) -> Entry {
        Entry(iso1: iso1 == iso2 ? nil : iso1, iso2: iso2, iso2b: iso2b, names: names)
    }

    private static let index: [String: Entry] = {
        var map: [String: Entry] = [:]
        for entry in entries {
            if let c = entry.iso1 { map[c] = entry }
            map[entry.iso2] = entry
            if let b = entry.iso2b { map[b] = entry }
            for n in entry.names { map[fold(n)] = entry }
        }
        return map
    }()

    /// Lowercases and removes diacritics so "Español" and "espanol" meet.
    static func fold(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping.lowercased()
    }

    static func canonical(_ entry: Entry) -> String { entry.iso1 ?? entry.iso2 }

    private static let regions: Set<String> = [
        "us", "gb", "uk", "au", "ca", "nz", "ie", "in", "za", "br", "pt", "mx", "es", "ar", "cl", "co", "pe", "ve",
        "fr", "be", "ch", "de", "at", "it", "nl", "se", "no", "dk", "fi", "pl", "cz", "sk", "hu", "ro", "bg", "gr",
        "tr", "ru", "ua", "il", "sa", "ae", "eg", "jp", "kr", "cn", "tw", "hk", "sg", "th", "vn", "id", "my", "ph",
        "419", "latn"
    ]
    private static let scripts: [String: String] = ["hans": "Hans", "hant": "Hant", "latn": "Latn", "cyrl": "Cyrl", "arab": "Arab"]

    /// File-name shorthand seen in the wild.
    private static let shorthand: [String: LanguageTag] = [
        "chs": LanguageTag(language: "zh", script: "Hans"),
        "cht": LanguageTag(language: "zh", script: "Hant"),
        "big5": LanguageTag(language: "zh", script: "Hant"),
        "simplified": LanguageTag(language: "zh", script: "Hans"),
        "traditional": LanguageTag(language: "zh", script: "Hant"),
        "brazilian": LanguageTag(language: "pt", region: "BR"),
        "latam": LanguageTag(language: "es", region: "419"),
        "castilian": LanguageTag(language: "es", region: "ES"),
    ]

    static func parse(_ text: String) -> LanguageTag? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return nil }
        let lower = fold(raw)
        if let sh = shorthand[lower] { return sh }
        if let entry = index[lower], !entry.names.isEmpty, entry.names.map(fold).contains(lower) {
            return LanguageTag(language: canonical(entry))
        }
        // Tags: split on "-" or "_".
        let parts = lower.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        guard let first = parts.first, first.count <= 3, let entry = index[first] else { return nil }
        var tag = LanguageTag(language: canonical(entry))
        for part in parts.dropFirst() {
            if let s = scripts[part] { tag.script = s }
            else if part.count == 2 && regions.contains(part) { tag.region = part == "uk" ? "GB" : part.uppercased() }
            else if part == "419" { tag.region = "419" }
            else if part == "tw" || part == "hk" { tag.region = part.uppercased() }
            else if let sh = shorthand[part] { tag.script = sh.script ?? tag.script; tag.region = sh.region ?? tag.region }
            else { return nil }
        }
        // zh-TW, zh-HK are Traditional; zh-CN, zh-SG are Simplified, when no script was given.
        if tag.language == "zh", tag.script == nil, let r = tag.region {
            if r == "TW" || r == "HK" { tag.script = "Hant" }
            if r == "CN" || r == "SG" { tag.script = "Hans" }
        }
        return tag
    }

    /// English display name for pickers ("English", "Portuguese (BR)").
    public static func displayName(_ tag: LanguageTag) -> String {
        let base = entries.first { canonical($0) == tag.language }?.names.first?.capitalized ?? tag.language
        var extra: [String] = []
        if let s = tag.script { extra.append(s == "Hans" ? "Simplified" : s == "Hant" ? "Traditional" : s) }
        if let r = tag.region { extra.append(r) }
        return extra.isEmpty ? base : "\(base) (\(extra.joined(separator: ", ")))"
    }
}
