import Foundation
import SwiftData

@Model
final class FeedHistoryEntry {
    @Attribute(.unique) var url: URL
    /// Nil until the feed has loaded successfully at least once.
    var title: String?
    var lastAccessedAt: Date

    init(url: URL, title: String?, lastAccessedAt: Date) {
        self.url = url
        self.title = title
        self.lastAccessedAt = lastAccessedAt
    }

    var domainValue: FeedHistoryItem {
        FeedHistoryItem(url: url, title: title, lastAccessedAt: lastAccessedAt)
    }
}

/// Remembers which feeds the user has opened.
///
/// Errors are swallowed rather than propagated: failing to remember a URL must
/// never break loading the podcast the user actually asked for.
@ModelActor
actor FeedHistoryStoreImpl: FeedHistoryStore {
    /// Enough to be useful, few enough that screen 1 stays a list and not an
    /// archive.
    static let limit = 20

    private var dates: DateProviding = SystemDateProvider()

    func setDateProvider(_ provider: DateProviding) {
        dates = provider
    }

    func history() async -> [FeedHistoryItem] {
        let descriptor = FetchDescriptor<FeedHistoryEntry>(
            sortBy: [SortDescriptor(\.lastAccessedAt, order: .reverse)]
        )
        guard let entries = try? modelContext.fetch(descriptor) else { return [] }
        return entries.map(\.domainValue)
    }

    func record(url: URL, title: String?) async {
        let now = dates.now

        if let existing = try? fetchEntry(url) {
            existing.lastAccessedAt = now
            // Only overwrite the title once we actually know one, so a failed
            // reload never erases a name we already had.
            if let title { existing.title = title }
        } else {
            modelContext.insert(FeedHistoryEntry(url: url, title: title, lastAccessedAt: now))
        }

        try? modelContext.save()
        try? pruneBeyondLimit()
    }

    func clear() async {
        try? modelContext.delete(model: FeedHistoryEntry.self)
        try? modelContext.save()
    }

    private func fetchEntry(_ url: URL) throws -> FeedHistoryEntry? {
        var descriptor = FetchDescriptor<FeedHistoryEntry>(
            predicate: #Predicate { $0.url == url }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func pruneBeyondLimit() throws {
        let descriptor = FetchDescriptor<FeedHistoryEntry>(
            sortBy: [SortDescriptor(\.lastAccessedAt, order: .reverse)]
        )
        let entries = try modelContext.fetch(descriptor)
        guard entries.count > Self.limit else { return }
        for entry in entries.dropFirst(Self.limit) {
            modelContext.delete(entry)
        }
        try modelContext.save()
    }
}
