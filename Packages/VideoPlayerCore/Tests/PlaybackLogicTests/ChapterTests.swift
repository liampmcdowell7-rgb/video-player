import XCTest
@testable import PlaybackLogic

final class ChapterTests: XCTestCase {
    private func classify(_ title: String) -> ChapterKind? { ChapterTitleRecognizer.classify(title) }

    // CH-1 (table-driven, one row per language and kind)
    func testCH1_titlesInManyLanguages() {
        let rows: [(String, String, ChapterKind)] = [
            ("EN", "Intro", .intro), ("EN", "Opening Credits", .intro), ("EN", "Previously on", .recap),
            ("EN", "Recap", .recap), ("EN", "End Credits", .credits), ("EN", "Outro", .credits),
            ("FR", "Générique de début", .intro), ("FR", "Précédemment", .recap), ("FR", "Générique de fin", .credits),
            ("DE", "Vorspann", .intro), ("DE", "Was bisher geschah", .recap), ("DE", "Abspann", .credits),
            ("ES", "Introducción", .intro), ("ES", "Resumen", .recap), ("ES", "Créditos finales", .credits),
            ("IT", "Sigla iniziale", .intro), ("IT", "Riassunto", .recap), ("IT", "Titoli di coda", .credits),
            ("PT", "Abertura", .intro), ("PT", "Resumo", .recap), ("PT", "Créditos finais", .credits),
            ("NL", "Openingstitels", .intro), ("NL", "Eerder", .recap), ("NL", "Aftiteling", .credits),
            ("SV", "Inledning", .intro), ("SV", "Tidigare", .recap), ("SV", "Eftertexter", .credits),
            ("JA", "オープニング", .intro), ("JA", "前回のあらすじ", .recap), ("JA", "エンディング", .credits),
            ("JA", "第1話 前回のあらすじ", .recap),
            ("KO", "오프닝", .intro), ("KO", "지난 이야기", .recap), ("KO", "엔딩 크레딧", .credits),
            ("RU", "Заставка", .intro), ("RU", "Ранее", .recap), ("RU", "Титры", .credits),
            ("ZH", "片头", .intro), ("ZH", "前情提要", .recap), ("ZH", "片尾", .credits),
            ("PL", "Czołówka", .intro), ("PL", "Poprzednio", .recap), ("PL", "Napisy końcowe", .credits),
            ("TR", "Giriş", .intro), ("TR", "Önceki bölüm", .recap), ("TR", "Bitiş jeneriği", .credits),
        ]
        for (language, title, expected) in rows {
            XCTAssertEqual(classify(title), expected, "\(language): \(title)")
        }
    }

    // CH-2
    func testCH2_caseAndDiacriticsDoNotMatter() {
        for title in ["GÉNÉRIQUE DE FIN", "generique de fin", "Generique De Fin", "Générique  de   fin "] {
            XCTAssertEqual(classify(title), .credits, title)
        }
        XCTAssertEqual(classify("INTRO"), .intro)
        XCTAssertEqual(classify("créditos FINALES"), .credits)
    }

    // CH-3
    func testCH3_numberingIsIgnoredButPlainChaptersAreNot() {
        XCTAssertEqual(classify("Opening 2"), .intro)
        XCTAssertEqual(classify("Intro 01"), .intro)
        XCTAssertEqual(classify("Intro II"), .intro)
        XCTAssertEqual(classify("Credits Part 2"), .credits)
        XCTAssertEqual(classify("Recap 3"), .recap)
        for title in ["Chapter 01", "Chapter 2", "Scene 3", "Act II", "Kapitel 1", "Chapitre 4", "第2章", "1", ""] {
            XCTAssertNil(classify(title), title)
        }
    }

    // CH-4
    func testCH4_ordinaryTitlesContainingTheWordsAreNotMatched() {
        for title in ["Introduction to the Cast", "The Ending of Everything", "Opening the Vault", "Final Battle",
                      "Credits Roll Fight", "Fin", "Coda", "The End"] {
            XCTAssertNil(classify(title), title)
        }
    }

    // CH-5
    func testCH5_prefixForm() {
        XCTAssertEqual(classify("Previously on Breaking Stuff"), .recap)
        XCTAssertEqual(classify("Précédemment dans Show"), .recap)
        XCTAssertNil(classify("Previously Unseen Footage of Dogs"))
    }

