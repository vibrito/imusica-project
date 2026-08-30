import Foundation

// The boundaries of the app. Feature code depends on these and nothing else,
// which is what makes every ViewModel testable against a hand-written fake.

/// Loads podcasts, transparently deciding between cache and network.
protocol PodcastRepository: Sendable {
    /// - Parameter forceRefresh: skip the freshness check and revalidate now.
    ///   Used by pull-to-refresh.
    func podcast(for url: URL, forceRefresh: Bool) async throws(AppError) -> Podcast
}

/// Loads image data, transparently caching it.
///
/// Returns nil rather than throwing: a missing image is a cosmetic problem, and
/// should never put a screen into an error state.
protocol ImageLoading: Sendable {
    func image(for url: URL) async -> Data?
}

/// Playback and queue navigation.
@MainActor
protocol AudioPlaying: AnyObject {
    var currentEpisode: Episode? { get }
    var currentPodcast: Podcast? { get }
    var isPlaying: Bool { get }
    var elapsed: TimeInterval { get }
    var duration: TimeInterval { get }
    var canGoNext: Bool { get }
    var canGoPrevious: Bool { get }

    /// Loads a queue and begins at `index`.
    ///
    /// The whole episode list is passed, not just one episode, because
    /// next/previous are meaningless without it.
    func load(queue: [Episode], startingAt index: Int, podcast: Podcast)
    func play()
    func pause()
    func next()
    func previous()
    func seek(to time: TimeInterval)
}

/// A previously used feed URL.
struct FeedHistoryItem: Equatable, Sendable, Identifiable {
    var id: URL { url }
    let url: URL
    /// Nil until the feed has loaded successfully at least once.
    let title: String?
    let lastAccessedAt: Date
}

/// Remembers which feeds the user has opened, most recent first.
protocol FeedHistoryStore: Sendable {
    func history() async -> [FeedHistoryItem]
    func record(url: URL, title: String?) async
    func clear() async
}

/// What the Settings screen reports.
struct CacheStatistics: Equatable, Sendable {
    let cachedFeedCount: Int
    let imageCacheBytes: Int64

    static let empty = CacheStatistics(cachedFeedCount: 0, imageCacheBytes: 0)
}

/// Cache inspection and clearing.
///
/// The two caches clear independently — the brief asks for options, plural, and
/// dumping megabytes of artwork is a different decision from dropping feeds.
protocol CacheManaging: Sendable {
    func statistics() async -> CacheStatistics
    func clearFeedCache() async
    func clearImageCache() async
}
