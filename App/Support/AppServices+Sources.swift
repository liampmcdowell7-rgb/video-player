import Foundation
import VideoPlayerCore
import UserData
import AppLogic

/// What the source screens do beyond adding a source: check one, and decide about a changed certificate or host key.
extension AppServices {
    /// Connects to a saved source and lists its top folder. Nil when it worked, otherwise the honest state to show.
    /// A refused certificate or key shows up in `trust` (and as the returned state), and nothing is trusted by this call.
    func checkSource(_ definition: UDSourceDefinition) async -> ErrorState? {
        do {
            let source = try sourceFactory.source(for: definition)
            try await source.authenticate()
            _ = try await source.list("/")
            trust.clear(sourceID: definition.id)
            return nil
        } catch {
            return SourceErrorText.state(for: error, doing: "Connect")
        }
    }

    /// The user read both fingerprints and chose to trust the new one. This is the only place a changed value is saved.
    func trustNewFingerprint(_ issue: TrustIssue) async {
        guard var definition = definitions.first(where: { $0.id == issue.sourceID }) else { return }
        definition.trustedFingerprint = issue.savedValueIfTrusted
        try? await definitionSaver.saveDefinition(definition)
        trust.clear(sourceID: issue.sourceID)
        libraryRevision += 1
        sourceAdded()
    }

    /// The user chose to keep blocking: nothing changes, the banner is dismissed until the next failed connection.
    func keepBlocking(_ issue: TrustIssue) {
        trust.clear(sourceID: issue.sourceID)
    }
}
