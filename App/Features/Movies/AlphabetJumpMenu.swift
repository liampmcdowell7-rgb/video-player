import SwiftUI

/// One letter in the jump list and how many titles it holds.
struct AlphabetJumpEntry: Identifiable {
    let letter: String
    let count: Int
    var id: String { letter }
}

/// The letter jump list: one menu with "#" then A to Z. Only letters that have titles are listed, each with its count.
/// A native `Menu` (no side strip): the remote moves through it with the focus engine (PROVISIONAL; alternative: a
/// vertical index strip, which the system apps do not use on this platform).
struct AlphabetJumpMenu: View {
    let letters: [AlphabetJumpEntry]
    let onPick: (String) -> Void

    var body: some View {
        // R443 (owner's device test of 23 Nov 2026, "Jump to Letter" at about 27 to 30 s): it showed a faint half-transparent pill
        // with tiny text. Cause in the code: the label was our `ActionLabel` (a `FittingText` that measures its own width
        // inside `frame(maxHeight: .infinity)`), which in a menu row has no width to measure, so the text shrank to its
        // floor. Now the system's own menu row, `Menu(_:systemImage:content:)`, like Needs Review next to it. A submenu of a menu
        // is placed by the system (SwiftUI has no anchor or placement parameter for it), so where it opens is the system's;
        // the nearest alternative is a flat section in More (OPEN_QUESTIONS R443 (d)).
        Menu("Jump to Letter", systemImage: "textformat.abc") {
            ForEach(letters) { entry in
                Button("\(entry.letter) (\(entry.count))") {
                    onPick(entry.letter)
                }
            }
        }
        .accessibilityLabel("Jump to Letter")
        .accessibilityIdentifier(ControlID.jumpToLetter)
    }
}
