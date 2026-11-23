import Foundation
import XCTest
@testable import ScreenChecks

/// R412 (compile check run #26 on a10f582: "'scrollContentBackground' is unavailable in tvOS"): SwiftUI calls whose Apple
/// page lists no tvOS. Nothing here compiles for tvOS; this only stops a call that is known to be missing from reaching a
/// compile check again. A call goes on the list only after its Apple page was read and showed no tvOS; add the page link.
extension ScreenChecksTests {
    /// (what, pattern, Apple page and the platforms it lists).
    static let notOnTVOS: [(name: String, pattern: String, page: String)] = [
        ("scrollContentBackground(_:)", #"\.scrollContentBackground\s*\("#,
         "https://developer.apple.com/documentation/swiftui/view/scrollcontentbackground(_:) (iOS, iPadOS, Mac Catalyst, macOS, visionOS, watchOS)"),
        ("containerBackground(_:for: .navigation)", #"containerBackground\s*\([^)]*for:\s*\.navigation\b"#,
         "https://developer.apple.com/documentation/swiftui/containerbackgroundplacement/navigation (iOS, iPadOS, Mac Catalyst, watchOS)"),
        // R414: read while looking for a grey for the task covers.
        ("UIColor.secondarySystemBackground", #"\bsecondarySystemBackground\b"#,
         "https://developer.apple.com/documentation/uikit/uicolor/secondarysystembackground (iOS, iPadOS, Mac Catalyst, visionOS)"),
    ]

    /// Each line of `source` (comments left out) that uses a call of `notOnTVOS`, as "line: name".
    static func notOnTVOSUses(in source: String) -> [String] {
        var found: [String] = []
        for (number, raw) in source.components(separatedBy: "\n").enumerated() {
            var line: Substring = Substring(raw)
            if let comment = raw.range(of: "//") { line = raw[..<comment.lowerBound] }
            let code: String = String(line)
            for entry in notOnTVOS where code.range(of: entry.pattern, options: .regularExpression) != nil {
                found.append("\(number + 1): \(entry.name)")
            }
        }
        return found
    }

    func testNoAppFileUsesASwiftUICallThatTVOSDoesNotHave() throws {
        // The project root as the R399 import check finds it (VP_PROJECT_ROOT when test-core.sh runs a copy of the package).
        guard let root = try projectRoot() else { return }
        let files: [(String, String)] = try swiftFiles(in: "App", root: root)
        XCTAssertGreaterThan(files.count, 50, "too few app files found under \(root.path)/App")
        for (path, source) in files {
            for use in Self.notOnTVOSUses(in: source) {
                let entry = Self.notOnTVOS.first { use.hasSuffix(": " + $0.name) }
                XCTFail("\(path):\(use) has no tvOS on its Apple page: \(entry?.page ?? "")")
            }
        }
    }

    /// The guard catches the line that failed compile check run #26 (App/Shared/SettingsPane.swift:375 on a10f582), and
    /// not the same words in a comment.
    func testTheLineOfRun26IsCaught() {
        let old: String = """
            content
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        """
        XCTAssertEqual(Self.notOnTVOSUses(in: old), ["2: scrollContentBackground(_:)"])
        XCTAssertEqual(Self.notOnTVOSUses(in: "// (`scrollContentBackground(.hidden)`) is not on tvOS"), [])
        XCTAssertEqual(Self.notOnTVOSUses(in: "    .containerBackground(.thinMaterial, for: .navigation)"), ["1: containerBackground(_:for: .navigation)"])
        XCTAssertEqual(Self.notOnTVOSUses(in: "    .containerBackground(.thinMaterial, for: .tabView)"), [])
        // R414: the iOS grey is caught; the system style the covers use is not.
        XCTAssertEqual(Self.notOnTVOSUses(in: "    .background(Color(uiColor: .secondarySystemBackground))"), ["1: UIColor.secondarySystemBackground"])
        XCTAssertEqual(Self.notOnTVOSUses(in: "    .background(BackgroundStyle().secondary, ignoresSafeAreaEdges: .all)"), [])
    }
}
