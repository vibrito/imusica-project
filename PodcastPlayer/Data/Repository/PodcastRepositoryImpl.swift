import Foundation

/// Composes cache, network, and parser into one stale-while-revalidate policy.
///
/// The policy in one sentence: a fresh cache is served without touching the
/// network, a stale one is revalidated conditionally, and a network failure
/// with any cached copy present serves that copy rather than showing an error.
///
/// That last rule is the one that matters on a train. The user asked for a
/// podcast, we have a podcast, and refusing to show it because a refresh failed
/// would be technically correct and practically useless.
struct PodcastRepositoryImpl: PodcastRepository, CacheManaging {
    private let client: HTTPClient
    private let parser: RSSFeedParser
    private let cache: FeedCacheStore
    private let images: ImageCache
    private let dates: DateProviding
    private let ttl: TimeInterval

    init(
        client: HTTPClient,
        parser: RSSFeedParser = RSSFeedParser(),
        cache: FeedCacheStore,
        images: ImageCache,
        dates: DateProviding = SystemDateProvider(),
        ttl: TimeInterval = 3600
    ) {
        self.client = client
        self.parser = parser
        self.cache = cache
        self.images = images
        self.dates = dates
        self.ttl = ttl
    }

    func podcast(for url: URL, forceRefresh: Bool) async throws(AppError) -> Podcast {
        let cached = try? await cache.entry(for: url)

        if let cached, !forceRefresh, isFresh(cached) {
            return cached.podcast
        }

        do {
            return try await revalidate(url, against: cached)
        } catch {
            // A stale cache beats an error screen.
            if let cached { return cached.podcast }
            throw error
        }
    }

    private func isFresh(_ entry: CachedEntry) -> Bool {
        dates.now.timeIntervalSince(entry.fetchedAt) < ttl
    }

    private func revalidate(_ url: URL, against cached: CachedEntry?) async throws(AppError) -> Podcast {
        let response = try await client.get(url, conditional: cached?.headers)
        let now = dates.now

        switch response {
        case .notModified:
            guard let cached else {
                // A 304 with nothing cached means our validators were wrong.
                // Nothing to show and nothing to fall back on.
                throw .invalidFeed(reason: "the server sent no content")
            }
            try? await cache.touchFetchedAt(url, to: now)
            return cached.podcast

        case .data(let data, let headers):
            let parsed = try parser.parse(data)
            let podcast = Self.podcast(from: parsed, feedURL: url)
            // A cache write failure must not fail the load — the user has their
            // podcast either way, they just pay for it again next time.
            try? await cache.save(podcast, headers: headers, at: now)
            return podcast
        }
    }

    /// Maps parser output into the domain, applying the guid fallback.
    private static func podcast(from feed: ParsedFeed, feedURL: URL) -> Podcast {
        Podcast(
            feedURL: feedURL,
            title: feed.title,
            description: feed.description,
            author: feed.author,
            imageURL: feed.imageURL,
            categories: feed.categories,
            episodes: feed.items.map { item in
                Episode(
                    id: item.guid ?? item.audioURL.absoluteString,
                    title: item.title,
                    description: item.description,
                    audioURL: item.audioURL,
                    duration: item.duration,
                    publishedAt: item.publishedAt,
                    imageURL: item.imageURL ?? feed.imageURL
                )
            }
        )
    }

    // MARK: - CacheManaging

    func statistics() async -> CacheStatistics {
        CacheStatistics(
            cachedFeedCount: (try? await cache.feedCount()) ?? 0,
            imageCacheBytes: await images.diskUsageBytes()
        )
    }

    func clearFeedCache() async {
        try? await cache.clear()
    }

    func clearImageCache() async {
        await images.clear()
    }
}
