import SwiftUI

/// Entry point. A SwiftUI `App` with a `WindowGroup` is the scene-based life cycle: the system creates the scene,
/// there is no app-delegate window code to migrate (docs/DESIGN_SYSTEM.md, "Scene life cycle").
@main
struct VideoPlayerApp: App {
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            // The UI-test text-size override is applied per tab inside RootView, not here, so the system tab bar keeps the
            // simulator's own text size (#15 item 1.5).
            RootView()
                .environment(services)
        }
    }
}
