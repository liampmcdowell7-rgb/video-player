import XCTest
@testable import ScreenChecks

/// R391 (owner's review of the screenshot run on fd9731f, item 14): one check for each shared fault, from the app's source
/// (structure only: nothing is compiled or run on tvOS here) and from invented element frames (FIXTURES).
extension ScreenChecksTests {
    /// The body of `struct <name>` in `source`.
    private func body(of name: String, in source: String) throws -> String {
        let start: String.Index = try XCTUnwrap(source.range(of: "struct \(name)")?.lowerBound, "no \(name)")
        return String(try XCTUnwrap(Self.braceBody(of: source, after: start), "the body of \(name)"))
    }

    // MARK: Shared fault 1: the badge gap

    /// The badge rows give their spacing (`BadgeSpacing`), take no default stack spacing, and hold nothing that spreads
    /// them: no `Spacer`, no `maxWidth: .infinity`, no fixed-width slot.
    func testBadgeRowsGiveTheirSpacingAndHoldNothingThatSpreadsThem() throws {
        guard let parts = try appSource("App/Shared/ProductPageParts.swift"),
              let episodes = try appSource("App/Features/Shows/EpisodeCards.swift"),
              let home = try appSource("App/Features/Home/HomeFeaturedView.swift") else { return }
        // The values themselves (8 and 12 pt, the owner's range) are checked in AppLogicTests, VisualSpacingTests.
        let groups: String = try body(of: "BadgeGroups", in: parts)
        XCTAssertTrue(groups.contains("HStack(spacing: CGFloat(BadgeSpacing.inGroup))"), "BadgeGroups does not give its spacing:\n\(groups)")
        let line: String = try body(of: "ProductMetadataLine", in: parts)
        XCTAssertTrue(line.contains("HStack(spacing: CGFloat(BadgeSpacing.afterText))"), "the metadata line does not give its spacing:\n\(line)")
        for (name, text) in [("BadgeGroups", groups), ("ProductMetadataLine", line), ("BadgeRow", try body(of: "BadgeRow", in: parts)),
                             ("BadgeOutline", try body(of: "BadgeOutline", in: parts))] {
            XCTAssertFalse(text.contains("HStack {"), "\(name) has a stack at the system's default spacing")
            XCTAssertFalse(text.contains("Spacer("), "\(name) holds a Spacer")
            XCTAssertFalse(text.contains("maxWidth: .infinity"), "\(name) fills the width")
        }
        XCTAssertTrue(try body(of: "BadgeOutline", in: parts).contains(".fixedSize()"), "a badge is not at its own width")

        let card: String = try body(of: "EpisodeCard", in: episodes)
        // R453: the card's caption is one line "number. title"; the runtime and the tag chips are no longer on the card.
        XCTAssertFalse(card.contains("BadgeRow("), "the episode card draws tag chips again (R453)")
        XCTAssertTrue(card.contains("cardCaption"), "the episode card's caption is not the one line \"number. title\" (R453)")
        XCTAssertFalse(card.contains("HStack {"), "the episode card has a stack at the system's default spacing")
        XCTAssertFalse(card.contains("SymbolColumn("), "the episode card still keeps a fixed slot for the watched mark")
        let featured: String = try body(of: "HomeFeaturedView", in: home)
        XCTAssertFalse(featured.contains("HStack {"), "Home's metadata line has a stack at the system's default spacing")
    }

