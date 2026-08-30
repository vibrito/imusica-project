import SwiftUI

/// Renders a `ViewState` the same way on every screen.
///
/// Loading, empty, and error are the states developers reach for last and users
/// hit first. Centralising them means a new screen gets all three for free, and
/// none of them can quietly drift out of step with the others.
struct StateView<T: Equatable, Content: View>: View {
    let state: ViewState<T>
    var retry: (() -> Void)?
    var emptyMessage: String = "Nothing here yet"
    @ViewBuilder var content: (T) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("state.loading")
                .accessibilityLabel("Loading")

        case .loaded(let value):
            content(value)

        case .empty:
            ContentUnavailableView(
                emptyMessage,
                systemImage: "waveform.slash"
            )
            .accessibilityIdentifier("state.empty")

        case .failed(let error):
            ContentUnavailableView {
                Label(error.errorDescription ?? "Something went wrong", systemImage: "exclamationmark.triangle")
                    .accessibilityIdentifier("state.errorTitle")
            } description: {
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                }
            } actions: {
                // Only offer Retry where retrying can actually help. A button
                // that fails identically every time teaches users to ignore it.
                if error.isRetryable, let retry {
                    Button("Try Again", action: retry)
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("state.retry")
                }
            }
            .accessibilityIdentifier("state.error")
        }
    }
}
