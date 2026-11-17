import SwiftUI
import AppLogic

/// An empty screen: title, one sentence, at most one button (wording comes from the view model).
struct EmptyStateView: View {
    let empty: EmptyState
    var action: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(empty.title, systemImage: symbol)
        } description: {
            Text(empty.message)
        } actions: {
            if let title = empty.actionTitle {
                Button(title, action: action)
            }
        }
    }

    private var symbol: String {
        switch empty.reason {
        case .noSources: return "externaldrive.connected.to.line.below"
        case .nothingIndexed: return "tray"
        case .noMatches, .noQuery: return "magnifyingglass"
        case .emptyFolder: return "folder"
        }
    }
}