    /// The fixture: three badges 8 and 12 pt apart pass; the run's own spread (65 and 72 pt) fails; badges of two
    /// different lines are never compared.
    func testBadgesCloseTogetherPassAndTheRunsSpreadFails() {
        func row(_ gaps: [Double], y: Double = 500) -> [(String, AXRect)] {
            var x: Double = 80
            var out: [(String, AXRect)] = []
            for (index, name) in ["4K", "Dolby Vision", "Dolby Atmos"].enumerated() {
                let width: Double = index == 0 ? 50 : 170
                out.append((name, AXRect(x: x, y: y, width: width, height: 34)))
                x += width + (index < gaps.count ? gaps[index] : 0)
            }
            return out
        }
        let tight: CheckResult = ScreenRules.badgeGaps(badges: row([8, 12]))
        XCTAssertTrue(tight.passed, tight.text)
        XCTAssertTrue(tight.text.contains("gaps [8, 12]"), tight.text)
        let spread: CheckResult = ScreenRules.badgeGaps(badges: row([65, 72]))
        XCTAssertFalse(spread.passed, spread.text)
        XCTAssertTrue(spread.text.contains("“4K” and “Dolby Vision” are 65 pt apart"), spread.text)
        // Two lines far apart on the screen (the metadata line and the row on top of Information) are two rows.
        let twoLines: CheckResult = ScreenRules.badgeGaps(badges: row([8, 12], y: 500) + row([8, 12], y: 900))
        XCTAssertTrue(twoLines.passed, twoLines.text)
        XCTAssertTrue(ScreenRules.badgeGaps(badges: []).passed)
    }

    // MARK: Shared fault 2: the icon-to-label gap

    /// A list row's symbol and title are the system `Label`: no stack, frame or slot of ours between them, and no custom
    /// `LabelStyle` anywhere in the app. Add a Source has no row with a symbol (every row or none).
    func testListRowsUseTheSystemLabelWithNoFrameOrSpacingOfOurs() throws {
        guard let layout = try appSource("App/Shared/LayoutParts.swift"),
              let rowLabel = try appSource("App/Shared/RowLabel.swift"),
              let kinds = try appSource("App/Features/Sources/SourceKindListView.swift"),
              let kindRow = try appSource("App/Features/Sources/SourceKindRow.swift") else { return }
        let slot: String = try body(of: "SlotLabel", in: layout)
        XCTAssertTrue(slot.contains("Label {"), "SlotLabel is not the system Label:\n\(slot)")
        XCTAssertTrue(slot.contains("} icon: {"), "SlotLabel does not hand its symbol to the Label as the icon")
        XCTAssertFalse(slot.contains("HStack"), "SlotLabel still lays the symbol and title out in a stack of ours")
        XCTAssertFalse(slot.contains(".frame("), "SlotLabel still frames its symbol")
        XCTAssertFalse(slot.contains("@ScaledMetric"), "SlotLabel still keeps a symbol slot")
        // R396 (audit SF1): the gap is the shared value, set with the system's own Label modifier, never a number here.
        XCTAssertTrue(slot.contains(".labelIconToTitleSpacing(CGFloat(RowSpacing.iconToLabel))"), "SlotLabel does not take the shared icon-to-label gap")
        XCTAssertFalse(slot.contains("labelReservedIconWidth"), "SlotLabel reserves a symbol width of its own")
        XCTAssertFalse(layout.contains("struct SymbolColumn"), "the fixed symbol column is still there")
        XCTAssertTrue(try body(of: "RowLabel", in: rowLabel).contains("SlotLabel(title, systemImage: systemImage"), "RowLabel is not the shared label")
        // The old row fails the same checks.
        let old: String = "struct SlotLabel: View { @ScaledMetric var slot: CGFloat = 44\n var body: some View { HStack { Image(systemName: s).frame(width: slot, height: slot)\n Text(t) } } }"
        let oldBody: String = try body(of: "SlotLabel", in: old)
        XCTAssertTrue(oldBody.contains("HStack") && oldBody.contains(".frame(") && !oldBody.contains("Label {"))

        XCTAssertFalse(kinds.contains("systemImage:"), "a row of Add a Source has a symbol while the source types have none")
        XCTAssertFalse(kindRow.contains("systemImage:") || kindRow.contains("Image("), "a source type row has a symbol while the other rows have none")
    }

    // MARK: R396: one shared set of values, no per-screen numbers

