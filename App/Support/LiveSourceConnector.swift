import Foundation
import VideoPlayerCore
import UserData
import AppLogic
import SourceOneDrive

/// Opens a connection for the setup flow: the same builder the saved sources use, then `authenticate()` and one folder listing,
/// so "Connected" means the server really answered. A certificate or host key the user has not approved is never accepted: it
/// comes back as an outcome and the screen asks (docs/SOURCES_WIRING.md). Nothing here logs a password or token.
struct LiveSourceConnector: SourceConnecting {
    let deviceID: String
    /// Holds the pending device sign-in between "show the code" and "the user did it" (only used once an app registration exists).
    private let signIn = SignInSession()

    init(deviceID: String) { self.deviceID = deviceID }

    private var builder: SourceBuilder { SourceBuilder(deviceID: deviceID, tokenStore: nil) }

    func test(_ draft: SourceDraft, trustedFingerprint: String?) async throws -> ConnectionOutcome {
        if draft.kind == .oneDrive { return try await startSignIn(draft) }
        let definition = draft.definition(id: "setup-test", trustedFingerprint: trustedFingerprint ?? "")
        let pin = Self.pin(for: definition)
        do {
            let source = try builder.build(definition, secret: draft[.password].isEmpty ? nil : draft[.password], pin: pin)
            try await source.authenticate()
            _ = try await source.list("/")
            return .connected
        } catch {
            if let outcome = Self.outcome(for: error, pin: pin) { return outcome }
            throw error
        }
    }

    func finishSignIn(_ draft: SourceDraft) async throws -> ConnectionOutcome {
        guard draft.kind == .oneDrive else { throw SourceError.unsupported("This source type has no sign-in step.") }
        return try await signIn.finish()
    }

    func secretToSave(for draft: SourceDraft) async -> String? {
        if draft.kind == .oneDrive { return await signIn.tokenText() }
        return draft[.password].isEmpty ? nil : draft[.password]
    }

    // MARK: Trust

    private static func pin(for definition: UDSourceDefinition) -> CertificatePin? {
        guard let kind = SourceBuilder.trustKind(for: definition) else { return nil }
        let host = definition.host.isEmpty ? (URL(string: definition.path)?.host ?? "") : definition.host
        return CertificatePin(kind: kind, host: host, trusted: definition.hasApprovedFingerprint ? definition.trustedFingerprint : nil)
    }

    private static func outcome(for error: Error, pin: CertificatePin?) -> ConnectionOutcome? {
        let refusal = (error as? TrustRefusedError)?.refusal ?? pin?.lastRefusal
        guard let refusal else { return nil }
        switch refusal.kind {
        case .tlsCertificate: return .untrustedCertificate(host: refusal.host, fingerprintHex: refusal.presented)
        case .sshHostKey: return .unapprovedHostKey(host: refusal.host, fingerprint: refusal.presented)
        }
    }

    // MARK: Sign-in kinds

    private func startSignIn(_ draft: SourceDraft) async throws -> ConnectionOutcome {
        guard let clientID = SourceConfiguration.oneDriveClientID, !clientID.isEmpty else {
            throw ConnectorError(kindTitle: SourceCatalog.info(for: draft.kind).title,
                                 reason: .notIncluded("This type is blocked until an app registration exists."))
        }
        return try await signIn.start(clientID: clientID)
    }
}

/// The pending OneDrive sign-in (Microsoft device-code flow). Reference type so the connector (a struct) can hold it between two calls.
private final class SignInSession: @unchecked Sendable {
    private let lock = NSLock()
    private var flow: DeviceCodeFlow?
    private var challenge: DeviceCodeChallenge?
    private var tokens: OneDriveTokens?

    func start(clientID: String) async throws -> ConnectionOutcome {
        let flow = DeviceCodeFlow(configuration: OneDriveConfiguration(clientID: clientID), transport: URLSessionTransport())
        let challenge = try await flow.start()
        lock.withLock { self.flow = flow; self.challenge = challenge; self.tokens = nil }
        return .needsSignIn(DeviceSignIn(userCode: challenge.userCode, verificationAddress: challenge.verificationURI,
                                         expiresInSeconds: challenge.expiresIn))
    }

    func finish() async throws -> ConnectionOutcome {
        let pending = lock.withLock { (flow, challenge) }
        guard let flow = pending.0, let challenge = pending.1 else { throw SourceError.unsupported("Start the sign-in again.") }
        let tokens = try await flow.waitForTokens(challenge)
        lock.withLock { self.tokens = tokens }
        return .connected
    }

    func tokenText() async -> String? {
        guard let tokens = lock.withLock({ self.tokens }), let data = try? SecretsTokenStore.encoder.encode(tokens) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
