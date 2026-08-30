import Testing
import Foundation
import SwiftData
@testable import PodcastPlayer

@Suite("FeedCacheStore")
struct FeedCacheStoreTests {

    private func makeStore() throws -> FeedCacheStore {
        FeedCacheStore(modelContainer: try makeInMemoryContainer())
    }

    @Test("Saves a podcast and reads it back intact")
    func savesAndReadsBack() async throws {
        let store = try makeStore()
        try await store.save(samplePodcast, headers: ConditionalHeaders(etag: "\"v1\"", lastModified: nil), at: t0)

        let entry = try await store.entry(for: anyFeedURL)
        #expect(entry?.podcast == samplePodcast)
        #expect(entry?.fetchedAt == t0)
        #expect(entry?.headers.etag == "\"v1\"")
    }

    @Test("Preserves feed order, which is the playback queue order")
    func preservesEpisodeOrder() async throws {
        let store = try makeStore()
        try await store.save(samplePodcast, headers: .none, at: t0)

        let entry = try await store.entry(for: anyFeedURL)
        #expect(entry?.podcast.episodes.map(\.id) == ["guid-1", "guid-2", "guid-3"])
    }

    @Test("Saving the same feed twice replaces rather than duplicates")
    func savingTwiceReplaces() async throws {
        let store = try makeStore()
        try await store.save(samplePodcast, headers: .none, at: t0)
        try await store.save(samplePodcast, headers: .none, at: t0)

        #expect(try await store.feedCount() == 1)
        #expect(try await store.entry(for: anyFeedURL)?.podcast.episodes.count == 3)
    }

    @Test("A re-save drops episodes the publisher withdrew")
    func resaveDropsRemovedEpisodes() async throws {
        let store = try makeStore()
        try await store.save(samplePodcast, headers: .none, at: t0)

        var shortened = samplePodcast
        shortened = Podcast(
            feedURL: samplePodcast.feedURL, title: samplePodcast.title,
            description: samplePodcast.description, author: samplePodcast.author,
            imageURL: samplePodcast.imageURL, categories: samplePodcast.categories,
            episodes: [sampleEpisodes[0]]
        )
        try await store.save(shortened, headers: .none, at: t0)

        #expect(try await store.entry(for: anyFeedURL)?.podcast.episodes.count == 1)
    }

    @Test("Different feeds coexist")
    func differentFeedsCoexist() async throws {
        let store = try makeStore()
        let other = Podcast(feedURL: otherFeedURL, title: "Other", description: nil,
                            author: nil, imageURL: nil, categories: [], episodes: [makeEpisode()])
        try await store.save(samplePodcast, headers: .none, at: t0)
        try await store.save(other, headers: .none, at: t0)

        #expect(try await store.feedCount() == 2)
        #expect(try await store.entry(for: otherFeedURL)?.podcast.title == "Other")
    }

    @Test("An unknown URL returns nil, not an error")
    func unknownURLReturnsNil() async throws {
        #expect(try await makeStore().entry(for: anyFeedURL) == nil)
    }

    @Test("Touching fetchedAt records freshness without rewriting the feed")
    func touchUpdatesTimestampOnly() async throws {
        let store = try makeStore()
        try await store.save(samplePodcast, headers: ConditionalHeaders(etag: "\"v1\"", lastModified: nil), at: t0)

        let later = t0.addingTimeInterval(7200)
        try await store.touchFetchedAt(anyFeedURL, to: later)

        let entry = try await store.entry(for: anyFeedURL)
        #expect(entry?.fetchedAt == later)
        #expect(entry?.headers.etag == "\"v1\"")
        #expect(entry?.podcast == samplePodcast)
    }

    @Test("Touching an unknown feed is a no-op, not a crash")
    func touchUnknownFeedIsHarmless() async throws {
        let store = try makeStore()
        try await store.touchFetchedAt(anyFeedURL, to: t0)
        #expect(try await store.feedCount() == 0)
    }

    @Test("Clearing removes every feed and its episodes")
    func clearRemovesEverything() async throws {
        let store = try makeStore()
        try await store.save(samplePodcast, headers: .none, at: t0)
        try await store.clear()

        #expect(try await store.feedCount() == 0)
        #expect(try await store.entry(for: anyFeedURL) == nil)
    }
}

@Suite("FeedHistoryStore")
struct FeedHistoryStoreTests {

    private func makeStore(dates: DateProviding) async throws -> FeedHistoryStoreImpl {
        let store = FeedHistoryStoreImpl(modelContainer: try makeInMemoryContainer())
        await store.setDateProvider(dates)
        return store
    }

    @Test("Records a URL and returns it")
    func recordsAndReturns() async throws {
        let store = try await makeStore(dates: FixedDateProvider(now: t0))
        await store.record(url: anyFeedURL, title: "Show")

        let history = await store.history()
        #expect(history.map(\.url) == [anyFeedURL])
        #expect(history.first?.title == "Show")
        #expect(history.first?.lastAccessedAt == t0)
    }

    @Test("Returns most recently accessed first")
    func returnsMostRecentFirst() async throws {
        let store = try await makeStore(dates: AdvancingDateProvider(start: t0, step: 60))
        await store.record(url: anyFeedURL, title: nil)
        await store.record(url: otherFeedURL, title: nil)

        #expect(await store.history().map(\.url) == [otherFeedURL, anyFeedURL])
    }

    @Test("Re-recording moves a URL to the top without duplicating it")
    func rerecordingMovesToTop() async throws {
        let store = try await makeStore(dates: AdvancingDateProvider(start: t0, step: 60))
        await store.record(url: anyFeedURL, title: nil)
        await store.record(url: otherFeedURL, title: nil)
        await store.record(url: anyFeedURL, title: "Now titled")

        let history = await store.history()
        #expect(history.map(\.url) == [anyFeedURL, otherFeedURL])
        #expect(history.count == 2)
        #expect(history.first?.title == "Now titled")
    }

    @Test("A later record with no title keeps the name we already had")
    func nilTitleDoesNotEraseAKnownName() async throws {
        let store = try await makeStore(dates: AdvancingDateProvider(start: t0, step: 60))
        await store.record(url: anyFeedURL, title: "Known Name")
        await store.record(url: anyFeedURL, title: nil)

        #expect(await store.history().first?.title == "Known Name")
    }

    @Test("History is capped so screen 1 stays a list, not an archive")
    func historyIsCapped() async throws {
        let store = try await makeStore(dates: AdvancingDateProvider(start: t0, step: 60))
        for index in 0..<(FeedHistoryStoreImpl.limit + 5) {
            await store.record(url: URL(string: "https://example.test/\(index).xml")!, title: nil)
        }

        let history = await store.history()
        #expect(history.count == FeedHistoryStoreImpl.limit)
        // The oldest entries are the ones dropped.
        #expect(history.last?.url == URL(string: "https://example.test/5.xml"))
    }

    @Test("Clearing empties the history")
    func clearEmptiesHistory() async throws {
        let store = try await makeStore(dates: FixedDateProvider(now: t0))
        await store.record(url: anyFeedURL, title: nil)
        await store.clear()

        #expect(await store.history().isEmpty)
    }
}
