import XCTest
@testable import AppLogic

/// R470 (replaces R452's test): the contrast proof per PAGE and per TEXT BLOCK over real-looking artwork, no build.
///
/// R452 proved only that white text passes over white under the cover at FULL strength; it never asked whether the cover is
/// at full strength where the text is. The owner's photo of build 202611250008 (episode page) showed exactly that gap: the
/// series line and the title sat over the bright picture, above the cover. This model places each page's text blocks on a
/// 1080 pt screen, takes the cover's opacity at every point of every block (`ArtReadability.coverAlpha`, anchored where the
/// page anchors it), puts the picture under it (two profiles: pure white everywhere, and a photograph: white at the top,
/// mid grey from the middle down), and fails when any block falls below WCAG's ratio anywhere along its height.
///
/// Requirements: 4.5:1 for every block, 3:1 for the large title (WCAG 2.x 1.4.3; HIG Accessibility "Color and effects":
/// 4.5:1 for text up to 17 pt, 3:1 at 18 pt or bold).
///
/// Model limits (UNVERIFIED without a tvOS device): the block heights use HIG's tvOS type sizes times 1.25 for the line
/// height, a 16 pt stack gap, 86 pt buttons and a 60 pt top content inset; the real metrics may differ by some points. The
/// pass does not depend on them: once the cover is anchored at the column's top, every block below it is at full strength,
/// so only the order of the blocks matters, not their exact sizes. No darkening by the system material is counted (Apple
/// states none).
final class ArtReadabilityTests: XCTestCase {
    let a = ArtReadability.scrimMaxOpacity
    static let screen: Double = 1080
    static let topInset: Double = 60
    static let gap: Double = 16
    static let buttonHeight: Double = 86

    // MARK: the model

    /// A text block: its size (tvOS text-style point size), how many lines, whether it is the large title (3:1) and whether it
    /// is drawn in the secondary colour (the worse of the two).
    struct Block {
        let name: String
        let points: Double
        var lines: Int = 1
        var large: Bool = false
        var secondary: Bool = true
        var height: Double { points * 1.25 * Double(lines) }
    }

    /// HIG tvOS type sizes (Typography, tvOS table): Title 1 76, Headline 38, Callout 31, Body 29, Caption 2 23.
    static let titleLine = Block(name: "title", points: 76, large: true, secondary: false)
    static let buttons = Block(name: "buttons", points: buttonHeight / 1.25, secondary: false)

    struct Placed { let block: Block; let top: Double }

    /// A number with `digits` decimals (no `%@`, so nothing depends on Foundation's bridging on Linux).
    static func f(_ value: Double, _ digits: Int) -> String {
        guard value.isFinite else { return "\(value)" }
        var scale = 1.0
        for _ in 0..<digits { scale *= 10 }
        let r = (value * scale).rounded() / scale
        return digits == 0 ? "\(Int(r))" : "\(r)"
    }

    /// A column whose bottom is at `bottom` (points from the screen's top), its blocks stacked upward, or (when it is taller
    /// than the room) starting at `minTop` and growing down: the layout of a bottom-aligned hero with a minimum height.
    static func column(_ blocks: [Block], bottom: Double, minTop: Double) -> [Placed] {
        let total = blocks.map(\.height).reduce(0, +) + gap * Double(max(blocks.count - 1, 0))
        var y = max(bottom - total, minTop)
        return blocks.map { (b: Block) -> Placed in
            defer { y += b.height + gap }
            return Placed(block: b, top: y)
        }
    }

