import Testing
import Foundation
@testable import PodcastPlayer

/// Loads a checked-in fixture. Tests never touch the network — the fixtures
/// are the contract, and they keep the suite fast and deterministic.
private func fixture(_ name: String) throws -> Data {
    let url = try #require(
        Bundle.tests.url(forResource: name, withExtension: "xml"),
        "Fixture \(name).xml is missing from the test bundle"
    )
    return try Data(contentsOf: url)
}

@Suite("RSSFeedParser")
struct RSSFeedParserTests {

    // MARK: - The brief's own reference feeds

    @Test("Every reference feed parses into playable episodes",
          arguments: ["la-cotorrisa", "instituto-claro", "geek-nights"])
    func referenceFeedsParse(name: String) throws {
        let feed = try RSSFeedParser().parse(try fixture(name))

        #expect(!feed.title.isEmpty)
        #expect(!feed.items.isEmpty)
        #expect(feed.items.allSatisfy { !$0.title.isEmpty })
        #expect(feed.imageURL != nil)
    }

    @Test("Reference feeds carry the metadata the detail screen needs",
          arguments: ["la-cotorrisa", "instituto-claro", "geek-nights"])
    func referenceFeedsCarryDisplayMetadata(name: String) throws {
        let feed = try RSSFeedParser().parse(try fixture(name))

        #expect(feed.author?.isEmpty == false)
        #expect(feed.description?.isEmpty == false)
        #expect(!feed.categories.isEmpty)
        #expect(feed.items.contains { $0.duration != nil })
    }

    @Test("Descriptions come back as display text, not markup",
          arguments: ["la-cotorrisa", "instituto-claro", "geek-nights"])
    func descriptionsAreStripped(name: String) throws {
        let feed = try RSSFeedParser().parse(try fixture(name))
        #expect(feed.description?.contains("<p>") != true)
        #expect(feed.items.allSatisfy { $0.description?.contains("<p>") != true })
    }

    // MARK: - Channel metadata

    @Test("Reads every channel field the detail screen shows")
    func readsChannelMetadata() throws {
        let feed = try RSSFeedParser().parse(try fixture("rich-metadata"))

        #expect(feed.title == "Rich Metadata Show")
        #expect(feed.author == "Ada Lovelace")
        #expect(feed.imageURL == URL(string: "https://example.test/cover.jpg"))
        #expect(feed.description == "A show & its description.")
    }

    @Test("Collects categories, nested ones included")
    func collectsCategories() throws {
        let feed = try RSSFeedParser().parse(try fixture("rich-metadata"))
        #expect(feed.categories.contains("Technology"))
        #expect(feed.categories.contains("Education"))
    }

    // MARK: - Item metadata

    @Test("Reads every item field")
    func readsItemMetadata() throws {
        let feed = try RSSFeedParser().parse(try fixture("rich-metadata"))
        let first = try #require(feed.items.first)

        #expect(first.guid == "episode-001")
        #expect(first.title == "The First Episode")
        #expect(first.description == "Line one.\n\nLine two.")
        #expect(first.audioURL == URL(string: "https://example.test/ep1.mp3"))
        #expect(first.duration == 2700)
        #expect(first.imageURL == URL(string: "https://example.test/ep1.jpg"))
        #expect(first.publishedAt != nil)
    }

    @Test("Parses RFC 822 publication dates")
    func parsesPublicationDates() throws {
        let feed = try RSSFeedParser().parse(try fixture("rich-metadata"))
        let expected = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2025, month: 1, day: 6, hour: 10
        ).date
        #expect(feed.items.first?.publishedAt == expected)
    }

    @Test("Falls back to itunes:summary when description is absent")
    func fallsBackToItunesSummary() throws {
        let feed = try RSSFeedParser().parse(try fixture("rich-metadata"))
        #expect(feed.items.last?.description == "Summary used when description is absent.")
    }

    @Test("Keeps items in feed order")
    func keepsFeedOrder() throws {
        let feed = try RSSFeedParser().parse(try fixture("rich-metadata"))
        #expect(feed.items.map(\.title) == ["The First Episode", "The Second Episode"])
    }

    // MARK: - Durations

    @Test("Reads every duration format and degrades unparseable ones to nil")
    func readsEveryDurationFormat() throws {
        let feed = try RSSFeedParser().parse(try fixture("duration-formats"))
        let byGUID = Dictionary(uniqueKeysWithValues: feed.items.map { ($0.guid ?? "", $0.duration) })

        #expect(byGUID["hhmmss"] == 3723)
        #expect(byGUID["mmss"] == 2550)
        #expect(byGUID["seconds"] == 3672)
        #expect(byGUID["garbage"] == .some(nil))   // present, but with no duration
        #expect(byGUID["absent"] == .some(nil))
    }

    @Test("An unparseable duration never costs us the episode")
    func unparseableDurationKeepsTheEpisode() throws {
        let feed = try RSSFeedParser().parse(try fixture("duration-formats"))
        #expect(feed.items.count == 5)
    }

    // MARK: - Missing and malformed data

    @Test("Absent optional fields are nil, not failures")
    func missingOptionalFieldsDoNotThrow() throws {
        let feed = try RSSFeedParser().parse(try fixture("missing-optional-fields"))

        #expect(feed.author == nil)
        #expect(feed.items.first?.duration == nil)
        #expect(feed.items.first?.description == nil)
        #expect(!feed.items.isEmpty)
    }

    @Test("Falls back from itunes:image to the channel image")
    func fallsBackToChannelImage() throws {
        let feed = try RSSFeedParser().parse(try fixture("missing-optional-fields"))
        #expect(feed.imageURL == URL(string: "https://example.test/channel-image.jpg"))
    }

    @Test("Drops unplayable items instead of failing the whole feed")
    func dropsItemsWithoutEnclosure() throws {
        let feed = try RSSFeedParser().parse(try fixture("missing-optional-fields"))
        #expect(feed.items.count == 2)
        #expect(!feed.items.contains { $0.title.contains("not playable") })
    }

    // The guid -> enclosure-URL fallback lives in the repository's mapper,
    // where a domain Episode.id is required. The parser reports absence
    // faithfully rather than inventing a value.
    @Test("An absent guid is reported as nil rather than guessed at")
    func absentGUIDIsNil() throws {
        let feed = try RSSFeedParser().parse(try fixture("missing-optional-fields"))
        #expect(feed.items.first?.guid == nil)
    }

    @Test("Malformed XML surfaces as invalidFeed")
    func malformedXMLThrowsInvalidFeed() throws {
        let data = try fixture("malformed")
        #expect(throws: AppError.self) {
            try RSSFeedParser().parse(data)
        }
    }

    @Test("Well-formed XML that isn't a feed surfaces as invalidFeed")
    func nonFeedXMLThrowsInvalidFeed() throws {
        let data = try fixture("not-a-feed")
        do {
            _ = try RSSFeedParser().parse(data)
            Issue.record("Expected a thrown error")
        } catch {
            guard case .invalidFeed = error else {
                Issue.record("Expected .invalidFeed, got \(error)")
                return
            }
        }
    }

    @Test("A valid but empty channel surfaces as noEpisodes, not invalidFeed")
    func emptyChannelThrowsNoEpisodes() throws {
        let data = try fixture("empty-channel")
        #expect(throws: AppError.noEpisodes) {
            try RSSFeedParser().parse(data)
        }
    }

    @Test("Empty input surfaces as invalidFeed")
    func emptyDataThrowsInvalidFeed() {
        #expect(throws: AppError.self) {
            try RSSFeedParser().parse(Data())
        }
    }
}
