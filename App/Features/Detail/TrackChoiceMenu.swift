import SwiftUI
import AppLogic
import LibraryIndex
import Subtitles

/// R471 (38), PROVISIONAL: the Audio or the Subtitles row of a movie's or an episode's actions menu. A system menu picker
/// (the check on the current row and the current value are the system's own); it lists the preferred file's tracks
/// (`ItemTrackMenu`), marks the one playback would start with, and keeps a pick for this title only
/// (`StartTrackChoice.keep`), which the player applies when the file is opened.
struct TrackChoiceMenu: View {
    enum Kind { case audio, subtitles }

    let kind: Kind
    let itemID: Int64
    let seriesTitle: String?
    let tracks: FileTrackDetails
    /// Read again after a pick, so the row shows the new value at once.
    @State private var revision = 0

    var body: some View {
        let state = currentState
        let options = kind == .audio ? state.audio : state.subtitles
        let action: ProductAction = kind == .audio ? .audio : .subtitles
        Picker(selection: selection(state)) {
            ForEach(options) { option in
                Text(option.detail.map { "\(option.title), \($0)" } ?? option.title).tag(option.id)
            }
        } label: {
            Label(action.title, systemImage: action.symbol)
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier(kind == .audio ? "product.audio" : "product.subtitles")
    }

    private var currentState: ItemTrackMenuState {
        _ = revision
        return StartTrackChoice.menuState(tracks: tracks, itemID: itemID, seriesTitle: seriesTitle)
    }

    private func selection(_ state: ItemTrackMenuState) -> Binding<String> {
        let options = kind == .audio ? state.audio : state.subtitles
        return Binding(
            get: { options.first(where: \.isSelected)?.id ?? options.first?.id ?? TrackRow.offID },
            set: { id in
                let choice = kind == .audio
                    ? ItemTrackMenu.choosingAudio(id, tracks: tracks, current: state)
                    : ItemTrackMenu.choosingSubtitle(id, tracks: tracks, current: state)
                if let choice { StartTrackChoice.keep(choice, itemID: itemID) }
                revision += 1
            })
    }
}