    /// The four pages that put text over artwork (Library, Search and the player: no text of ours over art; see R470).
    static var pages: [(name: String, blocks: [Placed])] {
        // Episode and movie pages: the hero is 0.8 of the page from the top inset, 40 pt under the buttons (ItemDetailContentView).
        // R471 (76): the blocks of R471 item 2's hero (overline, title, kind line, description, facts line, buttons); R470's
        // model still listed the earlier hero (content advice, info line, genres, a 3-line synopsis, time left).
        let productBottom = topInset + 0.8 * screen - 40
        let facts = Block(name: "facts line with two-line glyph badges (caption 2, 2 lines)", points: 23, lines: 2)
        let episode: [Block] = [
            Block(name: "series line (episode overline, headline)", points: 38),
            titleLine,
            Block(name: "kind line with rating box (callout)", points: 31),
            Block(name: "description (callout, \(HeroLines.descriptionLines) lines)", points: 31, lines: HeroLines.descriptionLines),
            facts,
            buttons,
        ]
        let movie: [Block] = Array(episode.dropFirst())
        // Show and season page: the hero is only 0.30 of the page (InfoBlockLayout.showHeroFraction) but as tall as its content.
        let show: [Block] = [
            titleLine,
            Block(name: "kind line with rating box (callout)", points: 31),
            Block(name: "content advice (caption 2)", points: 23),
            Block(name: "description (callout, \(HeroLines.descriptionLines) lines)", points: 31, lines: HeroLines.descriptionLines),
            facts,
            buttons,
        ]
        let showBottom = topInset + InfoBlockLayout.showHeroFraction * screen - 40
        // Home: the featured area is 0.8 of the screen (HomeFeaturedLayout), about 85 pt above the first shelf's header.
        let home: [Block] = [
            titleLine,
            Block(name: "kind line with rating box (callout)", points: 31),
            Block(name: "synopsis (callout, \(HomeFeatured.synopsisLines) lines)", points: 31, lines: HomeFeatured.synopsisLines),
            buttons,
        ]
        let homeBottom = topInset + 0.8 * screen - 85
        return [
            ("episode", column(episode, bottom: productBottom, minTop: topInset)),
            ("movie", column(movie, bottom: productBottom, minTop: topInset)),
            ("show / season", column(show, bottom: showBottom, minTop: topInset)),
            ("home hero", column(home, bottom: homeBottom, minTop: topInset)),
        ]
    }

    /// The picture's brightness (sRGB grey) at `y`, a share of the screen height.
    enum Profile: String, CaseIterable {
        case white = "pure white"
        case photo = "photo: white top, mid grey middle"

        func brightness(at y: Double) -> Double {
            switch self {
            case .white: return 1
            case .photo:
                if y < 0.35 { return 1 }
                if y < 0.55 { return 1 - 0.5 * (y - 0.35) / 0.2 }
                return 0.5
            }
        }
    }

    /// The worst contrast of `block` (top at `top` points) under a cover with opacity `alpha(y)`, sampled every point.
    static func worst(_ block: Block, top: Double, profile: Profile, alpha: (Double) -> Double) -> (ratio: Double, at: Double) {
        var worst: (ratio: Double, at: Double) = (.infinity, top)
        var y = top
        while y <= top + block.height {
            let share = y / screen
            let opacity = alpha(share)
            let ratio = block.secondary
                ? ArtReadability.secondaryContrast(backdrop: profile.brightness(at: share), opacity: opacity)
                : ArtReadability.primaryContrast(backdrop: profile.brightness(at: share), opacity: opacity)
            if ratio < worst.ratio { worst = (ratio, y) }
            y += 1
        }
        return worst
    }

    /// Each block of `page` against each profile; the failures, and a printed table.
    static func check(_ page: (name: String, blocks: [Placed]), label: String, alpha: (Double) -> Double) -> [String] {
        var failures: [String] = []
        for profile in Profile.allCases {
            for placed in page.blocks {
                let need = placed.block.large ? 3.0 : 4.5
                let w = worst(placed.block, top: placed.top, profile: profile, alpha: alpha)
                let line = "\(label) | \(page.name) | \(profile.rawValue) | \(placed.block.name) | top \(f(placed.top, 0)) h "
                    + "\(f(placed.block.height, 0)) | worst \(f(w.ratio, 2)):1 at y \(f(w.at, 0)) (cover \(f(alpha(w.at / screen), 2))) "
                    + "| needs \(f(need, 1))"
                print("R470 " + line + (w.ratio >= need ? " | pass" : " | FAIL"))
                if w.ratio < need { failures.append(line) }
            }
        }
        return failures
    }

