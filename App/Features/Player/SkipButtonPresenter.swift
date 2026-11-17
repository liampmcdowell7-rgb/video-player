import AVKit
import UIKit
import AppLogic

/// Shows the Skip Intro, Recap or Credits button as a contextual action of the system player (it appears while the
/// controls are hidden, bottom trailing). Set only while the playhead is inside the range; cleared when it leaves.
final class SkipButtonPresenter: SkipButtonPresenting, @unchecked Sendable {
    var controllerProvider: @MainActor () -> AVPlayerViewController? = { nil }

    func show(title: String, onPress: @escaping @Sendable () -> Void) {
        Task { @MainActor [controllerProvider] in
            let action = UIAction(title: title) { _ in onPress() }
            controllerProvider()?.contextualActions = [action]
        }
    }

    func hide() {
        Task { @MainActor [controllerProvider] in
            controllerProvider()?.contextualActions = []
        }
    }
}
