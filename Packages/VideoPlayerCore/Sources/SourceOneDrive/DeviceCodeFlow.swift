import Foundation
import VideoPlayerCore

/// OAuth 2.0 device authorization grant against the Microsoft identity platform.
/// Show `userCode` and `verificationURI` on the TV; the user signs in on a phone.
public struct DeviceCodeFlow: Sendable {
    private let configuration: OneDriveConfiguration
    private let transport: HTTPTransport
    private let sleep: OneDriveSleeper
    private let now: OneDriveClock

    public init(
        configuration: OneDriveConfiguration,
        transport: HTTPTransport,
        sleep: @escaping OneDriveSleeper = defaultOneDriveSleeper,
        now: @escaping OneDriveClock = { Date() }
    ) {
        self.configuration = configuration
        self.transport = transport
        self.sleep = sleep
        self.now = now
    }

    private func clientID() throws -> String {
        guard configuration.isRegistered, let id = configuration.clientID else { throw OneDriveError.needsAppRegistration }
        return id
    }

    private func endpoint(_ name: String) -> URL {
        configuration.loginBaseURL.appendingPathComponent(configuration.tenant)
            .appendingPathComponent("oauth2/v2.0/\(name)")
    }

    private func post(_ url: URL, _ pairs: [(String, String)]) async throws -> HTTPResponse {
        let request = HTTPRequest(
            url: url, method: "POST",
            headers: ["Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"],
            body: Form.encode(pairs))
        do { return try await transport.send(request) }
        catch let error as SourceError { throw error }
        catch { throw SourceError.transport(String(describing: error)) }
    }

    private struct DeviceResponse: Decodable {
        var device_code: String
        var user_code: String
        var verification_uri: String
        var expires_in: Int
        var interval: Int?
        var message: String?
    }

    private struct TokenResponse: Decodable {
        var access_token: String
        var refresh_token: String?
        var expires_in: Int
    }

    private struct ErrorResponse: Decodable { var error: String? }

    /// Step 1: ask for a code to show the user.
    public func start() async throws -> DeviceCodeChallenge {
        let id = try clientID()
        let response = try await post(endpoint("devicecode"), [
            ("client_id", id),
            ("scope", configuration.scopes.joined(separator: " "))
        ])
        guard response.statusCode == 200 else { throw failure(from: response) }
        guard let decoded = try? JSONDecoder().decode(DeviceResponse.self, from: response.body) else {
            throw SourceError.malformedResponse
        }
        return DeviceCodeChallenge(
            deviceCode: decoded.device_code, userCode: decoded.user_code,
            verificationURI: decoded.verification_uri, expiresIn: decoded.expires_in,
            interval: decoded.interval ?? 5, message: decoded.message)
    }

    /// Step 2: poll until the user has signed in (or declined, or the code expires).
    public func waitForTokens(_ challenge: DeviceCodeChallenge) async throws -> OneDriveTokens {
        let id = try clientID()
        var interval = max(1, challenge.interval)
        let deadline = now().addingTimeInterval(TimeInterval(challenge.expiresIn))
        while true {
            await sleep(TimeInterval(interval))
            if now() >= deadline { throw OneDriveError.deviceCodeExpired }
            let response = try await post(endpoint("token"), [
                ("grant_type", "urn:ietf:params:oauth:grant-type:device_code"),
                ("client_id", id),
                ("device_code", challenge.deviceCode)
            ])
            if response.statusCode == 200 { return try tokens(from: response, keeping: nil) }
            switch errorCode(response) {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            case "authorization_declined": throw OneDriveError.authorizationDeclined
            case "expired_token": throw OneDriveError.deviceCodeExpired
            case "bad_verification_code": throw OneDriveError.badVerificationCode
            default: throw failure(from: response)
            }
        }
    }

    /// Exchanges a refresh token for new tokens. The old refresh token is kept if none is returned.
    public func refresh(_ refreshToken: String) async throws -> OneDriveTokens {
        let id = try clientID()
        let response = try await post(endpoint("token"), [
            ("grant_type", "refresh_token"),
            ("client_id", id),
            ("refresh_token", refreshToken),
            ("scope", configuration.scopes.joined(separator: " "))
        ])
        if response.statusCode == 200 { return try tokens(from: response, keeping: refreshToken) }
        if errorCode(response) == "invalid_grant" { throw OneDriveError.notSignedIn }
        throw failure(from: response)
    }

    private func errorCode(_ response: HTTPResponse) -> String? {
        (try? JSONDecoder().decode(ErrorResponse.self, from: response.body))?.error
    }

    private func failure(from response: HTTPResponse) -> Error {
        if let code = errorCode(response) { return OneDriveError.authorizationFailed(code) }
        return SourceError.httpStatus(response.statusCode)
    }

    private func tokens(from response: HTTPResponse, keeping old: String?) throws -> OneDriveTokens {
        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: response.body) else {
            throw SourceError.malformedResponse
        }
        return OneDriveTokens(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token ?? old,
            expiresAt: now().addingTimeInterval(TimeInterval(decoded.expires_in)))
    }
}
