import Foundation

/// Screen 2: the podcast and its episodes.
@MainActor
@Observable
final class PodcastDetailViewModel {
    private(set) var state: ViewState<Podcast> = .idle

    private let feedURL: URL
    private let repository: PodcastRepository
    private let player: any AudioPlaying

    init(feedURL: URL, repository: PodcastRepository, player: any AudioPlaying) {
        self.feedURL = feedURL
        self.repository = repository
        self.player = player
    }

    /// Seeds the screen with a podcast screen 1 already fetched, so navigating
    /// in never shows a spinner for data we are holding.
    func prime(with podcast: Podcast) {
        guard case .idle = state else { return }
        state = podcast.episodes.isEmpty ? .empty : .loaded(podcast)
    }

    func load() async {
        guard state.value == nil else { return }
        await fetch(forceRefresh: false)
    }

    func refresh() async {
        await fetch(forceRefresh: true)
    }

    func retry() async {
        await fetch(forceRefresh: false)
    }

    func play(_ episode: Episode) {
        guard let podcast = state.value,
              let index = podcast.episodes.firstIndex(of: episode) else { return }

        // The whole list becomes the queue, not just the tapped episode —
        // otherwise next/previous have nothing to move through.
        player.load(queue: podcast.episodes, startingAt: index, podcast: podcast)
        player.play()
    }

    func isCurrent(_ episode: Episode) -> Bool {
        player.currentEpisode == episode
    }

    private func fetch(forceRefresh: Bool) async {
        // A refresh keeps the current content on screen rather than flashing a
        // spinner over a page the user is already reading.
        if state.value == nil { state = .loading }

        do {
            let podcast = try await repository.podcast(for: feedURL, forceRefresh: forceRefresh)
            state = podcast.episodes.isEmpty ? .empty : .loaded(podcast)
        } catch {
            // A failed refresh must not throw away content we are already
            // showing; the repository has already fallen back to cache where
            // it could.
            if state.value == nil { state = .failed(error) }
        }
    }
}
