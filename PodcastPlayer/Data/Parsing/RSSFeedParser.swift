import Foundation

/// A parsed channel, still in data-layer terms.
struct ParsedFeed: Equatable, Sendable {
    let title: String
    let description: String?
    let author: String?
    let imageURL: URL?
    let categories: [String]
    let items: [ParsedItem]
}

/// A parsed, playable item. Entries without media never become one.
struct ParsedItem: Equatable, Sendable {
    let guid: String?
    let title: String
    let description: String?
    let audioURL: URL
    let duration: TimeInterval?
    let publishedAt: Date?
    let imageURL: URL?
}

/// Parses RSS 2.0 with the iTunes podcast namespace, per
/// https://podcasters.apple.com/support/823-podcast-requirements
///
/// Streaming (`XMLParser` is SAX), so a feed with hundreds of episodes never
/// exists in memory twice.
///
/// The parser is deliberately lenient. Publishers omit fields constantly, and a
/// feed missing an author or a duration is still perfectly listenable — so
/// every optional field degrades to nil, and an item with no media is skipped
/// rather than being allowed to fail the whole feed. Only two things are fatal:
/// XML we cannot read at all, and a channel that yields no playable episodes.
struct RSSFeedParser: Sendable {

    func parse(_ data: Data) throws(AppError) -> ParsedFeed {
        guard !data.isEmpty else {
            throw .invalidFeed(reason: "the response was empty")
        }

        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false

        guard parser.parse() else {
            let reason = parser.parserError?.localizedDescription ?? "unreadable XML"
            throw .invalidFeed(reason: reason.lowercased())
        }

        guard let title = delegate.channelTitle?.trimmed, !title.isEmpty else {
            throw .invalidFeed(reason: "no podcast channel found")
        }

        guard !delegate.items.isEmpty else {
            throw .noEpisodes
        }

        return ParsedFeed(
            title: title,
            description: delegate.channelDescription.flatMap(displayText),
            author: delegate.channelAuthor?.trimmed.nonEmpty,
            imageURL: delegate.channelImageURL,
            categories: delegate.categories,
            items: delegate.items
        )
    }

    private func displayText(_ raw: String) -> String? {
        HTMLStripper.plainText(from: raw).nonEmpty
    }
}

// MARK: - SAX delegate

private final class Delegate: NSObject, XMLParserDelegate {

    // Channel-level accumulators.
    var channelTitle: String?
    var channelDescription: String?
    var channelAuthor: String?
    var channelImageURL: URL?
    var categories: [String] = []
    var items: [ParsedItem] = []

    /// The element path, so `<title>` inside `<item>` is never mistaken for the
    /// channel's own title.
    private var path: [String] = []
    private var text = ""

    /// Set while inside `<item>`; nil at channel level.
    private var item: ItemAccumulator?
    /// `<image><url>` at channel level, used only if `itunes:image` is absent.
    private var channelImageFallback: URL?
    private var didFindRSSRoot = false

    private struct ItemAccumulator {
        var guid: String?
        var title: String?
        var description: String?
        var summary: String?
        var audioURL: URL?
        var duration: String?
        var pubDate: String?
        var imageURL: URL?
    }

