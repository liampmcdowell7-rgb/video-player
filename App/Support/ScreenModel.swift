import SwiftUI
import Observation

/// Holds one screen's value-type view model (from the AppLogic package) and publishes it to SwiftUI.
/// The view model's `mutating async` methods run on a copy that is written back when they finish, so no view ever
/// holds an exclusive borrow of shared state across an `await`. While a reload runs the previous content stays on
/// screen (the first load shows a spinner because the state is still `.idle`).
@MainActor
@Observable
final class ScreenModel<Screen: Sendable> {
    private(set) var screen: Screen

    init(_ screen: Screen) {
        self.screen = screen
    }

    func run(_ work: (inout Screen) async -> Void) async {
        var copy = screen
        await work(&copy)
        screen = copy
    }
}
