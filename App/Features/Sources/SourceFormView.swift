import SwiftUI
import VideoPlayerCore
import AppLogic

/// The form for one source type: its fields, a Connect button, and the answers (progress, errors, the certificate question).
struct SourceFormView: View {
    @State var draft: SourceDraft
    var onFinished: () -> Void
    @Environment(AppServices.self) private var services
    @State private var model: ScreenModel<SourceSetupViewModel>?
    @State private var attempted = false

    private var info: SourceKindInfo { SourceCatalog.info(for: draft.kind, oneDriveClientID: SourceConfiguration.oneDriveClientID) }
    private var problems: [FieldProblem] { attempted ? SourceDraftValidator.problems(draft) : [] }
    private var phase: SetupPhase { model?.screen.phase ?? .editing }

    var body: some View {
        Form {
            Section {
                Text(info.statusLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let caveat = info.caveat {
                    Text(caveat)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(info.fields) { spec in
                SourceFieldRow(spec: spec, text: binding(spec.kind), problem: problems.first { $0.field == spec.kind }?.message)
            }
            Section {
                connectRow
            }
        }
        .pushedScreen(info.title)
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
            HStack {
                ProgressView()
                Text("Connecting")
            }
        } else {
            Button("Connect") { Task { await connect() } }
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
