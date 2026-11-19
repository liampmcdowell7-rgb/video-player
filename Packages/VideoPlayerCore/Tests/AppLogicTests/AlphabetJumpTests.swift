import XCTest
import LibraryIndex
@testable import AppLogic

final class AlphabetJumpTests: XCTestCase {
    func testLettersIgnoreCaseAccentsAndTheLeadingArticle() {
        XCTAssertEqual(TitleLetter.letter(for: "aftlander"), "A")
        XCTAssertEqual(TitleLetter.letter(for: "Éclair"), "E")
        XCTAssertEqual(TitleLetter.letter(for: "The Marrowgate"), "M", "The is dropped")
        XCTAssertEqual(TitleLetter.letter(for: "A Hushed Room"), "H")
        XCTAssertEqual(TitleLetter.letter(for: "An Education"), "E")
        XCTAssertEqual(TitleLetter.letter(for: "Theory of Everything"), "T", "only the whole word The is an article")
        XCTAssertEqual(TitleLetter.letter(for: "Ångström"), "A")
    }

    func testDigitsSymbolsAndOtherScriptsGoToHash() {
        for t in ["2047: A Quiet Voyage", "417", "(700) Nights of Rain", "青い灯台の物語", "   ", ""] {
            XCTAssertEqual(TitleLetter.letter(for: t), "#", t)
        }
    }

    func testLeadingPunctuationIsSkippedLikeTheLibrarySortDoes() {
        XCTAssertEqual(TitleLetter.letter(for: "!Hero"), "H")
        XCTAssertEqual(TitleLetter.letter(for: "¿Qué?"), "Q")
    }

    func testTheOnlyTitleThatIsAnArticleStaysUnderItsOwnLetter() {
        XCTAssertEqual(TitleLetter.letter(for: "The"), "T")
        XCTAssertEqual(TitleLetter.letter(for: "A"), "A")
    }

    func testTheJumpListHasHashFirstThenAToZ() {
        XCTAssertEqual(TitleLetter.all.count, 27)
        XCTAssertEqual(TitleLetter.all.first, "#")
        XCTAssertEqual(TitleLetter.all.last, "Z")
    }

    func testSortKeyOrdersHashFirstAndNumbersByValue() {
        let titles = ["Zornwick", "The Apiary", "Aquila 100", "Aquila 13", "2001", "Aftlander"]
        let sorted = titles.sorted { TitleLetter.sortKey($0) < TitleLetter.sortKey($1) }
        XCTAssertEqual(sorted, ["2001", "Aftlander", "The Apiary", "Aquila 13", "Aquila 100", "Zornwick"])
    }

    func testTargetsListOnlyLettersThatExistWithTheFirstTitleOfEach() {
        let list: [(id: Int64, title: String)] = [(1, "2001"), (2, "Aftlander"), (3, "Alpha"), (4, "The Marrowgate"), (5, "Zornwick")]
        let targets = AlphabetJump.targets(forTitles: list)
        XCTAssertEqual(targets.map(\.letter), ["#", "A", "M", "Z"])
        XCTAssertEqual(targets.first { $0.letter == "A" }?.firstID, 2)
        XCTAssertEqual(targets.first { $0.letter == "A" }?.count, 2)
        XCTAssertEqual(AlphabetJump.label(targets[1]), "A (2)")
        XCTAssertTrue(AlphabetJump.targets(forTitles: []).isEmpty)
    }

    func testShowsAreSortedByTheSameKeyAsTheLetters() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        var vm = ShowsViewModel(store: rig.store)
        await vm.load()
        let shows = try XCTUnwrap(vm.state.content)
        XCTAssertEqual(shows.map(\.title), ["Show One", "Show Two"])
        XCTAssertEqual(AlphabetJump.targets(for: shows).map(\.letter), ["S"])
    }

    func testMoviesJumpStartsTheGridAtTheLetterAndKeepsPaging() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        var base = ItemFilter()
        base.kinds = [.movie]
        var grid = ItemGridViewModel(store: rig.store, base: base, pageSize: 1, noun: "movies")
        await grid.load()
        let loaded = try XCTUnwrap(grid.state.content)
        XCTAssertEqual(loaded.alphabet.map(\.letter), ["A", "H", "Z"])
        XCTAssertEqual(loaded.cards.map(\.title), ["Aftlander"])
        await grid.jump(to: "H")
        var content = try XCTUnwrap(grid.state.content)
        XCTAssertEqual(content.cards.map(\.title), ["Hexfall"], "starts at the first H")
        XCTAssertEqual(grid.jumpedTo, "H")
        XCTAssertTrue(content.hasMore)
        await grid.loadMore()
        content = try XCTUnwrap(grid.state.content)
        XCTAssertEqual(content.cards.map(\.title), ["Hexfall", "Zornwick"], "paging continues after the jump")
        XCTAssertFalse(content.hasMore)
        await grid.jump(to: "Q")
        XCTAssertEqual(try XCTUnwrap(grid.state.content).cards.count, 2, "a letter with no titles changes nothing")
        await grid.load()
        XCTAssertNil(grid.jumpedTo, "a normal load clears the jump")
    }
}
