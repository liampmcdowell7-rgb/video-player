import SwiftUI
import AppLogic

/// A failed screen: one calm sentence and a Try Again button.
struct ErrorStateView: View {
    let error: ErrorState
    var retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(error.title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.message)
        } actions: {
            Button(error.retryTitle, action: retry)
        }
    }
}