    /// The shared row values (AppLogic `BadgeSpacing`, `RowSpacing`) are the only source of the badge gap, the action
    /// row's gap, the text column and the landscape shelf's column count: every view names the shared value, and the
    /// values themselves are inside what Apple's pictures measure (docs/AUDIT_VISUAL_TVAPP.md, section 1).
    func testTheViewsTakeTheSharedSpacingValuesAndTheValuesMatchApplesPictures() throws {
        guard let values = try appSource("Packages/VideoPlayerCore/Sources/AppLogic/VisualSpacing.swift"),
              let layout = try appSource("App/Shared/LayoutParts.swift"),
              let detail = try appSource("App/Features/Detail/ItemDetailContentView.swift"),
              let home = try appSource("App/Features/Home/HomeFeaturedView.swift"),
              let row = try appSource("App/Shared/CardRow.swift") else { return }
        func value(_ name: String) throws -> Double {
            let start: String.Index = try XCTUnwrap(values.range(of: "public static let \(name): ")?.upperBound, "no shared value \(name)")
            let rest: Substring = values[start...]
            let number: Substring = try XCTUnwrap(rest.range(of: " = ").map { rest[$0.upperBound...].prefix { $0.isNumber || $0 == "." } })
            return try XCTUnwrap(Double(number), "\(name) is not a number")
        }
        XCTAssertTrue((10.0...15.0).contains(try value("inGroup")), "badges: 10 to 15 pt on Apple's pages (B1, A4)")
        XCTAssertTrue((10.0...15.0).contains(try value("betweenGroups")), "badges: 10 to 15 pt on Apple's pages (B1, A4)")
        XCTAssertTrue((25.0...29.0).contains(try value("iconToLabel")), "list icon to label: about 25 to 29 pt (A3, A2)")
        XCTAssertTrue((22.0...27.0).contains(try value("betweenActions")), "action buttons: about 22 to 27 pt apart (A1, B1, A4)")
        XCTAssertTrue((650.0...658.0).contains(try value("textColumn")), "running text: about 650 pt wide at most (B1, A4)")
        XCTAssertEqual(try value("landscapeShelfColumns"), 5, "Continue Watching: five across (A1)")

        let actions: String = try body(of: "ActionRow", in: layout)
        XCTAssertTrue(actions.contains("var spacing: CGFloat? = CGFloat(RowSpacing.betweenActions)"), "the action row does not take the shared gap:\n\(actions)")
        XCTAssertTrue(layout.contains("buttonStyle(.bordered).buttonBorderShape(.circle)"), "the round action is not the system's bordered circle")
        XCTAssertEqual(detail.components(separatedBy: ".frame(maxWidth: CGFloat(RowSpacing.textColumn)").count - 1, 2, "the synopsis and its cover do not both take the shared text column")
        XCTAssertTrue(home.contains(".frame(maxWidth: CGFloat(RowSpacing.textColumn)"), "Home's synopsis line does not take the shared text column")
        XCTAssertTrue(home.contains("RowSpacing.featuredToShelf - RowSpacing.stackGap"), "Home's gap to the first shelf is not the shared value")
        XCTAssertTrue(row.contains("count: RowSpacing.landscapeShelfColumns"), "the landscape shelf does not take the shared column count")
        // Every secondary action of the pages is a round icon button; Play is the one capsule (R471 item 3: the system
        // bordered capsule, light only when focused, as in the reference frames, so no prominent button is left).
        XCTAssertEqual(detail.components(separatedBy: "PlayCapsuleButton(").count - 1, 1, "the movie page has more or fewer than one Play capsule")
        XCTAssertEqual(detail.components(separatedBy: ".buttonStyle(.borderedProminent)").count - 1, 0, "the movie page still has a prominent button")
        XCTAssertFalse(detail.contains("ActionLabel(\"More\", systemImage: \"ellipsis\")"), "More is still a text button on the movie page")
        XCTAssertFalse(home.contains("ActionLabel(\"More\", systemImage: \"ellipsis\")"), "More is still a text button on Home")
        for name in ["Start Over", "Go to Show", "Fix Match", "How This Was Sorted"] {
            XCTAssertTrue(detail.contains("\"\(name)\""), "the action “\(name)” is no longer on the movie page")
        }
    }

    // MARK: Shared fault 3: toolbar buttons of one size

