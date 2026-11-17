import Foundation
import VideoPlayerCore

/// Steps of the add-a-source flow.
enum SetupRoute: Hashable {
    case form(SourceKind)
    case discovery
    case discovered(DiscoveredSource)
}
