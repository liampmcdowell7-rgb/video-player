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
        Menu {
            ForEach(letters) { entry in
                Button {
                    onPick(entry.letter)
                } label: {
                    Text("\(entry.letter) (\(entry.count))")
                }
            }
        } label: {
            ActionLabel("Jump to Letter", systemImage: "textformat.abc")
        }
        .accessibilityLabel("Jump to Letter")
        .accessibilityIdentifier(ControlID.jumpToLetter)
    }
}
