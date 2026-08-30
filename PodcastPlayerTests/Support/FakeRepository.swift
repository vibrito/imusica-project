import Foundation
@testable import PodcastPlayer

final class FakeRepository: PodcastRepository, CacheManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<Podcast, AppError>]
    private var _requests: [(url: URL, forceRefresh: Bool)] = []
    private var _statistics: CacheStatistics

    private(set) var clearFeedCallCount = 0
    private(set) var clearImageCallCount = 0

    init(results: [Result<Podcast, AppError>] = [], statistics: CacheStatistics = .empty) {
        self.results = results
        self._statistics = statistics
    }

    convenience init(result: Result<Podcast, AppError>) {
        self.init(results: [result])
    }

    var callCount: Int { lock.withLock { _requests.count } }
    var lastURL: URL? { lock.withLock { _requests.last?.url } }
    var lastForceRefresh: Bool? { lock.withLock { _requests.last?.forceRefresh } }

    func podcast(for url: URL, forceRefresh: Bool) async throws(AppError) -> Podcast {
        let result: Result<Podcast, AppError>? = lock.withLock {
            _requests.append((url, forceRefresh))
            guard !results.isEmpty else { return nil }
            return results.count > 1 ? results.removeFirst() : results[0]
        }

        switch result {
        case .success(let podcast): return podcast
        case .failure(let error): throw error
        case nil: throw .notFound
        }
    }

    func statistics() async -> CacheStatistics { lock.withLock { _statistics } }

    func clearFeedCache() async {
        lock.withLock {
            clearFeedCallCount += 1
            _statistics = CacheStatistics(cachedFeedCount: 0, imageCacheBytes: _statistics.imageCacheBytes)
        }
    }

    func clearImageCache() async {
        lock.withLock {
            clearImageCallCount += 1
            _statistics = CacheStatistics(cachedFeedCount: _statistics.cachedFeedCount, imageCacheBytes: 0)
        }
    }
}

final class FakeHistoryStore: FeedHistoryStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [FeedHistoryItem]
    private(set) var recorded: [(url: URL, title: String?)] = []
    private(set) var clearCallCount = 0

    init(items: [FeedHistoryItem] = []) {
        self.items = items
    }

    func history() async -> [FeedHistoryItem] { lock.withLock { items } }

    func record(url: URL, title: String?) async {
        lock.withLock {
            recorded.append((url, title))
            items.removeAll { $0.url == url }
            items.insert(FeedHistoryItem(url: url, title: title, lastAccessedAt: t0), at: 0)
        }
    }

    func clear() async {
        lock.withLock {
            clearCallCount += 1
            items = []
        }
    }
}
