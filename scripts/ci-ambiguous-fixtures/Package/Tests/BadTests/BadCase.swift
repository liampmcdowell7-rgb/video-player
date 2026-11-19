// Fixture: bare uses of names Apple also declares, no typealias.
@testable import Mod
func ids(_ items: [LibraryItem]) -> Int { items.count }
struct Conformer: SharedProto {}
