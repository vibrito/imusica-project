import Foundation

/// A podcast as the app understands it, independent of how it was obtained.
///
/// This is a value type on purpose: it can be handed to a view, cached, and
/// compared without any risk of shared mutable state.
struct Podcast: Hashable, Sendable, Identifiable {
    /// The feed URL doubles as identity — one feed is one podcast.
    var id: URL { feedURL }

    let feedURL: URL
    let title: String
    let description: String?
    let author: String?
    let imageURL: URL?
    let categories: [String]
    let episodes: [Episode]
}

extension Podcast {
    /// The genre shown on the detail screen. Feeds routinely declare several
    /// categories; the first is the primary one by convention.
    var primaryCategory: String? { categories.first }
}
