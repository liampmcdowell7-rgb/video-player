import Foundation

/// One chapter as read from a file (the MKV reader lives in another target and maps into this).
public struct ChapterMark: Equatable, Sendable {
    public struct Title: Equatable, Sendable {
        public var language: String?
        public var text: String
        public init(language: String? = nil, text: String) {
            self.language = language
            self.text = text
        }
    }

    public var start: TimeInterval
    /// Nil when the file gives no end; the next visible chapter's start (or the file end) is used.
    public var end: TimeInterval?
    public var titles: [Title]
    public var isHidden: Bool
    public var isEnabled: Bool
    public var editionID: UInt64?
    public var editionIsDefault: Bool

    public init(start: TimeInterval, end: TimeInterval? = nil, titles: [Title], isHidden: Bool = false,
                isEnabled: Bool = true, editionID: UInt64? = nil, editionIsDefault: Bool = false) {
        self.start = start
        self.end = end
        self.titles = titles
        self.isHidden = isHidden
        self.isEnabled = isEnabled
        self.editionID = editionID
        self.editionIsDefault = editionIsDefault
    }

    public init(start: TimeInterval, end: TimeInterval? = nil, title: String, isHidden: Bool = false,
                isEnabled: Bool = true, editionID: UInt64? = nil, editionIsDefault: Bool = false) {
        self.init(start: start, end: end, titles: [Title(text: title)], isHidden: isHidden,
                  isEnabled: isEnabled, editionID: editionID, editionIsDefault: editionIsDefault)
    }
}

public enum ChapterKind: String, Sendable, CaseIterable {
    case recap, intro, credits, postCredits
}

/// Recognises chapter titles such as Intro, Opening, Recap, Previously, Credits, Outro, Ending in many
/// languages. Matching is case-, diacritic- and numbering-insensitive ("Opening 2" is an intro,
/// "Chapter 01" is nothing). Whole-title match, so "Introduction to the Cast" is not an intro.
public enum ChapterTitleRecognizer {
    /// Result for one title, nil when it is not a skippable segment.
    public static func classify(_ title: String) -> ChapterKind? {
        let normalized = normalize(title)
        guard !normalized.isEmpty else { return nil }
        let stripped = stripNumbering(normalized)
        guard !stripped.isEmpty else { return nil }

        // Order matters: "post credits" must be tested before "credits".
        for kind in [ChapterKind.postCredits, .credits, .recap, .intro] {
            let table = tables[kind] ?? Table(exact: [], prefixes: [], contains: [])
            if table.exact.contains(stripped) { return kind }
            if table.prefixes.contains(where: { stripped.hasPrefix($0 + " ") }) { return kind }
            // Scripts written without spaces (Chinese, Japanese, Korean) match as a substring.
            if table.contains.contains(where: { stripped.contains($0) }) { return kind }
        }
        return nil
    }

    /// A chapter is classified when any of its titles (any language) is recognised.
    public static func classify(_ mark: ChapterMark) -> ChapterKind? {
        for title in mark.titles {
            if let kind = classify(title.text) { return kind }
        }
        return nil
    }

    // MARK: Normalisation