    /// The cover as the app draws it now: anchored at the column's top (the first block), eased, 0.25 of the screen.
    static func coverNow(textTop: Double) -> (Double) -> Double {
        let start = ArtReadability.coverStart(textTop: textTop, height: screen)
        return { ArtReadability.coverAlpha(at: $0, start: start) }
    }

    /// The cover before R470: anchored at the TITLE's top, start clamped at 0, two linear stops over 0.12 of the screen.
    static func coverBefore(titleTop: Double) -> (Double) -> Double {
        let start = min(max(titleTop / screen - 0.12, 0), 1), full = titleTop / screen
        return { (y: Double) -> Double in
            if y <= start { return 0 }
            if y >= full || full <= start { return 0.80 }
            return 0.80 * (y - start) / (full - start)
        }
    }

    // MARK: the proof

    func testEveryTextBlockOfEveryPagePassesOverWhiteAndAPhotograph() {
        var failures: [String] = []
        for page in Self.pages {
            let textTop = page.blocks.first!.top
            failures += Self.check(page, label: "now", alpha: Self.coverNow(textTop: textTop))
        }
        XCTAssertTrue(failures.isEmpty, "blocks below the required contrast:\n" + failures.joined(separator: "\n"))
    }

    /// The model is not vacuous: the cover before R470 fails the episode's series line, as the owner's photo showed.
    func testTheCoverBeforeR470FailsTheEpisodeSeriesLine() {
        let episode = Self.pages.first { $0.name == "episode" }!
        let titleTop = episode.blocks.first { $0.block.name == "title" }!.top
        let failures = Self.check(episode, label: "before", alpha: Self.coverBefore(titleTop: titleTop))
        XCTAssertTrue(failures.contains { $0.contains("series line") }, "the old cover should fail the series line")
    }

    /// The photo's title too: R452 kept the LARGEST top seen, i.e. the title's top before the details arrived (no advice, genres,
    /// synopsis or time left yet, so the bottom-aligned column was shorter and the title lower). Under that stale cover the
    /// title of the full page is over the bare picture. This is the WORST case of that fault (nothing but the info line had
    /// arrived); the photo lies between it and the case above (its description was readable, "TV-MA 1080p" borderline).
    func testTheStaleAnchorBeforeR470FailsTheEpisodeTitle() {
        let episode = Self.pages.first { $0.name == "episode" }!
        let early = Self.column([episode.blocks[0].block, Self.titleLine,
                                 Block(name: "info line (callout)", points: 31), Self.buttons],
                                bottom: Self.topInset + 0.8 * Self.screen - 40, minTop: Self.topInset)
        let staleTitleTop = early[1].top
        print("R470 stale | title top before the details: \(Self.f(staleTitleTop, 0)) pt; after: \(Self.f(episode.blocks[1].top, 0)) pt")
        let failures = Self.check(episode, label: "before, stale", alpha: Self.coverBefore(titleTop: staleTitleTop))
        XCTAssertTrue(failures.contains { $0.contains("| title |") }, "the stale cover should fail the title")
    }

