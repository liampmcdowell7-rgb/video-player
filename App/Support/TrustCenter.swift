import Foundation
import Observation
import VideoPlayerCore
import AppLogic

/// Which sources are currently refused because their certificate or host key is not the one the user approved. Screens read
/// `issues`; sources report into it from whatever thread their transport runs on.
@MainActor
@Observable
final class TrustCenter {
    private(set) var issues: [String: TrustIssue] = [:]

    func issue(for sourceID: String) -> TrustIssue? { issues[sourceID] }

    func report(sourceID: String, sourceName: String, refusal: TrustRefusal) {
        issues[sourceID] = TrustIssue(sourceID: sourceID, sourceName: sourceName, refusal: refusal)
    }

    func clear(sourceID: String) { issues[sourceID] = nil }
}
