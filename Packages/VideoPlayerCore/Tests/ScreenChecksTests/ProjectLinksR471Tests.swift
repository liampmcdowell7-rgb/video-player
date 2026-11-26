import Foundation
import XCTest
@testable import ScreenChecks

/// R471 (112): every module a file in App/ (or TopShelf/) imports is either a package product listed as a dependency of
/// that target in project.yml, or an Apple framework the SDK links on its own. An import of a package product the target
/// does not link fails the archive ("no such module"); the Linux tests never compile the app, so this source check stands in.
extension ScreenChecksTests {
    /// Apple frameworks the app and the extension import today (all in the tvOS SDK; Swift links them automatically).
    static let systemModulesTheTargetsImport: Set<String> = [
        "AVFoundation", "AVKit", "CloudKit", "CoreGraphics", "CoreMedia", "CoreVideo", "CryptoKit", "Foundation", "ImageIO",
        "Network", "Observation", "QuartzCore", "Security", "SwiftUI", "TVServices", "TVUIKit", "UIKit", "os",
    ]

    /// The `product:` names in one target's block of project.yml (from its `  Name:` line to the next target line).
    static func linkedProducts(ofTarget name: String, in spec: String) -> Set<String> {
        var inside = false
        var products: Set<String> = []
        for raw in spec.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let isTargetLine = line.hasPrefix("  ") && !line.hasPrefix("   ") && line.hasSuffix(":")
            if isTargetLine { inside = line == "  \(name):"; continue }
            if !line.hasPrefix(" ") && !line.isEmpty && !line.hasPrefix("#") { inside = false }
            guard inside else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("product: ") { products.insert(String(trimmed.dropFirst("product: ".count))) }
        }
        return products
    }

    /// Every module named by an `import` line in the Swift files under `folder` (relative to the project root).
    func importedModules(under folder: String) throws -> Set<String> {
        var roots: [URL] = []
        if let root = ProcessInfo.processInfo.environment["VP_PROJECT_ROOT"], !root.isEmpty {
            roots.append(URL(fileURLWithPath: root))
        }
        roots.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
        let base = try XCTUnwrap(roots.map { $0.appendingPathComponent(folder) }
            .first { FileManager.default.fileExists(atPath: $0.path) }, "\(folder) not found")
        var modules: Set<String> = []
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil))
        for case let url as URL in walker where url.pathExtension == "swift" {
            for raw in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
                var words = raw.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
                while let first = words.first, first.hasPrefix("@") { words.removeFirst() }
                guard words.count >= 2, words[0] == "import" else { continue }
                modules.insert(String(words[1].split(separator: ".").first ?? ""))
            }
        }
        return modules
    }

    func testEveryModuleTheAppImportsIsLinked() throws {
        guard let spec = try appSource("project.yml") else { return }
        let app = Self.linkedProducts(ofTarget: "VideoPlayer", in: spec)
        XCTAssertTrue(app.contains("AppLogic") && app.contains("SourcePlex"), "project.yml's app block was not read: \(app.sorted())")
        let unlinked = try importedModules(under: "App").subtracting(app).subtracting(Self.systemModulesTheTargetsImport)
        XCTAssertEqual(unlinked.sorted(), [], "App/ imports a module the app target does not link (project.yml, R471 (112))")

        let topShelf = Self.linkedProducts(ofTarget: "TopShelf", in: spec)
        XCTAssertEqual(topShelf, ["UserData"])
        let shelfUnlinked = try importedModules(under: "TopShelf").subtracting(topShelf)
            .subtracting(Self.systemModulesTheTargetsImport)
        XCTAssertEqual(shelfUnlinked.sorted(), [], "TopShelf/ imports a module the extension does not link")
    }

    /// The reader itself: a module missing from a target's block is reported.
    func testTheLinkedProductReaderStopsAtTheNextTarget() {
        let spec = "targets:\n  VideoPlayer:\n    dependencies:\n      - package: P\n        product: A\n  TopShelf:\n"
            + "    dependencies:\n      - package: P\n        product: B\nschemes:\n  X:\n        product: C\n"
        XCTAssertEqual(Self.linkedProducts(ofTarget: "VideoPlayer", in: spec), ["A"])
        XCTAssertEqual(Self.linkedProducts(ofTarget: "TopShelf", in: spec), ["B"])
    }
}