    private var isInsideItem: Bool { item != nil }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName: String?,
                attributes: [String: String]) {
        let name = elementName.lowercased()
        path.append(name)
        text = ""

        switch name {
        case "rss", "feed":
            didFindRSSRoot = true

        case "item", "entry":
            item = ItemAccumulator()

        case "itunes:image":
            let href = attributes["href"].flatMap(URL.init(string:))
            if isInsideItem {
                item?.imageURL = href
            } else if href != nil {
                channelImageURL = href
            }

        case "enclosure", "media:content":
            // Only audio counts. Feeds attach images and video here too.
            let type = attributes["type"]?.lowercased() ?? ""
            let isAudio = type.hasPrefix("audio") || type.isEmpty
            if isInsideItem, isAudio, item?.audioURL == nil {
                item?.audioURL = attributes["url"].flatMap(URL.init(string:))
            }

        case "itunes:category":
            // Nested categories repeat the element, so collect at any depth.
            if !isInsideItem, let text = attributes["text"]?.trimmed.nonEmpty {
                categories.append(text)
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        // Descriptions almost always arrive as CDATA.
        if let string = String(data: CDATABlock, encoding: .utf8) {
            text += string
        }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName: String?) {
        defer {
            if !path.isEmpty { path.removeLast() }
            text = ""
        }

        let name = elementName.lowercased()
        let value = text.trimmed

        if name == "item" || name == "entry" {
            if let finished = item.flatMap(build) { items.append(finished) }
            item = nil
            return
        }

        if isInsideItem {
            switch name {
            case "guid": item?.guid = value.nonEmpty
            case "title": item?.title = value.nonEmpty
            case "description", "content:encoded": item?.description = value.nonEmpty
            case "itunes:summary": item?.summary = value.nonEmpty
            case "itunes:duration": item?.duration = value.nonEmpty
            case "pubdate", "published": item?.pubDate = value.nonEmpty
            default: break
            }
            return
        }

        // Channel level.
        switch name {
        case "title" where isDirectChannelChild:
            channelTitle = channelTitle ?? value.nonEmpty
        case "description", "itunes:summary":
            channelDescription = channelDescription ?? value.nonEmpty
        case "itunes:author", "managingeditor":
            channelAuthor = channelAuthor ?? value.nonEmpty
        case "url" where path.contains("image"):
            channelImageFallback = channelImageFallback ?? URL(string: value)
        default:
            break
        }
    }

    /// True when the element closing is a direct child of `<channel>` — the
    /// path is `[rss, channel, title]`, not `[rss, channel, image, title]`.
    private var isDirectChannelChild: Bool {
        path.count >= 2 && path[path.count - 2] == "channel"
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        // `itunes:image` wins; `<image><url>` is the fallback.
        channelImageURL = channelImageURL ?? channelImageFallback

        // Well-formed XML that never declared an RSS root is not a feed.
        if !didFindRSSRoot { channelTitle = nil }
    }

    /// Turns an accumulator into an episode, or discards it.
    ///
    /// No media means nothing to play. Dropping one entry is always better than
    /// failing the whole feed over it.
    private func build(_ accumulator: ItemAccumulator) -> ParsedItem? {
        guard let audioURL = accumulator.audioURL else { return nil }

        let rawDescription = accumulator.description ?? accumulator.summary

        return ParsedItem(
            guid: accumulator.guid,
            title: accumulator.title.map { HTMLStripper.plainText(from: $0) }?.nonEmpty
                ?? audioURL.lastPathComponent,
            description: rawDescription.map { HTMLStripper.plainText(from: $0) }?.nonEmpty,
            audioURL: audioURL,
            duration: DurationParser.parse(accumulator.duration),
            publishedAt: DateParser.parse(accumulator.pubDate),
            imageURL: accumulator.imageURL
        )
    }
}

// MARK: - Dates

/// Parses the publication date formats podcast feeds use.
///
/// RFC 822 is what the RSS spec mandates, but ISO 8601 appears often enough
/// that falling back to it costs nothing and saves the date.
enum DateParser {
    // Formatters are expensive to build and are only ever read here, never
    // reconfigured. Apple documents formatting as thread-safe under that
    // restriction, so sharing them beats allocating one per episode.
    nonisolated(unsafe) private static let rfc822: [DateFormatter] = {
        ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, dd MMM yyyy HH:mm zzz", "dd MMM yyyy HH:mm:ss zzz"]
            .map { format in
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = format
                return formatter
            }
    }()

    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let trimmed = raw?.trimmed, !trimmed.isEmpty else { return nil }

        for formatter in rfc822 {
            if let date = formatter.date(from: trimmed) { return date }
        }
        return iso8601.date(from: trimmed)
    }
}

// MARK: - Small helpers

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { isEmpty ? nil : self }
}
