import SwiftUI
import UserData
import AppLogic

/// One source: its settings, how well its type has been tested, the approved fingerprint, a connection check, a way to
/// enter its password again, and Remove. A changed certificate or host key is shown here and is never trusted by itself.
/// The one sentence under a source page's title.
enum SourceDetailText {
    static let summary = "This source’s settings, its connection and how well its type has been tested."
}

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
    @State private var newName = ""
    @State private var testing = false
    @State private var speedResult: String?
    @State private var confirmRefresh = false

    /// The saved version (a trusted fingerprint updates it after this screen opened).
    private var current: UDSourceDefinition {
        _ = services.libraryRevision
        return services.definitions.first { $0.id == definition.id } ?? definition
    }

    private var issue: TrustIssue? { services.trust.issue(for: definition.id) }

    var body: some View {
        // #15 3.4: bounded column (`SettingsPane`), so the Name row is no longer clipped under the title; how well the type
        // is tested is status text in the left column, said once (L3, L9).
        SettingsPane(title: current.name, summary: SourceDetailText.summary,
                     status: [current.verificationLabel ?? "", current.caveat ?? ""]) {
            Section {
                ValueRow("Name", value: current.name)
                ValueRow("Type", value: current.kindTitle)
                if !current.host.isEmpty { ValueRow("Server", value: current.host) }
                if !current.username.isEmpty { ValueRow("User Name", value: current.username) }
                ValueRow("Password", value: passwordStatus)
            }
            // R458: Hide, Edit (the name), Speed Test and Refresh Metadata of this source.
            Section {
                SettingToggle(HideSourceOption.title, isOn: Binding(
                    get: { HideSourceOption.isHidden(current) },
                    set: { on in Task { await services.setSourceHidden(on, for: current) } }
                ))
            } footer: {
                Text(HideSourceOption.footer)
            }
            Section("Edit") {
                TextField("Name", text: $newName)
                Button("Save Name") {
                    Task { await services.renameSource(newName, for: current); newName = "" }
                }
                .disabled(SourceRename.cleaned(newName) == nil)
            }
            Section {
                TaskButtonRow {
                    TaskButton(testing ? "Testing" : "Speed Test") { Task { await runSpeedTest() } }
                        .disabled(testing)
                }
                if let speedResult { ValueRow("Read Speed", value: speedResult).readableRow() }
            } footer: {
                Text(SpeedTest.footer)
            }
            Section {
                TaskButtonRow {
                    TaskButton("Refresh Metadata") { confirmRefresh = true }
                        .disabled(!services.online.hasCatalogueKey)
                }
            } footer: {
                Text(services.online.hasCatalogueKey ? MetadataRefresh.message : MetadataRefresh.needsKeyLine)
            }
            if SortSourceOption.applies(toKind: current.kind) {
                // docs/SORTING.md; PROVISIONAL setting, OPEN_QUESTIONS.
                Section {
                    SettingToggle(SortSourceOption.title, isOn: Binding(
                        get: { SortSourceOption.preferFilename(current) },
                        set: { on in Task { await services.setSortByFilename(on, for: current) } }
                    ))
                } footer: {
                    Text(SortSourceOption.footer)
                }
            }
            if PlexWatchSyncOption.applies(toKind: current.kind) {
                // R309: two-way watch state with this Plex server; off by default. PROVISIONAL, OPEN_QUESTIONS.
                Section {
                    SettingToggle(PlexWatchSyncOption.title, isOn: Binding(
                        get: { PlexWatchSyncOption.isOn(current) },
                        set: { on in Task { await services.setPlexWatchSync(on, for: current) } }
                    ))
                } footer: {
                    Text(PlexWatchSyncOption.footer)
                }
            }
            if SourceBuilder.trustKind(for: current) != nil {
                Section("Approved Fingerprint") {
                    if let shown = current.approvedFingerprintDisplay {
                        Text(shown)
                    } else {
                        StatusText("None approved yet. The system’s own trust decides for this server.")
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
                // #36 S-C (R255): the page's main action, a prominent bezeled button.
                TaskButtonRow {
                    TaskButton(checking ? "Checking" : "Check Connection", prominent: true) { Task { await check() } }
                        .disabled(checking)
                }
            } footer: {
                if let checkResult { Text(checkResult) }
            }
            if current.auth != "none" && current.auth != "oauth" {
                Section {
                    SecureField("Password", text: $password)
                    Button("Save Password") { Task { await savePassword() } }
                        .disabled(password.isEmpty)
                } header: {
                    Text("Enter the Password Again")
                } footer: {
                    if let message { Text(message) }
                }
            }
            Section {
                TaskButtonRow {
                    TaskButton("Forget Source", role: .destructive) { confirmRemove = true }
                }
            }
        }
        .confirmationDialog(issue?.acceptTitle ?? "", isPresented: $confirmTrust, titleVisibility: .visible, presenting: issue) { issue in
            Button(issue.acceptTitle, role: .destructive) { Task { await services.trustNewFingerprint(issue) } }
            Button("Cancel", role: .cancel) {}
        } message: { issue in
            Text("Approved before: " + (issue.approvedFingerprint ?? "none") + "\n\nNow shown: " + issue.presentedFingerprint + "\n\nOnly continue if you know why it changed.")
        }
        .confirmationDialog(MetadataRefresh.confirmTitle, isPresented: $confirmRefresh, titleVisibility: .visible) {
            Button("Refresh This Source") { Task { await services.refreshMetadata(sourceID: definition.id) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(MetadataRefresh.message)
        }
        .confirmationDialog("Forget “\(current.name)”?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Forget Source", role: .destructive) {
                Task {
                    await services.removeSource(id: definition.id)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ForgetSourceText.message(name: current.name))
        }
    }

    private var passwordStatus: String {
        if current.auth == "none" { return "Not needed" }
        if current.auth == "oauth" { return "Sign-in saved" }
        return services.secrets.secret(for: definition.id) == nil ? "Needed" : "Saved"
    }

    private func runSpeedTest() async {
        testing = true
        speedResult = await services.speedTest(current)
        testing = false
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
