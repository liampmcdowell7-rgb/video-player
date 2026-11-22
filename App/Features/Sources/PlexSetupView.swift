import SwiftUI
import AppLogic

/// Add a Source > Plex: the sign-in code page, then the account's servers (docs/PLEX_SOURCE.md sections 1, 2 and 10;
/// OPEN_QUESTIONS R302, R303).
///
/// Design reference (owner's principle, R332 and R301): adding a source has no equivalent in Apple's TV app, so the flow
/// follows tvOS Settings. The code page is a full-screen page instead of a Settings form, because HIG Managing accounts
/// (read 20 Nov 2026) says, for tvOS, "Prefer letting people use another device to sign up or authenticate" and "Minimize
/// data entry", and Designing for tvOS (read 20 Nov 2026) says people sit "often 8 feet or more" away, so the code is the
/// largest text on the page. Whether a tvOS Settings page of this exact shape exists is UNVERIFIED (no Apple page read
/// shows one). The server list is the same full-screen task page as Add a Source and the forms (`TaskPage`, a system Form):
/// one row per server, its name and "Local" or "Remote" as secondary text (rule L2). System components only. "plex.tv/link"
/// is plain text, never a link or a logo. A QR code is an alternative in R302, not built.
struct PlexSetupView: View {
    @Environment(AppServices.self) private var services
    var onFinished: () -> Void
    @State private var model: ScreenModel<PlexSetupModel>?
    /// Each Get a New Code or Try Again starts a new attempt; the `.task` below is tied to it and to the page, so leaving
    /// the page (or starting again) cancels the polling.
    @State private var attempt = 0
    /// The server whose row was chosen; adding runs in a `.task` tied to it, so leaving the page cancels it too.
    @State private var chosen: PlexServerChoice?

    var body: some View {
        content
            .task(id: attempt) {
                if model == nil {
                    let account = PlexAccountConnector(deviceID: services.ledger.deviceID, credentials: services.dependencies.credentials)
                    model = ScreenModel(PlexSetupModel(account: account, store: services.store, secrets: services.secrets,
                                                       definitions: services.definitionSaver))
                }
                // Signed in already: the servers; otherwise a code, then wait for it (a no-op when the servers are shown).
                await model?.run { await $0.start() }
                await model?.run { await $0.waitForSignIn() }
            }
            .task(id: chosen?.id) {
                guard let chosen else { return }
                await model?.run { await $0.add(chosen) }
                if case .saved = phase { onFinished() }
                self.chosen = nil
            }
    }

    private var phase: PlexSetupPhase { model?.screen.phase ?? .gettingCode }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .gettingCode:
            spinner(PlexSetupText.gettingCode)
        case .code(let code):
            codePage(code: code.code, link: code.linkText)
        case .codeExpired:
            // R382 (owner's audit #22): the system's empty-state view, as for "no servers" below; same texts and action.
            ContentUnavailableView {
                Label(PlexSetupText.signInTitle, systemImage: "clock")
            } description: {
                Text(PlexSetupText.expired)
            } actions: {
                Button(PlexSetupText.newCode) { attempt += 1 }
            }
        case .loadingServers:
            spinner(PlexSetupText.loadingServers)
        case .servers(let servers):
            serverList(servers, busy: nil)
        case .connecting(let server):
            serverList([server], busy: server)
        case .noServers:
            ContentUnavailableView {
                Label(PlexSetupText.noServersTitle, systemImage: "server.rack")
            } description: {
                Text(PlexSetupText.noServers)
            }
        case .saved:
            spinner(nil)
        case .failed(let error):
            ErrorStateView(error: error) { attempt += 1 }
        }
    }

    private func spinner(_ text: String?) -> some View {
        VStack {
            ProgressView()
            if let text {
                Text(text)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// R303: one system row per server, the name and "Local" or "Remote" on their own lines (S1), the footer saying what
    /// adding does. While one server connects, its row shows the system spinner and nothing can be chosen twice.
    private func serverList(_ servers: [PlexServerChoice], busy: PlexServerChoice?) -> some View {
        TaskPage(title: PlexSetupText.serversTitle) {
            Section {
                ForEach(servers) { server in
                    Button {
                        chosen = server
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                FittingText(server.name)
                                FittingText(server.detail, style: .caption)
                                    .foregroundStyle(.secondary)
                            }
                            if busy == server { ProgressView() }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .disabled(busy != nil)
                }
            } footer: {
                Text(PlexSetupText.serversFooter)
            }
        }
    }
}
