import XCTest
import VideoPlayerCore
@testable import SourceOneDrive

// All responses are hand-written from documentation (see OneDriveFixtures); nothing here ran against Microsoft.
final class DeviceCodeFlowTests: XCTestCase {
    private func flow(
        clientID: String? = Support.clientID, tenant: String = "consumers",
        transport: ScriptedTransport, sleeps: SleepLog, clock: TestClock
    ) -> DeviceCodeFlow {
        DeviceCodeFlow(
            configuration: OneDriveConfiguration(clientID: clientID, tenant: tenant),
            transport: transport, sleep: sleeps.sleeper, now: clock.clock)
    }

    /// First request returns the device code; later ones follow `tokenReplies` (the last repeats).
    private func scripted(_ tokenReplies: [HTTPResponse]) -> ScriptedTransport {
        ScriptedTransport { _, index in
            if index == 0 { return Support.json(OneDriveFixtures.deviceCode) }
            return tokenReplies[min(index - 1, tokenReplies.count - 1)]
        }
    }

    func testMissingClientIDIsNeedsAppRegistrationAndSendsNothing() async throws {
        let transport = ScriptedTransport { _, _ in Support.json("{}") }
        let sleeps = SleepLog(), clock = TestClock(Support.t0)
        for id in [nil, ""] as [String?] {
            let flow = flow(clientID: id, transport: transport, sleeps: sleeps, clock: clock)
            do { _ = try await flow.start(); XCTFail("should throw") }
            catch { XCTAssertEqual(error as? OneDriveError, .needsAppRegistration) }
            do { _ = try await flow.refresh("x"); XCTFail("should throw") }
            catch { XCTAssertEqual(error as? OneDriveError, .needsAppRegistration) }
        }
        XCTAssertEqual(transport.requests.count, 0)
        XCTAssertEqual(OneDriveConfiguration.blockedStatus, "blocked: needs an app registration")
        XCTAssertFalse(OneDriveConfiguration(clientID: nil).isRegistered)
    }

    func testStartRequestAndParsing() async throws {
        let transport = scripted([])
        let flow = flow(transport: transport, sleeps: SleepLog(), clock: TestClock(Support.t0))
        let challenge = try await flow.start()

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.absoluteString, "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode")
        XCTAssertEqual(request.headers["Content-Type"], "application/x-www-form-urlencoded")
        let body = Support.bodyText(request)
        XCTAssertTrue(body.contains("client_id=\(Support.clientID)"), body)
        XCTAssertTrue(body.contains("scope=Files.Read%20offline_access"), body)

