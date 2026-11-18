import Foundation
import VideoPlayerCore
import LibraryIndex
import UserData
import AppLogic
import RemuxEngine
import SourceRangeProxy

/// Where the player should open one file: a link the system player can open itself, or a loopback address this app serves
/// from a source that has no link (SMB, NFS, SFTP, FTP) or whose certificate only this app has been told to trust.
enum PlaybackLocation: Equatable {
    case url(URL, headers: [String: String])
    case proxied(URL)

    var url: URL {
        switch self {
        case .url(let url, _): return url
        case .proxied(let url): return url
        }
    }
    var headers: [String: String] {
        if case .url(_, let headers) = self { return headers }
        return [:]
    }
}

/// Builds the live object for every saved source and hands out what playback needs. One place, so scanning, browsing and
/// playing all use the same pinned connection rules (docs/SOURCES_WIRING.md).
@MainActor
final class SourceFactory {
    private let secrets: MirroredSecrets
    private let ledger: UserDataLedger
    private let trust: TrustCenter
    private let builder: SourceBuilder
    private var proxy: SourceRangeProxy?

    init(secrets: MirroredSecrets, ledger: UserDataLedger, trust: TrustCenter, deviceID: String) {
        self.secrets = secrets
        self.ledger = ledger
        self.trust = trust
        self.builder = SourceBuilder(deviceID: deviceID, tokenStore: { [secrets] sourceID in
            SecretsTokenStore(secrets: secrets, sourceID: sourceID)
        })
    }

    /// The live source for a saved definition, or nil when this build cannot open that type (the reason is shown by the screens
    /// through `unavailableReason`). A refused certificate or host key is reported to the `TrustCenter`, never trusted.
    func makeSource(_ definition: UDSourceDefinition) -> (any MediaSource)? {
        try? source(for: definition)
    }

    /// Same as `makeSource`, with the reason when it cannot be built.
    func source(for definition: UDSourceDefinition) throws -> any MediaSource {
        #if DEBUG
        // The synthetic sample library of the UI-test screenshots; nil in every normal launch.
        if let sample = UITestMode.fixtureSource(for: definition) { return sample }
        #endif
        let secret = secrets.secret(for: definition.id)
        let pin = Self.pin(for: definition, trust: trust)
        return try builder.build(definition, secret: secret, pin: pin)
    }

    func unavailableReason(for definition: UDSourceDefinition) -> String? {
        do { _ = try source(for: definition); return nil }
        catch { return (error as? LocalizedError)?.errorDescription ?? "This source cannot be opened." }
    }

    private static func pin(for definition: UDSourceDefinition, trust: TrustCenter) -> CertificatePin? {
        guard let kind = SourceBuilder.trustKind(for: definition) else { return nil }
        let id = definition.id, name = definition.name
        let host = definition.host.isEmpty ? (URL(string: definition.path)?.host ?? "") : definition.host
        return CertificatePin(kind: kind, host: host,
                              trusted: definition.hasApprovedFingerprint ? definition.trustedFingerprint : nil) { refusal in
            Task { @MainActor in trust.report(sourceID: id, sourceName: name, refusal: refusal) }
        }
    }

    // MARK: Playback

    private func definition(for sourceID: String) throws -> UDSourceDefinition {
        guard let found = ledger.sourceDefinitions().first(where: { $0.id == sourceID }) else { throw PlaybackError.sourceUnavailable }
        return found
    }

    /// One file as random-access bytes (the converting player and the range proxy read through this).
    func byteReader(for file: StoredFile) async throws -> any ByteRangeReader {
        let definition = try definition(for: file.sourceID)
        let live = try source(for: definition)
        return try await MediaSourceReader.open(source: live, path: file.path)
    }

    /// What to hand the player for this file. Never starts anything for a source whose certificate or key is refused: the
    /// refusal is thrown (and shown) instead.
    func playbackLocation(for file: StoredFile) async throws -> PlaybackLocation {
        let definition = try definition(for: file.sourceID)
        let live = try source(for: definition)
        let access = try await live.playbackAccess(for: file.path)
        let pinnedTLS = SourceBuilder.trustKind(for: definition) == .tlsCertificate && definition.hasApprovedFingerprint
        switch access {
        case .url(let url, let headers) where !(pinnedTLS && url.scheme?.lowercased() == "https"):
            return .url(url, headers: headers)
        default:
            // No link, or a link only this app's connection is allowed to trust: serve the bytes on the loopback address.
            let reader = try await MediaSourceReader.open(source: live, path: file.path)
            stopProxies()
            let server = SourceRangeProxy()
            let url = try server.start(reader: reader, fileName: file.name)
            proxy = server
            return .proxied(url)
        }
    }

    func stopProxies() {
        proxy?.stop()
        proxy = nil
    }
}
