import Foundation

/// Screen 1: enter a feed URL, or pick one used before.
@MainActor
@Observable
final class FeedSourceViewModel {
    var urlText: String = ""
    private(set) var state: ViewState<Podcast> = .idle
    private(set) var history: [FeedHistoryItem] = []

    private let repository: PodcastRepository
    private let historyStore: FeedHistoryStore
    /// The URL of the load in flight or just completed, so retry knows what to
    /// repeat even after the text field has been edited.
    private var pendingURL: URL?

    init(repository: PodcastRepository, history: FeedHistoryStore) {
        self.repository = repository
        self.historyStore = history
    }

    var canSubmit: Bool {
        !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !state.isLoading
    }

    func loadHistory() async {
        history = await historyStore.history()
    }

    func submit() async {
        guard let url = Self.normalized(urlText) else {
            state = .failed(.invalidURL)
            return
        }
        await load(url)
    }

    func select(_ item: FeedHistoryItem) async {
        urlText = item.url.absoluteString
        await load(item.url)
    }

    func retry() async {
        guard let pendingURL else { return }
        await load(pendingURL)
    }

    func clearHistory() async {
        await historyStore.clear()
        history = []
    }

    /// Lets the screen return to its form after a podcast has been opened.
    func reset() {
        state = .idle
    }

    /// Empties the field.
    ///
    /// Also dismisses a failure, because the error describes an address that
    /// no longer exists — leaving it up would have the user reading a
    /// complaint about text they just deleted. A load in flight is left alone;
    /// clearing the field is not a cancel.
    func clear() {
        urlText = ""
        if case .failed = state { state = .idle }
    }

    var canClear: Bool { !urlText.isEmpty }

    private func load(_ url: URL) async {
        pendingURL = url
        state = .loading

        do {
            let podcast = try await repository.podcast(for: url, forceRefresh: false)
            state = podcast.episodes.isEmpty ? .empty : .loaded(podcast)
            // Only successful loads are remembered — a typo does not deserve a
            // permanent place in the user's history.
            await historyStore.record(url: url, title: podcast.title)
            await loadHistory()
        } catch {
            state = .failed(error)
        }
    }

    /// Turns what the user typed into a URL worth attempting.
    ///
    /// People paste feed addresses without a scheme constantly. Assuming https
    /// costs nothing and removes the most common reason a valid feed appears
    /// broken.
    static func normalized(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"

        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host(), host.contains(".")
        else { return nil }

        return url
    }
}
