import Foundation
import SwiftData
@testable import PodcastPlayer

// Shared test data. Keeping the sample podcast in one place means a change to
// the domain model breaks one file, not thirty.

let anyFeedURL = URL(string: "https://example.test/feed.xml")!
let otherFeedURL = URL(string: "https://example.test/other.xml")!
let t0 = Date(timeIntervalSince1970: 1_700_000_000)

func makeEpisode(
    id: String = "guid-1",
    title: String = "An Episode",
    duration: TimeInterval? = 1800
) -> Episode {
    Episode(
        id: id,
        title: title,
        description: "Episode description",
        audioURL: URL(string: "https://example.test/\(id).mp3")!,
        duration: duration,
        publishedAt: t0,
        imageURL: nil
    )
}

let sampleEpisodes: [Episode] = [
    makeEpisode(id: "guid-1", title: "First"),
    makeEpisode(id: "guid-2", title: "Second"),
    makeEpisode(id: "guid-3", title: "Third"),
]

let samplePodcast = Podcast(
    feedURL: anyFeedURL,
    title: "Sample Podcast",
    description: "A description",
    author: "An Author",
    imageURL: URL(string: "https://example.test/cover.jpg"),
    categories: ["Technology", "Education"],
    episodes: sampleEpisodes
)

func makeInMemoryContainer() throws -> ModelContainer {
    try PersistenceContainer.make(inMemory: true)
}
