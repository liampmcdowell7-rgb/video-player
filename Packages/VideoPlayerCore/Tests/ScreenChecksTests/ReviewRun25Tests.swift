import XCTest
@testable import ScreenChecks

/// R409 to R411 (owner's reading of run #25's notes, item 9): each fix checked from the source (structure only: nothing
/// is compiled or run on tvOS here). Whether the next run agrees waits for that run.
extension ScreenChecksTests {
    /// The body of the first `func <name>` / `struct <name>` in `source`.
    private func run25Body(of declaration: String, in source: String) throws -> String {
        let start: String.Index = try XCTUnwrap(source.range(of: declaration)?.lowerBound, "no \(declaration)")
        return String(try XCTUnwrap(Self.braceBody(of: source, after: start), "the body of \(declaration)"))
    }

    /// R409 (a): a picture needs only `runningForeground` (raw value 4); the wait for a "screen." element is for launches
    /// only, since pushed pages carry no such identifier and the sidebar is out of the tree there.
    func testAPictureNeedsOnlyTheForegroundState() throws {
        guard let tests = try appSource("UITests/ScreenshotTests.swift") else { return }
        let front: String = try run25Body(of: "func appIsInFront(", in: tests)
        XCTAssertTrue(front.contains("app.wait(for: .runningForeground, timeout: timeout)"), "the state is no longer the test")
        XCTAssertTrue(front.contains("guard waitForScreen else { return true }"), "a picture still needs a screen. element or the sidebar")
        let shot: String = try run25Body(of: "func shot(_ name: String", in: tests)
        XCTAssertTrue(shot.contains("appIsInFront(app, timeout: 2)"), "shot does not use the state-only check")
        XCTAssertFalse(shot.contains("waitForScreen: true"), "shot still waits for a screen. element")
        let launch: String = try run25Body(of: "func launch(_ mode: String", in: tests)
        XCTAssertTrue(launch.contains("waitForScreen: true"), "a launch no longer waits for one of the app's screens")
        XCTAssertTrue(tests.contains("4: \"running in the foreground\""), "the note does not name state 4")
    }

    /// R410 (b): How This Was Sorted has its own navigation stack, as every other task cover that shows a `TaskPage`.
    func testEveryTaskPageCoverHasItsOwnNavigationStack() throws {
        let covers: [(String, String)] = [("App/Shared/SortMoveSheet.swift", "struct SortInfoSheet: View {"),
                                          ("App/Shared/SortMoveSheet.swift", "struct SortMoveSheet: View {"),
                                          ("App/Features/FixMatch/FixMatchView.swift", "struct FixMatchView: View {"),
                                          ("App/Features/Movies/SaveViewSheet.swift", "struct SaveViewSheet<Screen: QueryGridScreen>: View {"),
                                          ("App/Features/Files/FileDetailsSheet.swift", "struct FileDetailsSheet: View {")]
        for (path, declaration) in covers {
            guard let source = try appSource(path) else { continue }
            let structure: String = try run25Body(of: declaration, in: source)
            let body: String = try run25Body(of: "var body: some View {", in: structure)
            let first: String = body.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty && !$0.hasPrefix("//") } ?? ""
            XCTAssertEqual(first, "NavigationStack {", "\(declaration) (\(path)) is not inside its own navigation stack")
        }
    }

    /// R411 (d): the sidebar check takes neighbours in the drawn order and reports only frames that intersect.
    func testTheSidebarCheckComparesItemsInTheirDrawnOrder() throws {
        guard let tests = try appSource("UITests/ScreenshotTests.swift") else { return }
        let check: String = try run25Body(of: "func tabBarCheck(", in: tests)
        XCTAssertTrue(check.contains("let drawn: [XCUIElement] = items.sorted"), "neighbours are not sorted by where they are drawn")
        XCTAssertTrue(check.contains("zip(drawn, drawn.dropFirst())"), "the overlap test still walks the declared order")
        XCTAssertFalse(check.contains("zip(items, items.dropFirst())"), "the overlap test still walks the declared order")
        XCTAssertTrue(check.contains("drawn order (recorded, not judged)"), "the drawn order is not recorded")
    }
}
