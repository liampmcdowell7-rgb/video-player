// Fixture: covered by a local typealias, and a qualified use.
@testable import Mod
typealias LibraryItem = Mod.LibraryItem
func ids(_ items: [LibraryItem]) -> Int { items.count }
let shared = Mod.SharedClass()
