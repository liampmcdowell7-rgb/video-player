import SwiftUI
import UserData
import AppLogic

/// The sources the user added, and the way to add another. #15 3.3: bounded column (`SettingsPane`) so "Add a Source" is a
/// normal row, not a full-width bar; the system section header (L4). The verification status is said once, on each
/// source's own page (L9), not under every row.
struct SourcesSettingsView: View {
    @Environment(AppServices.self) private var services
    @State private var definitions: [UDSourceDefinition] = []
    @State private var showSetup = false

    var body: some View {
        SettingsPane(title: "Sources", summary: SettingsTexts.sourcesSummary,
                     status: definitions.isEmpty ? [SettingsTexts.noSources] : []) {
            Section {
                Button { showSetup = true } label: { RowLabel("Add a Source", systemImage: "plus") }
            }
            if !definitions.isEmpty {
                Section("Your Sources") {
                    ForEach(definitions, id: \.id) { definition in
                        NavigationLink {
                            SourceDetailView(definition: definition)
                        } label: {
                            VStack(alignment: .leading) {
                                FittingText(definition.name)
                                // The source type by its real name (WebDAV, SMB, Jellyfin, ...), then the server.
                                FittingLine(line: ShortLine(ordered: definition.host.isEmpty ? [definition.kindTitle] : [definition.kindTitle, definition.host]),
                                            style: .caption)
                                    .foregroundStyle(.secondary)
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
        .task(id: services.libraryRevision) { definitions = services.definitions }
        .addSourceCover(isPresented: $showSetup)
    }
}