    /// The picture stays clear above the text: no cover at all above one ramp over the column's top.
    func testThePictureIsClearAboveTheRamp() {
        for page in Self.pages {
            let textTop = page.blocks.first!.top
            let start = ArtReadability.coverStart(textTop: textTop, height: Self.screen)
            print("R470 clear | \(page.name) | text top \(Self.f(textTop, 0)) pt | cover starts at \(Self.f(start * Self.screen, 0)) pt "
                  + "(\(Self.f(start, 3))) | full at \(Self.f((start + ArtReadability.rampFraction) * Self.screen, 0)) pt")
            if start > 0 {
                XCTAssertEqual(ArtReadability.coverAlpha(at: start * 0.99, start: start), 0, "\(page.name): cover above its start")
            }
            XCTAssertEqual(ArtReadability.coverAlpha(at: textTop / Self.screen, start: start), a, accuracy: 1e-9,
                           "\(page.name): the cover is not at full strength at the first line")
        }
    }

    // MARK: the drawn gradient

    func testTheStopsFollowTheCurveWithNoStep() {
        for textTop in [-50.0, 0, 30, 60, 200, 455, 700, 1000, 1080, 1300] {
            let start = ArtReadability.coverStart(textTop: textTop, height: Self.screen)
            let stops = ArtReadability.coverStops(start: start)
            XCTAssertGreaterThanOrEqual(stops.count, 2, "text top \(textTop)")
            XCTAssertEqual(stops.first?.location, 0, "text top \(textTop)")
            XCTAssertEqual(stops.last?.location, 1, "text top \(textTop)")
            for (p, q) in zip(stops, stops.dropFirst()) {
                XCTAssertLessThan(p.location, q.location, "text top \(textTop): locations must increase")
                XCTAssertLessThanOrEqual(q.alpha - p.alpha, 0.2 + 1e-9, "text top \(textTop): a visible step between stops")
                XCTAssertGreaterThanOrEqual(q.alpha, p.alpha - 1e-9, "text top \(textTop): the cover never gets lighter downward")
                XCTAssertEqual(q.alpha, ArtReadability.coverAlpha(at: q.location, start: start), accuracy: 1e-9)
            }
        }
    }

    func testTheEaseHasNoSlopeAtEitherEnd() {
        XCTAssertEqual(ArtReadability.ease(0), 0)
        XCTAssertEqual(ArtReadability.ease(1), 1)
        XCTAssertEqual(ArtReadability.ease(0.5), 0.5, accuracy: 1e-12)
        XCTAssertLessThan(ArtReadability.ease(0.01), 0.0001)
        XCTAssertGreaterThan(ArtReadability.ease(0.99), 0.9999)
    }

    func testTheCoverStartsOneRampAboveTheFirstLine() {
        XCTAssertEqual(ArtReadability.coverStart(textTop: 540, height: 1080), 0.5 - ArtReadability.rampFraction, accuracy: 1e-9)
        XCTAssertEqual(ArtReadability.coverStart(textTop: 50, height: 1080), 50.0 / 1080 - ArtReadability.rampFraction, accuracy: 1e-9)
        XCTAssertEqual(ArtReadability.coverStart(textTop: -100, height: 1080), -ArtReadability.rampFraction, accuracy: 1e-9)
        XCTAssertEqual(ArtReadability.coverStart(textTop: nil, height: 1080), ArtReadability.fallbackStart)
        XCTAssertEqual(ArtReadability.coverStart(textTop: 400, height: 0), ArtReadability.fallbackStart)
    }

    // MARK: kept from R452

    func testTheOpacityIsNoHigherThanTheProofNeeds() {
        // The smallest opacity in steps of 0.05 that passes secondary text over white is the constant.
        let needed = stride(from: 0.0, through: 1.0, by: 0.05).first { ArtReadability.secondaryContrast(backdrop: 1, opacity: $0) >= 4.5 }
        XCTAssertEqual(needed ?? -1, a, accuracy: 0.001)
    }

    func testAThinProgressBarKeepsThreeToOneOverWhite() {
        let ground = ArtReadability.covered(backdrop: 1, opacity: ArtReadability.progressScrimOpacity)
        XCTAssertGreaterThanOrEqual(ArtReadability.contrast(ArtReadability.luminance(grey: 1), ArtReadability.luminance(grey: ground)), 3)
    }
}
