import SwiftUI
import AppLogic
import UserData

/// R471 (17), PROVISIONAL: Settings > Library > My Lists. The user's lists, playlists and collections, one section per kind,
/// each with its count; a list opens on its titles. New entries at the end of each section make one (the shared name page).
/// Layout: `SettingsPane`, system rows only.
struct UserListsView: View {
    @Environment(AppServices.self) private var services
    @State private var naming: ListNameRequest?

    var body: some View {
        SettingsPane(title: UserListText.settingsTitle, summary: UserListText.settingsSummary) {
            ForEach(UDUserList.Kind.allCases, id: \.self) { kind in
                Section(UserListText.sectionTitle(kind)) {
                    ForEach(services.userLists(kinds: [kind])) { list in
                        NavigationLink {
                            UserListView(listID: list.id).screenIdentifier("screen.userList")
                        } label: {
                            ValueRow(list.name, value: String(services.ledger.listEntries(list.id).count))
                        }
                    }
                    Button(UserListText.newEntry(kind), systemImage: "plus") { naming = ListNameRequest(kind: kind) }
                }
            }
        }
        .listNameCover($naming)
    }
}

/// One list: its titles in the order they were added; choosing one opens its page (or says it is not in this library).
/// Rename and Delete at the end; each title can be removed from the list (the title stays in the library).
private struct UserListView: View {
    let listID: String
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var targets: [UDTitleRef: UserListTarget] = [:]
    @State private var naming: ListNameRequest?
    @State private var askDelete = false
    @State private var chosen: UDUserListEntry?

    var body: some View {
        let list = services.userList(id: listID)
        let entries = services.listEntries(listID)
        SettingsPane(title: list?.name ?? "", summary: list.map { UserListText.listSummary($0.kind) } ?? "") {
            Section {
                if entries.isEmpty {
                    Text(UserListText.emptyList)
                }
                ForEach(entries, id: \.self) { entry in
                    Button { chosen = entry } label: {
                        if targets[entry.ref] == nil {
                            LabeledContent(entry.title, value: UserListText.missing)
                        } else {
                            Text(entry.title)
                        }
                    }
                }
            }
            if let list {
                Section {
                    Button(UserListText.rename(list.kind), systemImage: "pencil") {
                        naming = ListNameRequest(kind: list.kind, renaming: list)
                    }
                    Button(UserListText.deleteConfirmation(list).button, systemImage: "trash", role: .destructive) { askDelete = true }
                }
            }
        }
        .task(id: services.listsRevision) {
            var found: [UDTitleRef: UserListTarget] = [:]
            for entry in services.listEntries(listID) {
                if let target = await services.listTarget(entry.ref) { found[entry.ref] = target }
            }
            targets = found
        }
        .listNameCover($naming)
        .confirmationDialog(chosen?.title ?? "", isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } }),
                            titleVisibility: .visible, presenting: chosen) { entry in
            if let target = targets[entry.ref] {
                Button("Open", systemImage: "arrow.forward") {
                    switch target {
                    case let .item(id): services.openRequest = .item(id)
                    case let .series(id): services.openRequest = .series(id)
                    }
                }
            }
            Button(UserListText.removeEntry, systemImage: "minus.circle", role: .destructive) {
                if let list { services.removeFromList(list, ref: entry.ref) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(list.map { UserListText.deleteConfirmation($0).title } ?? "", isPresented: $askDelete, titleVisibility: .visible) {
            if let list {
                Button(UserListText.deleteConfirmation(list).button, role: .destructive) {
                    services.deleteList(list)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let list { Text(UserListText.deleteConfirmation(list).message) }
        }
    }
}
