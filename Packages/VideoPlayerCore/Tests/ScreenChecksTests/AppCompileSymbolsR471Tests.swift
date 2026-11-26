import XCTest
@testable import ScreenChecks

/// R471 (101): a stand-in for SwiftUI's `ForEach(_:id:content:)` (Linux has no SwiftUI): the same generic shape, a key path
/// id and a result-builder content closure taking the collection's element.
@resultBuilder private enum ProbeBuilder { static func buildBlock<T>(_ part: T) -> T { part } }
private struct Probe { let id: Int; let title: String }
private struct ProbeEach<Data: RandomAccessCollection, ID: Hashable, Content> {
    let made: [Content]
    init(_ data: Data, id: KeyPath<Data.Element, ID>, @ProbeBuilder content: @escaping (Data.Element) -> Content) {
        made = data.map(content)
    }
}

/// R471 (91) and later: app-target lines that named a member on the wrong type. The Linux tests and the parse check do
/// not compile the app, so each fix keeps a source check that the wrong name is gone and the declared one is used.
extension ScreenChecksTests {
    /// R471 (91): the archive of 983558e stopped at AppServices.swift:788, `SQLiteLibraryStore.watchedFraction`; the
    /// constant is `LibraryWatchRules.watchedFraction` (LibraryIndex, declared since the first commit).
    func testPlayHistoryUsesTheLibrarysWatchedFraction() throws {
        guard let services = try appSource("App/Support/AppServices.swift") else { return }
        XCTAssertFalse(services.contains("SQLiteLibraryStore.watchedFraction"), "a member SQLiteLibraryStore does not have")
        XCTAssertTrue(services.contains("position >= $0 * LibraryWatchRules.watchedFraction"), "Play History's finished point is not the library's")
        XCTAssertTrue(services.contains("import LibraryIndex"))
        let store = try XCTUnwrap(try appSource("Packages/VideoPlayerCore/Sources/LibraryIndex/SQLiteLibraryStore.swift"))
        XCTAssertTrue(store.contains("public enum LibraryWatchRules {\n    public static let watchedFraction"), "the constant moved")
    }

    /// R471 (99): the cover's preference action (a @Sendable closure in the SDK) changes main-actor state and calls the
    /// main-actor `publish()` only inside `MainActor.assumeIsolated`, so it is valid in Swift 5 and Swift 6 mode.
    func testArtTextTopsPreferenceActionRunsOnTheMainActor() throws {
        guard let source = try appSource("App/Shared/ArtTextTop.swift") else { return }
        let action = try XCTUnwrap(source.range(of: ".onPreferenceChange(ArtTextTopKey.self) { (value: CGFloat?) in"))
        let rest = source[action.upperBound...]
        let isolated = try XCTUnwrap(rest.range(of: "MainActor.assumeIsolated {"), "the preference action is not main-actor isolated")
        // The code between the action's start and the assumption (comments aside) touches no state.
        let before = rest[..<isolated.lowerBound].split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        XCTAssertTrue(before.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty },
                      "code runs in the preference action before the main-actor assumption")
        let body = rest[isolated.upperBound...].prefix(120)
        XCTAssertTrue(body.contains("contentTop = value") && body.contains("publish()"), "the state change and publish() are not inside")
    }

    /// R471 (101): six app files (PersonView, HomeRows, CardRow, PosterGrid, ShowsView, HeroLinesView) pass a ForEach over
    /// `Array(x.enumerated())` a closure with two typed parameters, `{ (index: Int, card: ItemCard) in … }`, for the one
    /// `(offset:element:)` element. This compiles the same form here (a generic init with a result-builder closure, as
    /// SwiftUI's ForEach), so a toolchain that stopped accepting it fails this test instead of the archive.
    func testATwoParameterClosureTakesAnEnumeratedElement() throws {
        let cards = [Probe(id: 7, title: "One"), Probe(id: 9, title: "Two")]
        let each = ProbeEach(Array(cards.enumerated()), id: \.element.id) { (index: Int, card: Probe) in
            "\(index). \(card.title)"
        }
        XCTAssertEqual(each.made, ["0. One", "1. Two"])
        guard let grid = try appSource("App/Shared/PosterGrid.swift") else { return }
        XCTAssertTrue(grid.contains("ForEach(Array(cards.enumerated()), id: \\.element.id) { (index: Int, card: ItemCard) in"),
                      "the app's form changed; check this probe still matches it")
    }

    /// R471 (100): every preference action in the app (a @Sendable closure in the SDK) does its main-actor work inside
    /// `MainActor.assumeIsolated`, the first statement of the action.
    func testEveryPreferenceActionRunsOnTheMainActor() throws {
        var checked = 0
        for path in ["App/Shared/ArtTextTop.swift", "App/Shared/PosterCard.swift"] {
            guard let source = try appSource(path) else { return }
            var rest = source[...]
            while let action = rest.range(of: ".onPreferenceChange(") {
                let after = rest[action.upperBound...]
                let open = try XCTUnwrap(after.range(of: " in\n"), "\(path): no closure after onPreferenceChange")
                let code = after[open.upperBound...].split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .first { !$0.isEmpty && !$0.hasPrefix("//") }
                XCTAssertEqual(code, "MainActor.assumeIsolated {", "\(path): a preference action runs code off the main actor")
                checked += 1
                rest = after
            }
        }
        XCTAssertEqual(checked, 2, "the app's preference actions changed; check each new one")
    }
}
