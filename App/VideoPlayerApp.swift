import SwiftUI

/// Entry point. A SwiftUI `App` with a `WindowGroup` is the scene-based life cycle: the system creates the scene,
/// there is no app-delegate window code to migrate (docs/DESIGN_SYSTEM.md, "Scene life cycle").
@main
struct VideoPlayerApp: App {
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services)
        }
    }
}
