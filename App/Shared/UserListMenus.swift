import SwiftUI
import AppLogic
import UserData

/// R471 (17), PROVISIONAL: the Add to List and Add to Playlist or Collection entries of a details button or a long press.
/// A system menu: every list of the action's kinds, then the entries that make a new one. With the title's key known (a
/// page), the lists that hold the title are checked and choosing one adds or removes it; without it (a card, which does not
/// read the key until chosen), choosing a list adds the title and nothing is checked. Words ours (`UserListText`).
struct AddToListMenu: View {
    let action: ProductAction
    /// The title's key when known (a page); nil on a card.
    let ref: UDTitleRef?
    let onChoose: (UDUserList) -> Void
    let onNew: (UDUserList.Kind) -> Void
    @Environment(AppServices.self) private var services

    var body: some View {
        let kinds = UserListText.kinds(for: action)
        let lists = services.userLists(kinds: Set(kinds))
        let holding = ref.map { services.ledger.listIDs(containing: $0) } ?? []
        Menu {
            ForEach(lists) { list in
                Button { onChoose(list) } label: {
                    if holding.contains(list.id) {
                        Label(UserListText.entry(list, in: action), systemImage: "checkmark")
                    } else {
                        Text(UserListText.entry(list, in: action))
                    }
                }
            }
            if !lists.isEmpty { Divider() }
            ForEach(kinds, id: \.self) { kind in
                Button(UserListText.newEntry(kind), systemImage: "plus") { onNew(kind) }
            }
        } label: {
            Label(action.title, systemImage: action.symbol)
        }
        .accessibilityIdentifier("product.\(action.rawValue)")
    }
}

/// A list name to type: a new list (with the title to put in it, when made from a menu) or a list being renamed.
struct ListNameRequest: Identifiable {
    let id = UUID()
    let kind: UDUserList.Kind
    var renaming: UDUserList? = nil
    /// The title to add once the list is made; resolved when Done is pressed (a card reads it only then).
    var title: String = ""
    var ref: (() async -> UDTitleRef?)? = nil
}

/// The name page in a cover: the shared one-field entry page (`TextEntryPage`); Done makes or renames the list, Back
/// changes nothing.
private struct ListNamePage: View {
    let request: ListNameRequest
    @Environment(AppServices.self) private var services
    @State private var name: String

    init(request: ListNameRequest) {
        self.request = request
        _name = State(initialValue: request.renaming?.name ?? "")
    }

    var body: some View {
        TextEntryPage(title: UserListText.nameTitle(request.kind, renaming: request.renaming != nil),
                      summary: UserListText.nameSummary(request.kind), entry: UserListText.nameEntry, value: $name) { _, typed in
            let request = request
            Task {
                if let list = request.renaming {
                    services.renameList(list, to: typed)
                } else if let list = services.createList(name: typed, kind: request.kind), let resolve = request.ref,
                          let ref = await resolve() {
                    services.addToList(list, ref: ref, title: request.title)
                }
            }
        }
    }
}

extension View {
    /// Shows the name page while `request` is set.
    func listNameCover(_ request: Binding<ListNameRequest?>) -> some View {
        taskCover(item: request) { ListNamePage(request: $0) }
    }
}
