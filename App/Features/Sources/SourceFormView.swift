import SwiftUI
import VideoPlayerCore
import AppLogic

/// The form for one source type: its fields, a Connect button, and the answers (progress, errors, the certificate question).
struct SourceFormView: View {
    @State var draft: SourceDraft
    /// #30 item 3: the machine identifier of a server found on the network (nil for a typed source).
    var serverID: String? = nil
    var onFinished: () -> Void
    @Environment(AppServices.self) private var services
    @State private var model: ScreenModel<SourceSetupViewModel>?
    @State private var attempted = false

    private var info: SourceKindInfo { SourceCatalog.info(for: draft.kind, oneDriveClientID: SourceConfiguration.oneDriveClientID) }
    private var problems: [FieldProblem] { attempted ? SourceDraftValidator.problems(draft) : [] }
    private var phase: SetupPhase { model?.screen.phase ?? .editing }
    /// The Learn More text: the status line, then the caveat when there is one (#29: typed steps, no mixed-optional array).
    private var aboutText: String {
        let status: String = info.statusLine + "."
        guard let caveat: String = info.caveat else { return status }
        return status + " " + caveat
    }
    /// #30: the problem texts of all fields, one per line, under the fields' section (each names its field).
    private var problemText: String {
        let lines: [String] = problems.map { (problem: FieldProblem) -> String in problem.message }
        return lines.joined(separator: "\n")
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // #25 B1 (R202): one column, the type's name on top and its one sentence under it; Connect and Cancel sit together
        // after the fields. What was tested and what was not (the status and the caveat) are on the type's Learn More page,
        // one press away. #30 (R228): a full-screen `TaskPage`; all fields in ONE section, label and field on one row, the
        // problems under it. Fixed in code, verify in next screenshots (11 to 19, 94, 100, 111).
        TaskPage(title: info.title, summary: info.summary) {
            Section {
                ForEach(info.fields) { spec in
                    SourceFieldRow(spec: spec, text: binding(spec.kind))
                }
            } footer: {
                if !problems.isEmpty {
                    Text(problemText)
                }
            }
            // #30 item 3 (21-search-your-network-server-details): the found server's raw identifier, WHOLE on one line, in its own
            // details row here and never on the list row. It is a link to the identifier as a page, so the row takes the focus
            // and the system marquee can show the whole line if even the readable floor is too wide (R229). Fixed in code, verify
            // in the next screenshots.
            if let serverID {
                Section("Server Details") {
                    NavigationLink {
                        LongTextPage(title: "Server ID", text: serverID)
                    } label: {
                        LabeledContent {
                            FittingText(serverID)
                        } label: {
                            FittingText("Server ID")
                        }
                    }
                    .accessibilityLabel("Server ID")
                    .accessibilityValue(serverID)
                    .accessibilityIdentifier(ControlID.serverID)
                }
            }
            Section {
                // #36 S-C (R255): Connect and Cancel side by side, the same size, Connect prominent.
                TaskButtonRow {
                    connectRow
                    TaskButton("Cancel", role: .cancel) { dismiss() }
                        .accessibilityIdentifier(ControlID.sourceCancel)
                }
                LearnMoreLink(title: "About \(info.title)", text: aboutText)
                    .accessibilityIdentifier(ControlID.learnMore)
            }
        }
        .onChange(of: phase) { _, newPhase in
            if case .saved = newPhase {
                services.sourceAdded()
                onFinished()
            }
        }
        .alert(failure?.title ?? "", isPresented: failureShown, presenting: failure) { _ in
            Button("OK") { Task { await model?.run { $0.dismissFailure() } } }
        } message: { error in
            Text(error.message)
        }
        .alert(signIn?.title ?? "", isPresented: signInShown, presenting: signIn) { _ in
            Button("Continue") { Task { await model?.run { await $0.continueAfterSignIn() } } }
            Button("Cancel", role: .cancel) { Task { await model?.run { $0.cancelSignIn() } } }
        } message: { signIn in
            Text(signIn.message)
        }
        .alert(trust?.title ?? "", isPresented: trustShown, presenting: trust) { prompt in
            Button(prompt.trustTitle) { Task { await model?.run { await $0.trustAndContinue() } } }
            Button(prompt.cancelTitle, role: .cancel) { Task { await model?.run { $0.cancelTrust() } } }
        } message: { prompt in
            Text(prompt.message + "\n\n" + prompt.fingerprint)
        }
    }

    @ViewBuilder
    private var connectRow: some View {
        if case .testing = phase {
            // Status, not a button (L3), in the Connect button's place and size while the connection is tested.
            HStack {
                ProgressView()
                Text("Connecting")
            }
            .frame(maxWidth: .infinity, minHeight: TaskButtonLayout.minimumHeight)
        } else {
            TaskButton("Connect", prominent: true) { Task { await connect() } }
        }
    }

    private var failure: ErrorState? {
        if case .failed(let error) = phase { return error }
        return nil
    }

    private var trust: TrustPrompt? {
        if case .needsTrust(let prompt) = phase { return prompt }
        return nil
    }

    private var signIn: DeviceSignIn? {
        if case .needsSignIn(let request) = phase { return request }
        return nil
    }

    private var signInShown: Binding<Bool> {
        Binding(get: { signIn != nil }, set: { _ in })
    }

    private var failureShown: Binding<Bool> {
        Binding(get: { failure != nil }, set: { _ in })
    }

    private var trustShown: Binding<Bool> {
        Binding(get: { trust != nil }, set: { _ in })
    }

    private func binding(_ field: SourceFieldKind) -> Binding<String> {
        Binding(get: { draft[field] }, set: { draft[field] = $0 })
    }

    private func connect() async {
        attempted = true
        let current = draft
        var setup = SourceSetupViewModel(store: services.store, connector: services.connector, secrets: services.secrets,
                                         draft: current, definitions: services.definitionSaver)
        setup.oneDriveClientID = SourceConfiguration.oneDriveClientID
        model = ScreenModel(setup)
        await model?.run { await $0.connect() }
    }
}