    /// Every toolbar control of Movies and Shows draws the shared `ToolbarSymbol`, and that draws every symbol in ONE
    /// square, so the controls have one size.
    func testEveryToolbarControlDrawsItsSymbolInTheSameSquare() throws {
        guard let toolbar = try appSource("App/Shared/GridToolbar.swift"),
              let sort = try appSource("App/Features/Movies/SortFilterMenu.swift"),
              let saved = try appSource("App/Features/Movies/SavedViewsMenu.swift") else { return }
        let symbol: String = try body(of: "ToolbarSymbol", in: toolbar)
        XCTAssertTrue(symbol.contains(".frame(width: side, height: side)"), "the toolbar symbol has no one square:\n\(symbol)")
        XCTAssertTrue(symbol.contains("@ScaledMetric(relativeTo: .title2) private var side: CGFloat = SymbolSlot.toolbar"), "the square does not scale with the text size")
        XCTAssertTrue(symbol.contains(".labelStyle(.iconOnly)"), "the toolbar symbol is not the system's icon-only label")
        XCTAssertEqual(toolbar.components(separatedBy: "ToolbarSymbol(\"More\"").count - 1, 1, "More does not draw the shared symbol")
        XCTAssertEqual(sort.components(separatedBy: "ToolbarSymbol(").count - 1, 1, "Sort and Filter does not draw the shared symbol")
        XCTAssertEqual(saved.components(separatedBy: "ToolbarSymbol(").count - 1, 2, "Save View and Saved Views do not both draw the shared symbol")
        for (name, text) in [("GridToolbar", toolbar), ("SortFilterMenu", sort), ("SavedViewsMenu", saved)] {
            // The only image in a toolbar label is the one inside ToolbarSymbol.
            let images: Int = text.components(separatedBy: "Image(systemName:").count - 1
            XCTAssertEqual(images, name == "GridToolbar" ? 1 : 0, "\(name) draws a toolbar symbol outside ToolbarSymbol")
        }
        // R413: the controls are one full-width focus section on the page (no longer the system toolbar group), so Up from
        // any card of the first row reaches them.
        // R443: the row is the grid's header inside its scroll view (environment `libraryGridHeader`), no longer pinned by
        // `safeAreaInset`, so posters never scroll under the buttons; it is still one full-width focus section.
        XCTAssertTrue(toolbar.contains("environment(\\.libraryGridHeader"), "the controls are not the header of the grid")
        XCTAssertFalse(toolbar.contains("safeAreaInset(edge: .top) {"), "the controls are pinned above the grid again (posters scroll under them)")
        XCTAssertTrue(toolbar.contains(".frame(maxWidth: .infinity, alignment: .trailing)\n            .focusSection()"), "the controls' row is not one full-width focus section")
        XCTAssertFalse(toolbar.contains("ToolbarItemGroup("), "the controls are back in the system toolbar, which Up from the grid did not reach (run #27)")
    }

    /// The fixture: three controls of one size pass; the run's own sizes (108 x 66, 98 x 81, 100 x 63) fail.
    func testEqualToolbarButtonsPassAndTheRunsSizesFail() {
        let names: [String] = ["Sort and Filter", "Saved Views", "More"]
        let equal: [(String, AXRect)] = names.enumerated().map { (index: Int, name: String) -> (String, AXRect) in
            (name, AXRect(x: 1400 + Double(index) * 150, y: 60, width: 90, height: 66))
        }
        XCTAssertTrue(ScreenRules.equalSizes(items: equal).passed)
        let sizes: [(Double, Double)] = [(108, 66), (98, 81), (100, 63)]
        let run: [(String, AXRect)] = names.enumerated().map { (index: Int, name: String) -> (String, AXRect) in
            (name, AXRect(x: 1400 + Double(index) * 160, y: 60, width: sizes[index].0, height: sizes[index].1))
        }
        let result: CheckResult = ScreenRules.equalSizes(items: run)
        XCTAssertFalse(result.passed, result.text)
        XCTAssertTrue(result.text.contains("“Saved Views” is 98 x 81, “Sort and Filter” is 108 x 66"), result.text)
        XCTAssertTrue(result.text.contains("“More” is 100 x 63"), result.text)
        // A focused control may be drawn a little larger; within the tolerance it still passes.
        var focused: [(String, AXRect)] = equal
        focused[1].1 = AXRect(x: 1550, y: 59.5, width: 91, height: 67)
        XCTAssertTrue(ScreenRules.equalSizes(items: focused).passed)
        XCTAssertTrue(ScreenRules.equalSizes(items: []).passed)
    }
}

