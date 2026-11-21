import SwiftUI
import VideoPlayerCore
import AppLogic

/// The form for one source type: its fields, a Connect button, and the answers (progress, errors, the certificate question).
struct SourceFormView: View {
    @State var draft: SourceDraft
    /// #30 item 3: the machine identifier of a server found on the network (nil for a typed source). R326: state, because
    /// the form's own Search Your Network row can fill it.
    @State var serverID: String? = nil
    var onFinished: () -> Void
    @Environment(AppServices.self) private var services
    @State private var model: ScreenModel<SourceSetupViewModel>?
    @State private var attempted = false
    /// R325 (PROVISIONAL): where the focus is: a field row or Connect. Replaces R273's first focus on Name.
    @FocusState private var focus: SourceFormFocus?
    /// R325: set after Done filled the last empty required field; applied when the form appears again.
    @State private var pendingFocus: SourceFormFocus?

    private var info: SourceKindInfo { SourceCatalog.info(for: draft.kind, oneDriveClientID: SourceConfiguration.oneDriveClientID) }
    private var problems: [FieldProblem] { attempted ? SourceDraftValidator.problems(draft) : [] }
    private var phase: SetupPhase { model?.screen.phase ?? .editing }
    /// The fields' section footer (R322, R327): after Connect, what is wrong with each field (each names its field), one per
    /// line; then, always, the one line that names the optional fields. Plain text, never an alert for validation.
    private var footerText: String {
        var lines: [String] = problems.map { (problem: FieldProblem) -> String in problem.message }
        if let optional = SourceFormText.optionalLine(info.fields) { lines.append(optional) }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        // #25 B1 (R202): one column, the type's name on top and its one sentence under it. #30 (R228): a full-screen
        // `TaskPage`. R320 (PROVISIONAL, docs/SOURCE_SETUP_DESIGN.md): every field is one tvOS Settings row, value trailing;
        // Select opens its entry page. R324: Connect is the one action; no Cancel (Back returns to the type list).
        TaskPage(title: info.title, summary: info.summary) {
            // R326 (PROVISIONAL): discovery first. A type the network search finds starts with its own Search Your Network
            // row; the search starts only when the row is chosen, so opening a form never asks for local-network access.
            if SourceDiscoveryText.searches(draft.kind) {
                Section {
                    NavigationLink {
                        DiscoveryView(kind: draft.kind, onPick: picked)
                    } label: {
                        RowLabel("Search Your Network", systemImage: "wifi")
                    }
                    .accessibilityIdentifier(ControlID.formSearchYourNetwork)
                }
            }
            Section {
                ForEach(info.fields) { spec in
                    SourceFieldRow(spec: spec, text: binding(spec.kind)) { (before: String, after: String) in
                        fieldDone(spec.kind, before: before, after: after)
                    }
                    .focused($focus, equals: .field(spec.kind))
                }
            } footer: {
                if !footerText.isEmpty {
                    Text(footerText)
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
                // R324 (PROVISIONAL): Connect alone, `.borderedProminent` (HIG Buttons: "use a button that has a prominent
                // visual style for the most likely action in a view"). No Cancel: the remote's Back opens the parent, the
                // type list (HIG Remotes), and Add a Source's own Cancel closes the cover (HIG Modality).
                TaskButtonRow {
                    connectRow
                }
                // R329 (PROVISIONAL): the same About page as About Source Types opens for this type.
                NavigationLink {
                    SourceAboutPage(info: info)
                } label: {
                    SlotLabel(SourceAboutText.title(info), systemImage: "info.circle")
                }
                .accessibilityIdentifier(ControlID.learnMore)
            }
        }
        // R325: the first focus (Apple, defaultFocus(_:_:priority:), tvOS 16.0+: focus goes there "when the view is first
        // presented"): Connect when every required field is filled, otherwise the first empty required row.
        .defaultFocus($focus, SourceFormText.firstFocus(draft))
        // R325: after Done filled the last empty required field, Connect, once the form shows again. UNVERIFIED: whether
        // SwiftUI restores the focus to the row after this.
        .onAppear {
            if let next = pendingFocus {
                pendingFocus = nil
                focus = next
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
                .focused($focus, equals: .connect)
                .accessibilityIdentifier(ControlID.sourceConnect)
        }
    }

    /// R326: a server chosen on the form's Search Your Network page fills the rows it knows (a typed Name, user name and
    /// password stay), adds Server Details, and the focus goes where R325 puts it as the form shows again.
    private func picked(_ found: DiscoveredSource) {
        let next: SourceDraft = SourceDiscoveryText.merged(draft, with: found)
        draft = next
        serverID = SourceSetupFlow.identifier(of: found)
        pendingFocus = SourceFormText.firstFocus(next)
    }

    /// R325: Done on a field's entry page. When that Done filled the last empty required field, the focus goes to Connect
    /// as the form shows again.
    private func fieldDone(_ field: SourceFieldKind, before: String, after: String) {
        var old: SourceDraft = draft
        old[field] = before
        var new: SourceDraft = draft
        new[field] = after
        if let next = SourceFormText.focusAfterDone(before: old, after: new) { pendingFocus = next }
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