    /// NFKC, lower case, diacritics removed, a few letters mapped by hand, apostrophes dropped,
    /// everything that is not a letter becomes a space (digits too, so numbering disappears).
    /// The phrase tables go through the same function, so both sides always agree.
    static func normalize(_ text: String) -> String {
        var t = text.precomposedStringWithCompatibilityMapping.lowercased()
        t = t.folding(options: [.diacriticInsensitive], locale: nil)
        let map: [Character: String] = ["ł": "l", "ø": "o", "đ": "d", "ı": "i", "ß": "ss", "æ": "ae", "œ": "oe", "ħ": "h"]
        var out = ""
        for ch in t {
            if "'’‘`´ʼ".contains(ch) { continue }
            if let m = map[ch] { out += m; continue }
            if ch.isLetter { out.append(ch) } else { out.append(" ") }
        }
        return out.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    private static let numberingWords: Set<String> = [
        "part", "pt", "no", "nr", "teil", "partie", "parte", "deel", "del", "episode",
        "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x",
    ]

    /// Removes trailing numbering words ("part", roman numerals) left after digits became spaces.
    static func stripNumbering(_ normalized: String) -> String {
        var tokens = normalized.split(separator: " ").map(String.init)
        while let last = tokens.last, numberingWords.contains(last), tokens.count > 1 { tokens.removeLast() }
        return tokens.joined(separator: " ")
    }

    // MARK: Phrase tables

    struct Table {
        var exact: Set<String>
        var prefixes: [String]
        var contains: [String]
    }

    private static func makeTable(exact: [String], prefixes: [String] = [], contains: [String] = []) -> Table {
        Table(exact: Set(exact.map(normalize)), prefixes: prefixes.map(normalize), contains: contains.map(normalize))
    }

    private static let tables: [ChapterKind: Table] = [
        .intro: makeTable(
            exact: [
                // English
                "intro", "opening", "opening credits", "opening titles", "opening theme", "opening sequence", "title sequence",
                "main titles", "main title", "theme song", "op",
                // French
                "generique de debut", "generique d'ouverture", "ouverture", "generique douverture", "titre d'ouverture",
                // German
                "vorspann", "titelmusik", "titelsong", "intro", "eroffnung",
                // Spanish
                "introduccion", "apertura", "cabecera", "presentacion", "cortinilla",
                // Italian
                "sigla", "sigla iniziale", "titoli di testa", "apertura",
                // Portuguese
                "abertura", "introducao", "vinheta de abertura",
                // Dutch
                "openingstitels", "titelmuziek", "begintune", "begingenerique", "intro",
                // Swedish
                "inledning", "oppning", "introduktion", "intro", "titelsekvens",
                // Japanese
                "オープニング", "オープニングテーマ", "イントロ", "オープニング映像", "opening", "ＯＰ",
                // Korean
                "오프닝", "인트로", "오프닝 크레딧",
                // Russian
                "заставка", "вступление", "опенинг", "интро", "вступительные титры",
                // Chinese
                "片头", "片頭", "开场", "開場", "片头曲", "片頭曲", "主题曲", "主題曲",
                // Polish
                "czolowka", "wstep", "intro", "otwarcie",
                // Turkish
                "giris", "acilis", "acilis jenerigi", "giris jenerigi",
            ]),
        .recap: makeTable(
            exact: [
                // English
                "recap", "previously", "previously on", "the story so far", "story so far", "last time", "last time on",
                // French
                "precedemment", "resume", "resume des episodes precedents", "rappel", "precedemment dans",
                // German
                "zuvor", "bisher", "was bisher geschah", "ruckblick", "zusammenfassung", "vorab",
                // Spanish
                "resumen", "previamente", "anteriormente", "en capitulos anteriores", "capitulos anteriores", "lo que paso",
                // Italian
                "riassunto", "precedentemente", "in precedenza", "nelle puntate precedenti", "puntate precedenti",
                // Portuguese
                "resumo", "nos episodios anteriores", "episodios anteriores", "anteriormente em",
                // Dutch
                "eerder", "samenvatting", "voorheen", "in de vorige afleveringen", "vorige afleveringen", "eerder in",
                // Swedish
                "tidigare", "sammanfattning", "tidigare i", "i forra avsnittet",
                // Japanese
                "前回のあらすじ", "前回", "あらすじ", "リキャップ", "前回までのあらすじ",
                // Korean
                "지난 이야기", "이전 줄거리", "리캡", "지난 회", "지난 줄거리",
                // Russian
                "ранее", "ранее в сериале", "предыдущие серии", "в предыдущих сериях", "краткое содержание", "ранее в",
                // Chinese
                "前情提要", "前情回顾", "前情回顧", "上集回顾", "上集回顧", "前情概要", "前情",
                // Polish
                "poprzednio", "w poprzednich odcinkach", "streszczenie", "poprzednio w",
                // Turkish
                "onceki bolum", "onceki bolumlerde", "daha once", "ozet", "gecen bolum",
            ],
            prefixes: [
                "previously on", "previously in", "last time on", "last time in", "recap of", "recap from",
                "precedemment dans", "anteriormente en", "anteriormente em", "eerder in", "tidigare i", "poprzednio w",
            ],
            contains: ["前回のあらすじ", "前情提要", "前情回顾", "前情回顧", "지난 이야기", "이전 줄거리"]),
        .credits: makeTable(
            exact: [
                // English
                "credits", "end credits", "closing credits", "final credits", "end titles", "closing titles", "outro", "ending",
                "ending theme", "end theme", "ending credits", "ed", "rolling credits",
                // French
                "generique", "generique de fin", "generique final", "titres de fin",
                // German
                "abspann", "nachspann", "outro", "schlussabspann",
                // Spanish
                "creditos", "creditos finales", "cierre", "creditos de cierre",
                // Italian
                "titoli di coda", "crediti", "sigla finale", "crediti finali",
                // Portuguese
                "creditos finais", "encerramento", "creditos",
                // Dutch
                "aftiteling", "eindgenerique", "afsluiting", "credits", "eindtitels", "slotcredits",
                // Swedish
                "eftertexter", "eftertext", "avslutning", "sluttext", "credits", "slutsekvens",
                // Japanese
                "エンディング", "エンドクレジット", "クレジット", "スタッフロール", "エンドロール", "エンディングテーマ", "エンディング映像",
                "ending", "ＥＤ",
                // Korean
                "엔딩", "크레딧", "엔딩 크레딧", "엔드 크레딧", "엔딩크레딧",
                // Russian
                "титры", "финальные титры", "эндинг", "конечные титры", "окончание", "завершающие титры",
                // Chinese
                "片尾", "片尾曲", "演职员表", "演職員表", "片尾字幕", "结尾", "結尾", "片尾字幕", "制作人员", "製作人員",
                // Polish
                "napisy koncowe", "napisy", "zakonczenie", "tyly", "koncowka",
                // Turkish
                "bitis jenerigi", "kapanis jenerigi", "son jenerik", "jenerik sonu",
            ]),
        .postCredits: makeTable(
            exact: [
                // English
                "post credits", "post credit", "post credits scene", "post credit scene", "after credits", "after the credits",
                "after credits scene", "stinger", "post credits stinger", "mid credits scene", "extras scene", "bonus scene",
                "end credits scene", "tag scene",
                // French
                "apres le generique", "scene post generique", "scene apres generique",
                // German
                "nach dem abspann", "abspannszene", "nach abspann", "post abspann",
                // Spanish
                "despues de los creditos", "escena post creditos", "escena poscreditos", "escena postcreditos",
                // Italian
                "dopo i titoli di coda", "scena dopo i titoli", "scena post credits",
                // Portuguese
                "apos os creditos", "cena pos creditos", "cena pos-creditos", "cena pos creditos",
                // Dutch
                "na de aftiteling", "scene na de aftiteling",
                // Swedish
                "efter eftertexterna", "scen efter eftertexterna",
                // Japanese
                "エンドクレジット後", "おまけ", "エンドロール後", "エンドクレジット後映像",
                // Korean
                "쿠키 영상", "엔딩 크레딧 후", "쿠키",
                // Russian
                "после титров", "сцена после титров", "сцена после финальных титров",
                // Chinese
                "片尾彩蛋", "彩蛋", "片尾后", "片尾後", "片尾彩蛋场景",
                // Polish
                "po napisach", "scena po napisach",
                // Turkish
                "jenerik sonrasi", "jenerik sonrasi sahne", "bitis sonrasi sahne",
            ],
            contains: ["彩蛋", "エンドクレジット後", "エンドロール後", "쿠키 영상", "после титров"]),
    ]
}

/// Turns a file's chapters into segment candidates and finds a post-credits chapter.
public enum ChapterSegmentExtractor {
    /// PROVISIONAL INTERPRETATION: confidence given to a chapter-derived segment. Chapter titles are the
    /// uploader's own labels, so they are trusted well above the 0.7 threshold, but below a user's mark (1.0).
    public static let chapterConfidence = 0.9

