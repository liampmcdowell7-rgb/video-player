import SwiftUI
import AppLogic

/// Add a Source > Plex: the sign-in code page (docs/PLEX_SOURCE.md sections 1 and 10; OPEN_QUESTIONS R302).
///
/// Design reference (owner's principle, R332 and R301): adding a source has no equivalent in Apple's TV app, so the flow
/// follows tvOS Settings; this one page is a full-screen code page instead of a Settings form, because HIG Managing accounts
/// (read 20 Nov 2026) says, for tvOS, "Prefer letting people use another device to sign up or authenticate" and "Minimize
/// data entry", and Designing for tvOS (read 20 Nov 2026) says people sit "often 8 feet or more" away, so the code is the
/// largest text on the page. Whether a tvOS Settings page of this exact shape exists is UNVERIFIED (no Apple page read
/// shows one). System components only: Text in system text styles, the system spinner and one system Button. "plex.tv/link"
/// is plain text, never a link or a logo. A QR code is an alternative in R302, not built.
struct PlexSetupView: View {
    @Environment(AppServices.self) private var services
    @State private var model: ScreenModel<PlexSetupModel>?
    /// Each Get a New Code or Try Again starts a new attempt; the `.task` below is tied to it and to the page, so leaving
    /// the page (or starting again) cancels the polling.
    @State private var attempt = 0

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: attempt) {
                if model == nil {
                    let account = PlexAccountConnector(deviceID: services.ledger.deviceID, credentials: services.dependencies.credentials)
                    model = ScreenModel(PlexSetupModel(account: account))
                }
                await getCodeAndWait()
            }
    }

    private var phase: PlexSetupPhase { model?.screen.phase ?? .gettingCode }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .gettingCode:
            VStack {
                ProgressView()
                Text(PlexSetupText.gettingCode)
                    .foregroundStyle(.secondary)
            }
        case .code(let code):
            codePage(code: code.code, link: code.linkText)
        case .codeExpired:
            VStack {
                Text(PlexSetupText.signInTitle)
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)
                Text(PlexSetupText.expired)
                    .foregroundStyle(.secondary)
                Button(PlexSetupText.newCode) { attempt += 1 }
            }
        case .signedIn:
            // Stage 3 (R303) puts the server list here.
            Text(PlexSetupText.signedIn)
        case .failed(let error):
            ErrorStateView(error: error) { attempt += 1 }
        }
    }

    private func codePage(code: String, link: String) -> some View {
        VStack {
            Text(PlexSetupText.signInTitle)
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
            Text(PlexSetupText.instruction(link: link))
                .multilineTextAlignment(.center)
            Text(verbatim: link)
                .font(.title3)
            // S1: the code is one line; it scales down rather than wrap or end in "...".
            Text(verbatim: code)
                .font(TVTextStyle.title1.font)
                .fontWeight(.bold)
                .monospaced()
                .lineLimit(1)
                // design-lint:allow rule S1 (OPEN_QUESTIONS R165): the system text style shrinks to fit, never below Apple's 23 pt minimum (HIG Typography)
                .minimumScaleFactor(ShortLine.minimumScale(forPointSize: TVTextStyle.title1.pointSize))
                .accessibilityLabel(code.map(String.init).joined(separator: " "))
            Text(PlexSetupText.why)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                ProgressView()
                Text(PlexSetupText.waiting)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Gets a code, then waits (polling once per second in the connector) until it is entered or runs out.
    private func getCodeAndWait() async {
        guard let model else { return }
        await model.run { await $0.requestCode() }
        await model.run { await $0.waitForSignIn() }
    }
}
