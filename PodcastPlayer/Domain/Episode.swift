import Foundation

/// A single playable episode.
///
/// `audioURL` is non-optional by construction: an entry with no playable media
/// is not an episode, and is dropped during parsing rather than represented
/// here as a half-valid value.
struct Episode: Equatable, Sendable, Identifiable {
    /// The feed's `guid`, falling back to the enclosure URL when absent.
    let id: String

    let title: String
    let description: String?
    let audioURL: URL
    /// Nil when the feed omits `itunes:duration` or states it unparseably.
    let duration: TimeInterval?
    let publishedAt: Date?
    /// Episode-specific artwork, when the feed provides it. Callers fall back
    /// to the podcast's own image.
    let imageURL: URL?
}
