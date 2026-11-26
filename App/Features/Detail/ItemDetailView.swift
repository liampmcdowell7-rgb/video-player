import SwiftUI
import AppLogic
import UserData

/// A movie or an episode: facts, Play, versions, extras and the less common actions.
struct ItemDetailView: View {
    let itemID: Int64
    @Environment(AppServices.self) private var services
    @State private var model: ScreenModel<ItemDetailViewModel>?
    @State private var showFixMatch = false
    /// R471 (14): Unmatch is asked about (system confirmation dialog).
    @State private var askUnmatch = false
    /// R471 (15): Delete from Library is asked about first; the page closes once the title has left the library.
    @State private var askDelete = false
    @Environment(\.dismiss) private var dismiss
    @State private var showSortInfo = false
    @State private var showEdit = false
    @State private var editKeys: [UDEditKey] = []
    @State private var editStart: UDEditField.Group?
    @State private var askVersion = false
    @State private var pendingFromStart = false
    @AppStorage(PlayVersion.key) private var playVersionRaw = PlayVersion.default.rawValue
    private var playVersion: PlayVersion { PlayVersion(rawValue: playVersionRaw) ?? .auto }

    var body: some View {
        Group {
            if let model {
                ScreenStateView(state: model.screen.state, onRetry: { Task { await reload() } }) { content in
                    ItemDetailContentView(content: content, model: model, onPlay: play, onFixMatch: { showFixMatch = true },
                                          onSortInfo: { showSortInfo = true }, onEdit: { Task { await openEdit() } },
                                          onChangeArtwork: { Task { await openEdit(start: .artwork) } },
                                          onUnmatch: { askUnmatch = true }, onDelete: { askDelete = true })
                }
            } else {
                LoadingView()
            }
        }
        .task(id: services.libraryRevision) { await reload() }
        // R458: Play Version = Ask. The choice is kept as the title's Select Version, so the question comes once per title.
        .confirmationDialog("Which Version?", isPresented: $askVersion, titleVisibility: .visible) {
            ForEach(model?.screen.state.content?.versions ?? []) { version in
                Button(version.label) {
                    Task {
                        await model?.run { await $0.choosePreferredVersion(version.id) }
                        services.playRequest = PlayRequest(itemID: itemID, fromStart: pendingFromStart)
                    }
                }
            }
        }
        // R471 (14): Unmatch says what changes and what stays before it acts (a movie; an episode follows its show).
        .confirmationDialog(unmatchText.title, isPresented: $askUnmatch, titleVisibility: .visible) {
            Button(unmatchText.button, role: .destructive) { Task { await services.unmatch(.movie(itemID: itemID)) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(unmatchText.message)
        }
        .confirmationDialog(deleteText.title, isPresented: $askDelete, titleVisibility: .visible) {
            Button(deleteText.button, role: .destructive) {
                Task { await services.removeFromLibrary(.item(itemID: itemID)); dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteText.message)
        }
        .taskCover(isPresented: $showFixMatch) {
            if let content = model?.screen.state.content {
                FixMatchView(itemID: itemID, kind: content.kind, currentTitle: content.title)
            }
        }
        .taskCover(isPresented: $showEdit) {
            if let content = model?.screen.state.content, !editKeys.isEmpty {
                MetadataEditView(title: content.episodeTitle ?? content.title, keys: editKeys, artworkKey: "item-\(itemID)", level: content.kind == .movie ? .movie : .episode,
                                 startGroup: editStart)
            }
        }
        .taskCover(isPresented: $showSortInfo) {
            if let content = model?.screen.state.content {
                SortInfoSheet(itemID: itemID, kind: content.kind)
            }
        }
    }

    private var unmatchText: (title: String, message: String, button: String) {
        Unmatcher.confirmation(.movie(itemID: itemID), title: model?.screen.state.content?.title ?? "")
    }

    private var deleteText: (title: String, message: String, button: String) {
        let content = model?.screen.state.content
        return LibraryRemover.confirmation(.item(itemID: itemID), title: content?.episodeTitle ?? content?.title ?? "")
    }

    /// R449: the keys this item's edits live under (online id and file), then the edit screens.
    /// `start`: the group to open on (R471 (13): Change Artwork opens Artwork); nil: the list of groups.
    private func openEdit(start: UDEditField.Group? = nil) async {
        editStart = start
        guard let item = try? await services.store.item(id: itemID) else { return }
        let files = (try? await services.store.versions(of: itemID)) ?? []
        editKeys = EditTarget.keys(for: item, files: files)
        showEdit = !editKeys.isEmpty
    }

    private func play(fromStart: Bool) {
        if let content = model?.screen.state.content,
           PlayVersion.asks(mode: playVersion, versionCount: content.versions.count, hasExplicitChoice: content.hasExplicitVersion) {
            pendingFromStart = fromStart
            askVersion = true
            return
        }
        services.playRequest = PlayRequest(itemID: itemID, fromStart: fromStart)
    }

    private func reload() async {
        if model == nil {
            model = ScreenModel(ItemDetailViewModel(store: services.store, itemID: itemID, trackReader: services.trackDetailsReader))
        }
        let mode = playVersion
        await model?.run { $0.playVersion = mode; await $0.load() }
        // #21 C: the frame rate and every audio and subtitle track, read from the file's header once and then kept.
        // R471 (72): read without holding a copy of the page, then put the details on the page as it is now (a Favorite or
        // Watched change made during the read stays).
        if let read = await model?.screen.readTrackDetails() {
            await model?.run { $0.applyTrackDetails(read) }
        }
    }
}