    public struct Extraction: Equatable, Sendable {
        public var candidates: [SkipSegment]
        public var postCreditsStart: TimeInterval?
    }

    /// Picks one edition (the one flagged default, else the first edition in the file), ignores hidden and
    /// disabled chapters, and uses each chapter's end (or the next usable chapter's start, or the file end).
    public static func extract(chapters: [ChapterMark], file: FileIdentity) -> Extraction {
        let edition = chosenEdition(chapters)
        let usable = chapters
            .filter { $0.editionID == edition && !$0.isHidden && $0.isEnabled }
            .sorted { $0.start < $1.start }

        var candidates: [SkipSegment] = []
        var postStart: TimeInterval?
        for (index, mark) in usable.enumerated() {
            guard let kind = ChapterTitleRecognizer.classify(mark) else { continue }
            let nextStart = index + 1 < usable.count ? usable[index + 1].start : file.duration
            let end = mark.end ?? nextStart
            switch kind {
            case .postCredits:
                if postStart == nil { postStart = mark.start }
            case .recap, .intro, .credits:
                let type: SegmentType = kind == .recap ? .recap : (kind == .intro ? .intro : .credits)
                candidates.append(SkipSegment(type: type, start: mark.start, end: end, source: .embeddedChapters,
                                              confidence: chapterConfidence, file: file))
            }
        }
        return Extraction(candidates: candidates, postCreditsStart: postStart)
    }

    static func chosenEdition(_ chapters: [ChapterMark]) -> UInt64? {
        if let flagged = chapters.first(where: { $0.editionIsDefault }) { return flagged.editionID }
        return chapters.first?.editionID
    }
}
