import SwiftUI
import AppLogic

/// Draws whatever state a screen is in. Loaded content comes from the caller; every other state is the same everywhere.
struct ScreenStateView<Loaded: Equatable & Sendable, Page: View>: View {
    let state: ViewState<Loaded>
    var onEmptyAction: () -> Void = {}
    var onRetry: () -> Void = {}
    @ViewBuilder var content: (Loaded) -> Page

    var body: some View {
        switch state {
        case .idle, .loading:
            LoadingView()
        case .loaded(let value):
            content(value)
        case .empty(let empty):
            EmptyStateView(empty: empty, action: onEmptyAction)
        case .failed(let error):
            ErrorStateView(error: error, retry: onRetry)
        }
    }
}
