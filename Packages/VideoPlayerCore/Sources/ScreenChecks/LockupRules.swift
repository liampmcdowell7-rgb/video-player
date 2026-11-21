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
}
