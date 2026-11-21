import Foundation
import VideoPlayerCore

// Add a Source > Plex, as data and a small state machine (docs/PLEX_SOURCE.md sections 1 and 2; OPEN_QUESTIONS R302).
// The screen (App/Features/Sources/PlexSetupView.swift) only shows these types. The model never sees a token: the
// connector keeps the account token in the Keychain and hands out codes and server choices only.

/// The code to show while the owner signs in on another device.
public struct PlexCode: Equatable, Sendable {
    public var code: String
    public var linkText: String
    public var expiresAt: Date
    public init(code: String, linkText: String, expiresAt: Date) {
        self.code = code; self.linkText = linkText; self.expiresAt = expiresAt
    }
}

/// Errors the Plex setup flow tells apart (the live connector maps the client's errors onto these).
public enum PlexSetupError: Error, Equatable, Sendable {
    case codeExpired
}

/// The Plex account side of the setup flow. The real one lives in the app target (it talks to plex.tv and the Keychain).
public protocol PlexAccountConnecting: Sendable {
    /// Asks plex.tv for a new short code.
    func newCode() async throws -> PlexCode
    /// Returns once the owner entered the code on plex.tv/link, with the account token already stored in the Keychain.
    /// Throws `PlexSetupError.codeExpired` when the code ran out first.
    func waitForSignIn(_ code: PlexCode) async throws
}

public enum PlexSetupPhase: Equatable, Sendable {
    case gettingCode
    case code(PlexCode)
    case codeExpired
    case signedIn
    case failed(ErrorState)
}

/// Texts of the Plex sign-in page. HIG Managing accounts (read 20 Nov 2026), tvOS: "Prefer letting people use another device
/// to sign up or authenticate" and "Minimize data entry"; "Always identify the authentication method you offer"; "Explain the
/// benefits of creating an account ... Display this message in your sign-in view"; "Avoid using the term passcode".
public enum PlexSetupText {
    public static let signInTitle = "Sign In to Plex"
    public static func instruction(link: String) -> String {
        "On your phone or computer, go to \(link) and enter this code."
    }
    public static let why = "Signing in finds your Plex servers. Your Plex password is never entered on this Apple TV."
    public static let waiting = "Waiting for the code to be entered."
    public static let expired = "This code expired."
    public static let newCode = "Get a New Code"
    public static let gettingCode = "Getting a code."
    public static let signedIn = "Signed in to Plex."
}

public struct PlexSetupModel: Sendable {
    public let account: any PlexAccountConnecting
    public private(set) var phase: PlexSetupPhase = .gettingCode

    public init(account: any PlexAccountConnecting) { self.account = account }

    /// Gets a code; the screen calls `waitForSignIn()` next. Also the Get a New Code action.
    public mutating func requestCode() async {
        phase = .gettingCode
        do { phase = .code(try await account.newCode()) }
        catch { fail(error, doing: "get a sign-in code") }
    }

    /// Waits until the owner entered the code (polling is the connector's job) or the code ran out.
    public mutating func waitForSignIn() async {
        guard case .code(let code) = phase else { return }
        do {
            try await account.waitForSignIn(code)
            phase = .signedIn
        } catch PlexSetupError.codeExpired {
            phase = .codeExpired
        } catch is CancellationError {
            return
        } catch {
            fail(error, doing: "sign in to Plex")
        }
    }

    private mutating func fail(_ error: Error, doing what: String) {
        phase = .failed(SourceErrorText.state(for: error, doing: what))
    }
}
