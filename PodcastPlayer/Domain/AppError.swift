import Foundation

/// The single error type that crosses layer boundaries.
///
/// `URLError`, `XMLParser` failures, and SwiftData errors are all translated
/// into this in the data layer, so feature code never has to reason about
/// transport-level detail — and the UI always has something to say to the user.
enum AppError: Error, Equatable, Sendable, LocalizedError {
    /// The text the user typed is not a usable URL.
    case invalidURL
    /// The device has no usable connection.
    case offline
    /// The server answered, but not successfully.
    case network(statusCode: Int?)
    /// The feed URL is valid but nothing is published there.
    case notFound
    /// The response was not a podcast feed we can read.
    case invalidFeed(reason: String)
    /// A valid feed that contains no playable episodes.
    case noEpisodes
    /// Playback could not start or continue.
    case playbackFailed

    /// Whether offering a Retry button makes sense.
    ///
    /// Retrying a malformed feed or a mistyped URL will fail identically every
    /// time; offering the button anyway trains users to distrust it.
    var isRetryable: Bool {
        switch self {
        case .offline, .network, .playbackFailed:
            true
        case .invalidURL, .notFound, .invalidFeed, .noEpisodes:
            false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "That doesn't look like a valid address"
        case .offline:
            "You're offline"
        case .network(let statusCode):
            statusCode.map { "The server responded with an error (\($0))" }
                ?? "Couldn't reach the server"
        case .notFound:
            "No feed at that address"
        case .invalidFeed:
            "That isn't a podcast feed"
        case .noEpisodes:
            "This podcast has no episodes yet"
        case .playbackFailed:
            "Couldn't play this episode"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidURL:
            "Check the address and try again. It should look like https://example.com/feed.xml"
        case .offline:
            "Check your connection and try again."
        case .network:
            "The podcast host may be having trouble. Try again in a moment."
        case .notFound:
            "Double-check the address, or try one of the sample feeds."
        case .invalidFeed(let reason):
            "The address returned something we couldn't read (\(reason))."
        case .noEpisodes:
            "Check back once the publisher releases an episode."
        case .playbackFailed:
            "The audio file may be unavailable. Try another episode."
        }
    }
}
