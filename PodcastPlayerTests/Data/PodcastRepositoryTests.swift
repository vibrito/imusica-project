import Testing
import Foundation
@testable import PodcastPlayer

@Suite("PodcastRepository")
struct PodcastRepositoryTests {

    private struct SUT {
        let repository: PodcastRepositoryImpl
        let cache: FeedCacheStore
        let client: FakeHTTPClient
        let directory: URL
    }

    private func makeSUT(
        client: FakeHTTPClient,
        now: Date = t0,
        ttl: TimeInterval = 3600
    ) throws -> SUT {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RepoTests-\(UUID().uuidString)", isDirectory: true)
        let cache = FeedCacheStore(modelContainer: try makeInMemoryContainer())
        let images = ImageCache(client: client, directory: directory)

        return SUT(
            repository: PodcastRepositoryImpl(
                client: client, cache: cache, images: images,
                dates: FixedDateProvider(now: now), ttl: ttl
            ),
            cache: cache, client: client, directory: directory
        )
    }

    private func feedXML(episodeCount: Int) -> Data {
        let items = (1...episodeCount).map { index in
            """
              <item>
                <guid>guid-\(index)</guid>
                <title>Episode \(index)</title>
                <itunes:duration>30:00</itunes:duration>
                <enclosure url="https://example.test/\(index).mp3" type="audio/mpeg"/>
              </item>
            """
        }.joined(separator: "\n")

        return Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
          <channel>
            <title>Sample Podcast</title>
            <itunes:author>An Author</itunes:author>
            <itunes:image href="https://example.test/cover.jpg"/>
        \(items)
          </channel>
        </rss>
        """.utf8)
    }

    // MARK: - Freshness

    @Test("A fresh cache is served without touching the network")
    func freshCacheSkipsNetwork() async throws {
        let sut = try makeSUT(client: FakeHTTPClient(data: feedXML(episodeCount: 2)), now: t0)
        try await sut.cache.save(samplePodcast, headers: .none, at: t0)

        let podcast = try await sut.repository.podcast(for: anyFeedURL, forceRefresh: false)

        #expect(podcast == samplePodcast)
        #expect(sut.client.requestCount == 0)
    }

    @Test("An expired cache is revalidated with its stored validators")
    func staleCacheRevalidatesConditionally() async throws {
        let sut = try makeSUT(
            client: FakeHTTPClient(result: .success(.notModified)),
            now: t0.addingTimeInterval(7200)
        )
        try await sut.cache.save(
            samplePodcast,
            headers: ConditionalHeaders(etag: "\"v1\"", lastModified: nil),
            at: t0
        )

        let podcast = try await sut.repository.podcast(for: anyFeedURL, forceRefresh: false)

        #expect(sut.client.requestCount == 1)
        #expect(sut.client.lastConditional?.etag == "\"v1\"")
        #expect(podcast == samplePodcast)
    }

    @Test("A 304 refreshes the timestamp without rewriting the feed")
    func notModifiedTouchesTimestamp() async throws {
        let now = t0.addingTimeInterval(7200)
        let sut = try makeSUT(client: FakeHTTPClient(result: .success(.notModified)), now: now)
        try await sut.cache.save(
            samplePodcast,
            headers: ConditionalHeaders(etag: "\"v1\"", lastModified: nil),
            at: t0
        )

        _ = try await sut.repository.podcast(for: anyFeedURL, forceRefresh: false)

        #expect(try await sut.cache.entry(for: anyFeedURL)?.fetchedAt == now)
    }

    @Test("A changed feed replaces the cache and its validators")
    func changedFeedReplacesCache() async throws {
        let sut = try makeSUT(
            client: FakeHTTPClient(result: .success(.data(
                feedXML(episodeCount: 2),
                ConditionalHeaders(etag: "\"v2\"", lastModified: nil)
            ))),
            now: t0.addingTimeInterval(7200)
        )
        try await sut.cache.save(
            samplePodcast,
            headers: ConditionalHeaders(etag: "\"v1\"", lastModified: nil),
            at: t0
        )

        let podcast = try await sut.repository.podcast(for: anyFeedURL, forceRefresh: false)

        #expect(podcast.episodes.count == 2)
        #expect(try await sut.cache.entry(for: anyFeedURL)?.headers.etag == "\"v2\"")
    }

    @Test("Force refresh bypasses an otherwise fresh cache")
    func forceRefreshBypassesFreshCache() async throws {
        let sut = try makeSUT(
            client: FakeHTTPClient(result: .success(.data(feedXML(episodeCount: 2), .none))),
            now: t0
        )
        try await sut.cache.save(samplePodcast, headers: .none, at: t0)

        _ = try await sut.repository.podcast(for: anyFeedURL, forceRefresh: true)

        #expect(sut.client.requestCount == 1)
    }

    // MARK: - Cold start

    @Test("With no cache, the feed is fetched and stored")
    func coldStartFetchesAndCaches() async throws {
        let sut = try makeSUT(
            client: FakeHTTPClient(result: .success(.data(
                feedXML(episodeCount: 3),
                ConditionalHeaders(etag: "\"v1\"", lastModified: nil)
            )))
        )

        let podcast = try await sut.repository.podcast(for: anyFeedURL, forceRefresh: false)

        #expect(podcast.title == "Sample Podcast")
        #expect(podcast.author == "An Author")
        #expect(podcast.episodes.count == 3)
        #expect(try await sut.cache.entry(for: anyFeedURL)?.podcast == podcast)
    }

    @Test("Episodes inherit the podcast artwork when they have none of their own")
    func episodesInheritPodcastArtwork() async throws {
        let sut = try makeSUT(client: FakeHTTPClient(data: feedXML(episodeCount: 1)))

        let podcast = try await sut.repository.podcast(for: anyFeedURL, forceRefresh: false)

        #expect(podcast.episodes.first?.imageURL == podcast.imageURL)
    }

    // MARK: - Failure handling

    @Test("Offline with a cached copy serves the cache instead of failing")
    func offlineWithCacheServesCache() async throws {
        let sut = try makeSUT(
            client: FakeHTTPClient(error: .offline),
            now: t0.addingTimeInterval(7200)
        )
        try await sut.cache.save(samplePodcast, headers: .none, at: t0)

        #expect(try await sut.repository.podcast(for: anyFeedURL, forceRefresh: false) == samplePodcast)
    }

    @Test("Offline with no cache propagates the error")
    func offlineWithoutCachePropagates() async throws {
        let sut = try makeSUT(client: FakeHTTPClient(error: .offline))

        await #expect(throws: AppError.offline) {
            try await sut.repository.podcast(for: anyFeedURL, forceRefresh: false)
        }
    }

    @Test("Even a forced refresh falls back to the cache when the network fails")
    func forcedRefreshFallsBackToCache() async throws {
        let sut = try makeSUT(client: FakeHTTPClient(error: .network(statusCode: 500)))
        try await sut.cache.save(samplePodcast, headers: .none, at: t0)

        #expect(try await sut.repository.podcast(for: anyFeedURL, forceRefresh: true) == samplePodcast)
    }

    @Test("A feed that stops parsing falls back to the last good copy")
    func brokenFeedFallsBackToCache() async throws {
        let sut = try makeSUT(
            client: FakeHTTPClient(data: Data("<not xml".utf8)),
            now: t0.addingTimeInterval(7200)
        )
        try await sut.cache.save(samplePodcast, headers: .none, at: t0)

        #expect(try await sut.repository.podcast(for: anyFeedURL, forceRefresh: false) == samplePodcast)
    }

    @Test("A broken feed with no cache surfaces the parse error")
    func brokenFeedWithoutCachePropagates() async throws {
        let sut = try makeSUT(client: FakeHTTPClient(data: Data("<not xml".utf8)))

        await #expect(throws: AppError.self) {
            try await sut.repository.podcast(for: anyFeedURL, forceRefresh: false)
        }
    }

    @Test("A 404 with no cache surfaces as notFound")
    func notFoundPropagates() async throws {
        let sut = try makeSUT(client: FakeHTTPClient(error: .notFound))

        await #expect(throws: AppError.notFound) {
            try await sut.repository.podcast(for: anyFeedURL, forceRefresh: false)
        }
    }

    // MARK: - Cache management

    @Test("Statistics report the cached feed count")
    func statisticsReportFeedCount() async throws {
        let sut = try makeSUT(client: FakeHTTPClient(result: .success(.notModified)))
        try await sut.cache.save(samplePodcast, headers: .none, at: t0)

        #expect(await sut.repository.statistics().cachedFeedCount == 1)
    }

    @Test("Clearing the feed cache leaves nothing behind")
    func clearFeedCacheEmptiesIt() async throws {
        let sut = try makeSUT(client: FakeHTTPClient(result: .success(.notModified)))
        try await sut.cache.save(samplePodcast, headers: .none, at: t0)

        await sut.repository.clearFeedCache()

        #expect(await sut.repository.statistics().cachedFeedCount == 0)
    }

    @Test("Clearing images does not clear feeds")
    func clearingImagesLeavesFeedsAlone() async throws {
        let sut = try makeSUT(client: FakeHTTPClient(result: .success(.notModified)))
        try await sut.cache.save(samplePodcast, headers: .none, at: t0)

        await sut.repository.clearImageCache()

        #expect(await sut.repository.statistics().cachedFeedCount == 1)
    }
}