        XCTAssertEqual(challenge.userCode, "FJH2K9XQ")
        XCTAssertEqual(challenge.verificationURI, "https://www.microsoft.com/link")
        XCTAssertEqual(challenge.expiresIn, 900)
        XCTAssertEqual(challenge.interval, 5)
        XCTAssertEqual(challenge.deviceCode, "DAQABAAEAAAD--DLA3VO7QrddgJg7WevrDEVICE")
        XCTAssertTrue(try XCTUnwrap(challenge.message).contains("FJH2K9XQ"))
    }

    func testTenantIsConfigurable() async throws {
        let transport = scripted([])
        let flow = flow(tenant: "organizations", transport: transport, sleeps: SleepLog(), clock: TestClock(Support.t0))
        _ = try await flow.start()
        XCTAssertEqual(transport.requests[0].url.absoluteString,
                       "https://login.microsoftonline.com/organizations/oauth2/v2.0/devicecode")
        XCTAssertEqual(OneDriveConfiguration(clientID: "x").tenant, "consumers")
    }

    func testPollingHonoursIntervalAndSlowDownThenReturnsTokens() async throws {
        let clock = TestClock(Support.t0)
        let sleeps = SleepLog(advancing: clock)
        let transport = scripted([
            Support.json(OneDriveFixtures.error("authorization_pending"), status: 400),
            Support.json(OneDriveFixtures.error("authorization_pending"), status: 400),
            Support.json(OneDriveFixtures.error("slow_down"), status: 400),
            Support.json(OneDriveFixtures.tokens)
        ])
        let flow = flow(transport: transport, sleeps: sleeps, clock: clock)
        let challenge = try await flow.start()
        let tokens = try await flow.waitForTokens(challenge)

        XCTAssertEqual(sleeps.values, [5, 5, 5, 10], "interval 5, then +5 after slow_down")
        XCTAssertEqual(transport.requests.count, 5)
        let poll = transport.requests[1]
        XCTAssertEqual(poll.url.absoluteString, "https://login.microsoftonline.com/consumers/oauth2/v2.0/token")
        let body = Support.bodyText(poll)
        XCTAssertTrue(body.contains("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code"), body)
        XCTAssertTrue(body.contains("device_code=DAQABAAEAAAD--DLA3VO7QrddgJg7WevrDEVICE"), body)
        XCTAssertTrue(body.contains("client_id=\(Support.clientID)"), body)

        XCTAssertEqual(tokens.accessToken, "ACCESS-1")
        XCTAssertEqual(tokens.refreshToken, "REFRESH-1")
        XCTAssertEqual(tokens.expiresAt, Support.t0.addingTimeInterval(25 + 3599))
    }

    func testTerminalErrorsMapToTypedErrors() async throws {
        let cases: [(String, OneDriveError)] = [
            ("authorization_declined", .authorizationDeclined),
            ("expired_token", .deviceCodeExpired),
            ("bad_verification_code", .badVerificationCode),
            ("invalid_client", .authorizationFailed("invalid_client"))
        ]
        for (code, expected) in cases {
            let clock = TestClock(Support.t0)
            let transport = scripted([Support.json(OneDriveFixtures.error(code), status: 400)])
            let flow = flow(transport: transport, sleeps: SleepLog(advancing: clock), clock: clock)
            let challenge = try await flow.start()
            do { _ = try await flow.waitForTokens(challenge); XCTFail("\(code) should throw") }
            catch { XCTAssertEqual(error as? OneDriveError, expected, code) }
        }
    }

    func testLocalDeadlineExpiresTheCode() async throws {
        let clock = TestClock(Support.t0)
        let sleeps = SleepLog(advancing: clock)
        let transport = scripted([Support.json(OneDriveFixtures.error("authorization_pending"), status: 400)])
        let flow = flow(transport: transport, sleeps: SleepLog(advancing: clock), clock: clock)
        _ = sleeps
        let challenge = try await flow.start()
        // expires_in is 900 s; make each wait 400 s long so the deadline passes after 3 sleeps.
        let slow = DeviceCodeFlow(
            configuration: OneDriveConfiguration(clientID: Support.clientID), transport: transport,
            sleep: { _ in clock.advance(400) }, now: clock.clock)
        do { _ = try await slow.waitForTokens(challenge); XCTFail("should expire") }
        catch { XCTAssertEqual(error as? OneDriveError, .deviceCodeExpired) }
        XCTAssertEqual(transport.requests.count, 1 + 2, "two polls before the third wait passed the deadline")
    }

    func testRefreshSendsGrantAndKeepsOldRefreshTokenWhenNoneReturned() async throws {
        let clock = TestClock(Support.t0)
        let transport = ScriptedTransport { _, _ in Support.json(OneDriveFixtures.refreshedNoNewRefresh) }
        let flow = flow(transport: transport, sleeps: SleepLog(), clock: clock)
        let tokens = try await flow.refresh("REFRESH-OLD")
        XCTAssertEqual(tokens.accessToken, "ACCESS-3")
        XCTAssertEqual(tokens.refreshToken, "REFRESH-OLD")
        let body = Support.bodyText(transport.requests[0])
        XCTAssertTrue(body.contains("grant_type=refresh_token"), body)
        XCTAssertTrue(body.contains("refresh_token=REFRESH-OLD"), body)
        XCTAssertTrue(body.contains("scope=Files.Read%20offline_access"), body)
    }

    func testRefreshInvalidGrantMeansNotSignedIn() async throws {
        let transport = ScriptedTransport { _, _ in Support.json(OneDriveFixtures.error("invalid_grant"), status: 400) }
        let flow = flow(transport: transport, sleeps: SleepLog(), clock: TestClock(Support.t0))
        do { _ = try await flow.refresh("R"); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? OneDriveError, .notSignedIn) }
    }

    func testMalformedDeviceCodeResponse() async throws {
        let transport = ScriptedTransport { _, _ in Support.json("{\"nope\":1}") }
        let flow = flow(transport: transport, sleeps: SleepLog(), clock: TestClock(Support.t0))
        do { _ = try await flow.start(); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? SourceError, .malformedResponse) }
    }
}
