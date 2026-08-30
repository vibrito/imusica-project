import Testing
import Foundation
@testable import PodcastPlayer

@MainActor
@Suite("SettingsViewModel")
struct SettingsViewModelTests {

    @Test("Refresh loads both cache figures and the history count")
    func refreshLoadsStatistics() async {
        let cache = FakeRepository(statistics: CacheStatistics(cachedFeedCount: 3, imageCacheBytes: 5_242_880))
        let history = FakeHistoryStore(items: [
            FeedHistoryItem(url: anyFeedURL, title: nil, lastAccessedAt: t0)
        ])
        let sut = SettingsViewModel(cache: cache, history: history)

        await sut.refresh()

        #expect(sut.statistics.cachedFeedCount == 3)
        #expect(sut.feedCacheText == "3 feeds")
        #expect(sut.imageCacheText.contains("MB"))
        #expect(sut.historyText == "1 address")
    }

    @Test("Counts read correctly at one")
    func singularCounts() async {
        let cache = FakeRepository(statistics: CacheStatistics(cachedFeedCount: 1, imageCacheBytes: 0))
        let sut = SettingsViewModel(cache: cache, history: FakeHistoryStore())

        await sut.refresh()

        #expect(sut.feedCacheText == "1 feed")
    }

    @Test("Clearing feeds does not touch images")
    func clearingFeedsLeavesImages() async {
        let cache = FakeRepository(statistics: CacheStatistics(cachedFeedCount: 3, imageCacheBytes: 1024))
        let sut = SettingsViewModel(cache: cache, history: FakeHistoryStore())
        await sut.refresh()

        await sut.clearFeedCache()

        #expect(cache.clearFeedCallCount == 1)
        #expect(cache.clearImageCallCount == 0)
        #expect(sut.statistics.cachedFeedCount == 0)
        #expect(sut.statistics.imageCacheBytes == 1024)
    }

    @Test("Clearing images does not touch feeds")
    func clearingImagesLeavesFeeds() async {
        let cache = FakeRepository(statistics: CacheStatistics(cachedFeedCount: 3, imageCacheBytes: 1024))
        let sut = SettingsViewModel(cache: cache, history: FakeHistoryStore())
        await sut.refresh()

        await sut.clearImageCache()

        #expect(cache.clearImageCallCount == 1)
        #expect(cache.clearFeedCallCount == 0)
        #expect(sut.statistics.imageCacheBytes == 0)
        #expect(sut.statistics.cachedFeedCount == 3)
    }

    @Test("Clearing history leaves both caches alone")
    func clearingHistoryLeavesCaches() async {
        let cache = FakeRepository(statistics: CacheStatistics(cachedFeedCount: 3, imageCacheBytes: 1024))
        let history = FakeHistoryStore(items: [
            FeedHistoryItem(url: anyFeedURL, title: nil, lastAccessedAt: t0)
        ])
        let sut = SettingsViewModel(cache: cache, history: history)
        await sut.refresh()

        await sut.clearHistory()

        #expect(history.clearCallCount == 1)
        #expect(cache.clearFeedCallCount == 0)
        #expect(cache.clearImageCallCount == 0)
        #expect(sut.historyCount == 0)
        #expect(sut.statistics.cachedFeedCount == 3)
    }

    @Test("Nothing-to-clear is reported so the buttons can disable themselves")
    func reportsWhetherThereIsAnythingToClear() async {
        let sut = SettingsViewModel(cache: FakeRepository(statistics: .empty), history: FakeHistoryStore())
        await sut.refresh()

        #expect(!sut.hasFeedCache)
        #expect(!sut.hasImageCache)
        #expect(!sut.hasHistory)
    }
}
