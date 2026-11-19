import SwiftUI
import UserData
import AppLogic

/// One source: its settings, how well its type has been tested, the approved fingerprint, a connection check, a way to
/// enter its password again, and Remove. A changed certificate or host key is shown here and is never trusted by itself.
struct SourceDetailView: View {
    let definition: UDSourceDefinition
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmRemove = false
    @State private var confirmTrust = false
    @State private var message: String?
    @State private var checking = false
    @State private var checkResult: String?

    /// The saved version (a trusted fingerprint updates it after this screen opened).
    private var current: UDSourceDefinition {
        _ = services.libraryRevision
        return services.definitions.first { $0.id == definition.id } ?? definition
    }

    private var issue: TrustIssue? { services.trust.issue(for: definition.id) }

    var body: some View {
        Form {
            Section {
                LabeledContent("Name", value: current.name)
                LabeledContent("Type", value: current.kindTitle)
                if !current.host.isEmpty { LabeledContent("Server", value: current.host) }
                if !current.username.isEmpty { LabeledContent("User Name", value: current.username) }
                LabeledContent("Password", value: passwordStatus)
            }
            Section("Tested") {
                if let label = current.verificationLabel { Text(label) }
                if let caveat = current.caveat {
                    Text(caveat)
                        .foregroundStyle(.secondary)
                }
            }
            if SortSourceOption.applies(toKind: current.kind) {
                // docs/SORTING.md; PROVISIONAL setting, OPEN_QUESTIONS.
                Section {
                    Toggle(SortSourceOption.title, isOn: Binding(
                        get: { SortSourceOption.preferFilename(current) },
                        set: { on in Task { await services.setSortByFilename(on, for: current) } }
                    ))
                } footer: {
                    Text(SortSourceOption.footer)
                }
            }
            if SourceBuilder.trustKind(for: current) != nil {
                Section("Approved Fingerprint") {
                    if let shown = current.approvedFingerprintDisplay {
                        Text(shown)
                    } else {
                        Text("None approved yet. The system’s own trust decides for this server.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let issue {
                Section(issue.title) {
                    Text(issue.message)
                    if let approved = issue.approvedFingerprint { Text("Approved: " + approved) }
                    Text("Now shown: " + issue.presentedFingerprint)
                    Button(issue.acceptTitle) { confirmTrust = true }
                    Button(issue.keepTitle) { services.keepBlocking(issue) }
                }
            }
            Section {
                Button(checking ? "Checking" : "Check Connection") { Task { await check() } }
                    .disabled(checking)
                if let checkResult {
                    Text(checkResult)
                        .foregroundStyle(.secondary)
                }
            }
            if current.auth != "none" && current.auth != "oauth" {
                Section("Enter the Password Again") {
                    SecureField("Password", text: $password)
                    Button("Save Password") { Task { await savePassword() } }
                        .disabled(password.isEmpty)
                    if let message {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button("Remove Source", role: .destructive) { confirmRemove = true }
            }
        }
        .pushedScreen(current.name)
        .confirmationDialog(issue?.acceptTitle ?? "", isPresented: $confirmTrust, titleVisibility: .visible, presenting: issue) { issue in
            Button(issue.acceptTitle, role: .destructive) { Task { await services.trustNewFingerprint(issue) } }
            Button("Cancel", role: .cancel) {}
        } message: { issue in
            Text("Approved before: " + (issue.approvedFingerprint ?? "none") + "\n\nNow shown: " + issue.presentedFingerprint + "\n\nOnly continue if you know why it changed.")
        }
        .confirmationDialog("Remove “\(current.name)”?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove Source", role: .destructive) {
                Task {
                    await services.removeSource(id: definition.id)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its titles are removed from your library. The files on the server are not touched.")
        }
    }

    private var passwordStatus: String {
        if current.auth == "none" { return "Not needed" }
        if current.auth == "oauth" { return "Sign-in saved" }
        return services.secrets.secret(for: definition.id) == nil ? "Needed" : "Saved"
    }

    private func check() async {
        checking = true
        checkResult = nil
        if let problem = await services.checkSource(current) {
            checkResult = problem.title + ". " + problem.message
        } else {
            checkResult = "Connected."
        }
        checking = false
    }

    private func savePassword() async {
        do {
            _ = try await services.secrets.set(password, for: definition.id)
            password = ""
            message = "Saved."
            await services.refreshCloudStatus()
        } catch {
            message = "The password could not be saved."
        }
    }
}