/// R399: the tvOS compile of 406ad8c failed on "cannot find 'ProductPageSpacing' in scope" in App/Shared/GridToolbar.swift:
/// the file used an AppLogic type without `import AppLogic`. `scripts/parse-app.sh` is `swiftc -parse` (syntax only), so
/// no Linux check saw it. This test reads the app's sources as text: every file under App/ that names a public type of the
/// AppLogic package (the spacing enums of VisualSpacing.swift first) must import AppLogic. Names the app target declares
/// itself are left out (the app's own type of that name is meant). Comments and
/// string literals on one line are skipped too ("Artwork" in a toggle title is not the type).
extension ScreenChecksTests {
    /// The repository root (VP_PROJECT_ROOT, else up from this file), as `appSource`.
    func projectRoot() throws -> URL? {
        guard try appSource("App/Shared/GridToolbar.swift") != nil else { return nil }
        if let root = ProcessInfo.processInfo.environment["VP_PROJECT_ROOT"], !root.isEmpty,
           FileManager.default.fileExists(atPath: root + "/App/Shared/GridToolbar.swift") {
            return URL(fileURLWithPath: root)
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Every `.swift` file below `directory`, as (path relative to `root`, text).
    func swiftFiles(in directory: String, root: URL) throws -> [(String, String)] {
        let base: URL = root.appendingPathComponent(directory)
        guard let walker = FileManager.default.enumerator(atPath: base.path) else { return [] }
        var out: [(String, String)] = []
        while let relative = walker.nextObject() as? String {
            guard relative.hasSuffix(".swift") else { continue }
            out.append((directory + "/" + relative, try String(contentsOf: base.appendingPathComponent(relative), encoding: .utf8)))
        }
        return out.sorted { (a: (String, String), b: (String, String)) -> Bool in a.0 < b.0 }
    }

    /// The type names `source` declares; `publicOnly` keeps the TOP-LEVEL `public` ones (a package's API that a file can
    /// name bare: a nested type such as `TopShelfBuilder.Artwork` is reached through its outer type).
    static func declaredTypes(in source: String, publicOnly: Bool) -> Set<String> {
        let kinds: Set<String> = ["struct", "enum", "class", "protocol", "actor", "typealias"]
        let modifiers: Set<String> = ["public", "private", "fileprivate", "internal", "final", "indirect", "open", "package"]
        var names: Set<String> = []
        for line in source.components(separatedBy: "\n") {
            if publicOnly, let first = line.first, first == " " || first == "\t" { continue }
            let words: [String] = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == ":" || $0 == "<" || $0 == "{" || $0 == "=" })
                .map(String.init)
            var index: Int = 0
            var isPublic: Bool = false
            while index < words.count, modifiers.contains(words[index]) {
                if words[index] == "public" || words[index] == "open" { isPublic = true }
                index += 1
            }
            guard index + 1 < words.count, kinds.contains(words[index]) else { continue }
            if publicOnly && !isPublic { continue }
            names.insert(words[index + 1])
        }
        return names
    }