    // CH-6
    func testCH6_postCreditsChaptersAreRecognisedBeforeCredits() {
        let rows: [(String, ChapterKind)] = [
            ("Post-Credits Scene", .postCredits), ("Post Credits", .postCredits), ("Stinger", .postCredits),
            ("After Credits", .postCredits), ("Extras scene", .postCredits), ("Mid-credits scene", .postCredits),
            ("Nach dem Abspann", .postCredits), ("Après le générique", .postCredits), ("Escena post créditos", .postCredits),
            ("После титров", .postCredits), ("片尾彩蛋", .postCredits), ("쿠키 영상", .postCredits),
            ("エンドクレジット後", .postCredits), ("Po napisach", .postCredits), ("Jenerik sonrası", .postCredits),
            ("Credits", .credits),
        ]
        for (title, kind) in rows { XCTAssertEqual(classify(title), kind, title) }
    }

    // CH-7
    func testCH7_anyTitleLanguageOfAMarkCanMatch() {
        let mark = ChapterMark(start: 10, titles: [
            .init(language: "eng", text: "Chapter 3"), .init(language: "fra", text: "Générique de fin"),
        ])
        XCTAssertEqual(ChapterTitleRecognizer.classify(mark), .credits)
    }

    // CH-8
    func testCH8_hiddenAndDisabledChaptersAreIgnored() {
        let chapters = [
            ChapterMark(start: 0, title: "Intro", isHidden: true),
            ChapterMark(start: 100, title: "Part A"),
            ChapterMark(start: 500, title: "Outro", isEnabled: false),
            ChapterMark(start: 900, title: "Credits"),
        ]
        let extraction = ChapterSegmentExtractor.extract(chapters: chapters, file: Fixture.file)
        XCTAssertEqual(extraction.candidates.map(\.type), [.credits])
        XCTAssertEqual(extraction.candidates.first?.start, 900)
        XCTAssertEqual(extraction.candidates.first?.end, 1000)
        XCTAssertEqual(extraction.candidates.first?.source, .embeddedChapters)
        XCTAssertEqual(extraction.candidates.first?.confidence, ChapterSegmentExtractor.chapterConfidence)
        XCTAssertEqual(ChapterSegmentExtractor.chapterConfidence, 0.9)
    }

    // CH-9
    func testCH9_onlyOneEditionIsUsed_theDefaultOneWhenFlagged() {
        let chapters = [
            ChapterMark(start: 0, title: "Intro", editionID: 1),
            ChapterMark(start: 60, title: "Story", editionID: 1),
            ChapterMark(start: 0, title: "Recap", editionID: 2, editionIsDefault: true),
            ChapterMark(start: 40, title: "Story", editionID: 2),
        ]
        let extraction = ChapterSegmentExtractor.extract(chapters: chapters, file: Fixture.file)
        XCTAssertEqual(extraction.candidates.map(\.type), [.recap])
        XCTAssertEqual(extraction.candidates.first?.end, 40)

        let noFlag = ChapterSegmentExtractor.extract(chapters: Array(chapters.prefix(2)), file: Fixture.file)
        XCTAssertEqual(noFlag.candidates.map(\.type), [.intro])
    }

    // CH-10
    func testCH10_postCreditsChapterBecomesTheCreditsEnd() {
        let chapters = [
            ChapterMark(start: 0, title: "Story"),
            ChapterMark(start: 900, title: "Credits"),
            ChapterMark(start: 960, title: "Post-credits scene"),
        ]
        let extraction = ChapterSegmentExtractor.extract(chapters: chapters, file: Fixture.file)
        XCTAssertEqual(extraction.postCreditsStart, 960)
        XCTAssertEqual(extraction.candidates.first?.end, 960)
        let resolved = SegmentResolver.resolve(file: Fixture.file, candidates: extraction.candidates,
                                               postCreditsStart: extraction.postCreditsStart)
        XCTAssertEqual(resolved.segment(of: .credits)?.end, 960)
    }

    // CH-11: chapter-derived segments go through the same safety limits
    func testCH11_chapterSegmentsObeyLimits() {
        let chapters = [ChapterMark(start: 0, title: "Credits"), ChapterMark(start: 500, title: "Story")]
        let extraction = ChapterSegmentExtractor.extract(chapters: chapters, file: Fixture.file)
        let resolved = SegmentResolver.resolve(file: Fixture.file, candidates: extraction.candidates)
        XCTAssertTrue(resolved.segments.isEmpty)
        XCTAssertEqual(resolved.rejected.first?.reason, .creditsStartTooEarly)
    }
}
