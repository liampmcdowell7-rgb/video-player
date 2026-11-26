import XCTest
@testable import ScreenChecks

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
}
