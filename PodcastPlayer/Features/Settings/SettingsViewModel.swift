import Foundation

/// Cache inspection and clearing.
///
/// The brief asks for options to clear the cache, plural. Feeds, images, and
/// history clear independently because they are genuinely different decisions —
/// dumping a hundred megabytes of artwork is not the same as forgetting which
/// shows you follow.
@MainActor
@Observable
final class SettingsViewModel {
    private(set) var statistics: CacheStatistics = .empty
    private(set) var historyCount: Int = 0

    private let cache: CacheManaging
    private let history: FeedHistoryStore

    init(cache: CacheManaging, history: FeedHistoryStore) {
        self.cache = cache
        self.history = history
    }

    var feedCacheText: String { Formatters.feedCount(statistics.cachedFeedCount) }
    var imageCacheText: String { Formatters.byteCount(statistics.imageCacheBytes) }
    var historyText: String { Formatters.addressCount(historyCount) }

    var hasFeedCache: Bool { statistics.cachedFeedCount > 0 }
    var hasImageCache: Bool { statistics.imageCacheBytes > 0 }
    var hasHistory: Bool { historyCount > 0 }

    func refresh() async {
        statistics = await cache.statistics()
        historyCount = await history.history().count
    }

    func clearFeedCache() async {
        await cache.clearFeedCache()
        await refresh()
    }

    func clearImageCache() async {
        await cache.clearImageCache()
        await refresh()
    }

    func clearHistory() async {
        await history.clear()
        await refresh()
    }
}
