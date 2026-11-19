import SwiftUI
import UserData
import AppLogic

/// The sources the user added, and the way to add another.
struct SourcesSettingsView: View {
    @Environment(AppServices.self) private var services
    @State private var definitions: [UDSourceDefinition] = []
    @State private var showSetup = false

    var body: some View {
        List {
            Section {
                Button("Add a Source", systemImage: "plus") { showSetup = true }
            }
            if definitions.isEmpty {
                Section {
                    Text("No sources yet.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Your Sources") {
                    ForEach(definitions, id: \.id) { definition in
                        NavigationLink {
                            SourceDetailView(definition: definition)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(definition.name)
                                // The source type by its real name (WebDAV, SMB, Jellyfin, ...), then the server.
                                Text(definition.host.isEmpty ? definition.kindTitle : "\(definition.kindTitle) · \(definition.host)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let label = definition.verificationLabel {
                                    Text(label)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if let issue = services.trust.issue(for: definition.id) {
                                    Text(issue.title)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
        }
        .pushedScreen("Sources")
        .task(id: services.libraryRevision) { definitions = services.definitions }
        .sheet(isPresented: $showSetup) { SourceSetupFlow() }
    }
}