    /// The AppLogic names `source` uses without importing AppLogic (empty when it imports it or uses none).
    static func missingAppLogicImport(source: String, appLogicTypes: Set<String>, appTypes: Set<String>) -> [String] {
        let lines: [String] = source.components(separatedBy: "\n")
        if lines.contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("import AppLogic") }) { return [] }
        let code: String = lines.map { (line: String) -> String in
            var code: String = line
            if let comment = code.range(of: "//") { code = String(code[..<comment.lowerBound]) }
            // One-line string literals: every other run between quotes.
            return code.components(separatedBy: "\"").enumerated().filter { $0.offset % 2 == 0 }.map { $0.element }.joined(separator: " ")
        }.joined(separator: "\n")
        let identifier: CharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        let tokens: Set<String> = Set(code.components(separatedBy: identifier.inverted).filter { !$0.isEmpty })
        return tokens.intersection(appLogicTypes.subtracting(appTypes)).sorted()
    }

    func testEveryAppFileThatUsesAnAppLogicTypeImportsAppLogic() throws {
        guard let root = try projectRoot() else { return }
        let logic: [(String, String)] = try swiftFiles(in: "Packages/VideoPlayerCore/Sources/AppLogic", root: root)
        var logicTypes: Set<String> = []
        for (_, text) in logic { logicTypes.formUnion(Self.declaredTypes(in: text, publicOnly: true)) }
        let spacing: String = try XCTUnwrap(logic.first { $0.0.hasSuffix("/VisualSpacing.swift") }?.1, "no VisualSpacing.swift")
        let spacingTypes: Set<String> = Self.declaredTypes(in: spacing, publicOnly: true)
        XCTAssertTrue(spacingTypes.isSuperset(of: ["BadgeSpacing", "RowSpacing", "ProductPageSpacing"]), "the spacing enums moved: \(spacingTypes.sorted())")
        XCTAssertTrue(logicTypes.isSuperset(of: spacingTypes), "the AppLogic list misses the spacing enums")

        let app: [(String, String)] = try swiftFiles(in: "App", root: root)
        XCTAssertGreaterThan(app.count, 50, "too few app files found under \(root.path)/App")
        var appTypes: Set<String> = []
        for (_, text) in app { appTypes.formUnion(Self.declaredTypes(in: text, publicOnly: false)) }
        XCTAssertTrue(appTypes.intersection(spacingTypes).isEmpty, "the app target declares a spacing enum of its own: \(appTypes.intersection(spacingTypes).sorted())")

        var problems: [String] = []
        for (path, text) in app {
            let missing: [String] = Self.missingAppLogicImport(source: text, appLogicTypes: logicTypes, appTypes: appTypes)
            if !missing.isEmpty { problems.append("\(path) uses \(missing.joined(separator: ", ")) without import AppLogic") }
        }
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "\n"))
    }

    /// The fixture: GridToolbar.swift as it was at 406ad8c (no `import AppLogic`) fails; with the import it passes; a
    /// name the app declares itself, or one only in a comment, does not count.
    func testTheMissingImportOf406ad8cIsCaught() {
        let logic: Set<String> = ["ProductPageSpacing", "BadgeSpacing", "StatusText"]
        let broken: String = "import SwiftUI\n\nstruct GridCountLine: View {\n    var body: some View {\n        Text(count).padding(.bottom, CGFloat(ProductPageSpacing.aboveFirstGridRow))\n    }\n}\n"
        XCTAssertEqual(Self.missingAppLogicImport(source: broken, appLogicTypes: logic, appTypes: []), ["ProductPageSpacing"])
        let fixed: String = broken.replacingOccurrences(of: "import SwiftUI\n", with: "import SwiftUI\nimport AppLogic\n")
        XCTAssertEqual(Self.missingAppLogicImport(source: fixed, appLogicTypes: logic, appTypes: []), [])
        let own: String = "import SwiftUI\n// BadgeSpacing is AppLogic's\nstruct A: View { var body: some View { StatusText(text: \"\") } }\n"
        XCTAssertEqual(Self.missingAppLogicImport(source: own, appLogicTypes: logic, appTypes: ["StatusText"]), [])
        XCTAssertEqual(Self.declaredTypes(in: "public enum BadgeSpacing {\npublic struct Row: View {\nenum Hidden {\n    public struct Artwork {", publicOnly: true), ["BadgeSpacing", "Row"])
        // BackupSettingsView: "Artwork" as a toggle title is text, not AppLogic's type.
        XCTAssertEqual(Self.missingAppLogicImport(source: "SettingToggle(\"Artwork\", isOn: $on)", appLogicTypes: ["Artwork"], appTypes: []), [])
    }
}
