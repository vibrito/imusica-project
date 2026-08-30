import Foundation
import SwiftData

/// A cached feed plus the metadata needed to revalidate it.
struct CachedEntry: Equatable, Sendable {
    let podcast: Podcast
    let fetchedAt: Date
    let headers: ConditionalHeaders
}

/// Persists parsed feeds.
///
/// A `@ModelActor` so every SwiftData access happens on one isolated context —
/// `ModelContext` is not `Sendable`, and sharing one across tasks is the usual
/// way SwiftData code goes wrong under Swift 6 concurrency.
@ModelActor
actor FeedCacheStore {

    func entry(for url: URL) throws -> CachedEntry? {
        guard let feed = try fetchFeed(url) else { return nil }
        return CachedEntry(
            podcast: feed.domainValue,
            fetchedAt: feed.fetchedAt,
            headers: ConditionalHeaders(etag: feed.etag, lastModified: feed.lastModified)
        )
    }

    /// Upserts. Replacing wholesale rather than diffing is deliberate: a feed
    /// is a snapshot, episodes get edited and withdrawn upstream, and merging
    /// would leave deleted episodes behind forever.
    func save(_ podcast: Podcast, headers: ConditionalHeaders, at date: Date) throws {
        if let existing = try fetchFeed(podcast.feedURL) {
            modelContext.delete(existing)
        }

        let feed = CachedFeed(
            feedURL: podcast.feedURL,
            title: podcast.title,
            feedDescription: podcast.description,
            author: podcast.author,
            imageURL: podcast.imageURL,
            categories: podcast.categories,
            fetchedAt: date,
            etag: headers.etag,
            lastModified: headers.lastModified,
            episodes: podcast.episodes.enumerated().map { CachedEpisode($1, order: $0) }
        )

        modelContext.insert(feed)
        try modelContext.save()
    }

    /// Records that a 304 confirmed the cached copy, without rewriting it.
    func touchFetchedAt(_ url: URL, to date: Date) throws {
        guard let feed = try fetchFeed(url) else { return }
        feed.fetchedAt = date
        try modelContext.save()
    }

    func feedCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<CachedFeed>())
    }

    func clear() throws {
        try modelContext.delete(model: CachedFeed.self)
        try modelContext.delete(model: CachedEpisode.self)
        try modelContext.save()
    }

    private func fetchFeed(_ url: URL) throws -> CachedFeed? {
        var descriptor = FetchDescriptor<CachedFeed>(
            predicate: #Predicate { $0.feedURL == url }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

// MARK: - Container

enum PersistenceContainer {
    static let schema = Schema([CachedFeed.self, CachedEpisode.self, FeedHistoryEntry.self])

    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
