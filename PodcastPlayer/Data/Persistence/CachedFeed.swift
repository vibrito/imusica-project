import Foundation
import SwiftData

/// A cached podcast feed.
///
/// These types never leave the data layer — `FeedCacheStore` maps them to
/// domain values at its boundary. That is what keeps SwiftData out of the
/// ViewModels and makes the persistence layer replaceable.
@Model
final class CachedFeed {
    #Index<CachedFeed>([\.feedURL])
    @Attribute(.unique) var feedURL: URL

    var title: String
    var feedDescription: String?
    var author: String?
    var imageURL: URL?
    var categories: [String]

    /// When the feed was last confirmed current — refreshed on a 304 as well
    /// as on a full fetch, since both prove freshness.
    var fetchedAt: Date
    var etag: String?
    var lastModified: String?

    @Relationship(deleteRule: .cascade, inverse: \CachedEpisode.feed)
    var episodes: [CachedEpisode]

    init(
        feedURL: URL,
        title: String,
        feedDescription: String?,
        author: String?,
        imageURL: URL?,
        categories: [String],
        fetchedAt: Date,
        etag: String?,
        lastModified: String?,
        episodes: [CachedEpisode] = []
    ) {
        self.feedURL = feedURL
        self.title = title
        self.feedDescription = feedDescription
        self.author = author
        self.imageURL = imageURL
        self.categories = categories
        self.fetchedAt = fetchedAt
        self.etag = etag
        self.lastModified = lastModified
        self.episodes = episodes
    }
}

@Model
final class CachedEpisode {
    var episodeID: String
    var title: String
    var episodeDescription: String?
    var audioURL: URL
    var duration: TimeInterval?
    var publishedAt: Date?
    var imageURL: URL?

    /// Feed order is meaningful — it is the playback queue order — and is not
    /// recoverable from publication dates, which feeds sometimes omit.
    var order: Int

    var feed: CachedFeed?

    init(
        episodeID: String,
        title: String,
        episodeDescription: String?,
        audioURL: URL,
        duration: TimeInterval?,
        publishedAt: Date?,
        imageURL: URL?,
        order: Int
    ) {
        self.episodeID = episodeID
        self.title = title
        self.episodeDescription = episodeDescription
        self.audioURL = audioURL
        self.duration = duration
        self.publishedAt = publishedAt
        self.imageURL = imageURL
        self.order = order
    }
}

// MARK: - Mapping to and from the domain

extension CachedEpisode {
    var domainValue: Episode {
        Episode(
            id: episodeID,
            title: title,
            description: episodeDescription,
            audioURL: audioURL,
            duration: duration,
            publishedAt: publishedAt,
            imageURL: imageURL
        )
    }

    convenience init(_ episode: Episode, order: Int) {
        self.init(
            episodeID: episode.id,
            title: episode.title,
            episodeDescription: episode.description,
            audioURL: episode.audioURL,
            duration: episode.duration,
            publishedAt: episode.publishedAt,
            imageURL: episode.imageURL,
            order: order
        )
    }
}

extension CachedFeed {
    var domainValue: Podcast {
        Podcast(
            feedURL: feedURL,
            title: title,
            description: feedDescription,
            author: author,
            imageURL: imageURL,
            categories: categories,
            episodes: episodes.sorted { $0.order < $1.order }.map(\.domainValue)
        )
    }
}
