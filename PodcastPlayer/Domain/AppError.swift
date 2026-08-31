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
            String(localized: "That doesn't look like a valid address")
        case .offline:
            String(localized: "You're offline")
        case .network(let statusCode):
            statusCode.map { String(localized: "The server responded with an error (\($0))") }
                ?? String(localized: "Couldn't reach the server")
        case .notFound:
            String(localized: "No feed at that address")
        case .invalidFeed:
            String(localized: "That isn't a podcast feed")
        case .noEpisodes:
            String(localized: "This podcast has no episodes yet")
        case .playbackFailed:
            String(localized: "Couldn't play this episode")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidURL:
            String(localized: "Check the address and try again. It should look like https://example.com/feed.xml")
        case .offline:
            String(localized: "Check your connection and try again.")
        case .network:
            String(localized: "The podcast host may be having trouble. Try again in a moment.")
        case .notFound:
            String(localized: "Double-check the address, or try one of the sample feeds.")
        case .invalidFeed(let reason):
            // The reason comes from the XML parser and stays untranslated; it
            // is diagnostic detail, not prose.
            String(localized: "The address returned something we couldn't read (\(reason)).")
        case .noEpisodes:
            String(localized: "Check back once the publisher releases an episode.")
        case .playbackFailed:
            String(localized: "The audio file may be unavailable. Try another episode.")
        }
    }
}
