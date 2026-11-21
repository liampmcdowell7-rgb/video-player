import Foundation

/// R335 (PROVISIONAL, docs/HIG_AUDIT.md T1, T2): a portrait card is ONE lockup, the artwork and its caption inside the
/// focused button, as Apple's sample "Creating a tvOS media catalog app in SwiftUI" builds it ("Provide a separate `Image`
/// and `Text` view in the button's label closure"; "The button's title and any nearby section titles automatically move out
/// of the way of the button's image as it scales up on focus"). Before R335 the caption sat under a `.card` button,
/// outside it.
public extension ScreenRules {
    /// Passes when the caption (the StaticText with the card's title) lies inside the focused element's frame, with
    /// `tolerance` points of slack on every side (the focus lift can round the frames). A missing frame fails with its
    /// reason.
    static func captionInLockup(focused: AXRect?, caption: AXRect?, title: String, tolerance: Double = 4) -> CheckResult {
        guard let focused else {
            return CheckResult(passed: false, lines: ["no focused element", "LOCKUP NOT CHECKED: nothing has the focus"])
        }
        guard let caption else {
            return CheckResult(passed: false, lines: ["focused \(focused)", "caption \u{201C}\(title)\u{201D}: not found",
                                                      "LOCKUP NOT CHECKED: no caption"])
        }
        let inside: Bool = caption.x >= focused.x - tolerance && caption.maxX <= focused.maxX + tolerance
            && caption.y >= focused.y - tolerance && caption.maxY <= focused.maxY + tolerance
        let lines: [String] = ["focused \(focused)", "caption \u{201C}\(title)\u{201D} \(caption)",
                               inside ? "LOCKUP OK: the caption is inside the focused card"
                                      : "CAPTION OUTSIDE THE FOCUSED CARD: the title is not part of the lockup (R335)"]
        return CheckResult(passed: inside, lines: lines)
    }

    /// R360 (compile run of 21 Nov 2026, item 7): the focused card's title moves with the lifted artwork, as Apple's sample
    /// says the borderless lockup does ("automatically move out of the way of the button's image as it scales up on focus").
    /// Passes when the focused card's caption sits at least `minimumDrop` points lower than a resting card's caption in the
    /// same row. The run's tree reports a borderless button's frame as the artwork only (55-show-page-HIERARCHY), so
    /// `captionInLockup` cannot tell a moving title from a still one; this compares the captions themselves.
    static func captionMovesOnFocus(focusedCaption: AXRect?, restingCaption: AXRect?, title: String, minimumDrop: Double = 2) -> CheckResult {
        guard let focusedCaption, let restingCaption else {
            return CheckResult(passed: false, lines: ["caption \u{201C}\(title)\u{201D}: \(focusedCaption.map { "\($0)" } ?? "not found")",
                                                      "resting caption: \(restingCaption.map { "\($0)" } ?? "not found")",
                                                      "LOCKUP NOT CHECKED: a caption is missing"])
        }
        let drop: Double = focusedCaption.y - restingCaption.y
        let moved: Bool = drop >= minimumDrop
        var verdict: String = "LOCKUP OK: the focused title moved \(Int(drop.rounded())) pt down with the lifted artwork"
        if !moved { verdict = "TITLE DID NOT MOVE: the focused title is \(Int(drop.rounded())) pt from the resting titles (R360)" }
        return CheckResult(passed: moved, lines: ["focused caption \u{201C}\(title)\u{201D} \(focusedCaption)",
                                                  "resting caption \(restingCaption)", verdict])
    }
}
