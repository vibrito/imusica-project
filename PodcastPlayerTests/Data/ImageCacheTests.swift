import Testing
import Foundation
@testable import PodcastPlayer

@Suite("ImageCache")
struct ImageCacheTests {
    let imageURL = URL(string: "https://example.test/cover.jpg")!
    let imageData = Data("pretend-this-is-a-png".utf8)

    /// Each test gets its own directory so nothing leaks between them.
    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageCacheTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Fetches once, then serves from memory")
    func fetchesOnceThenServesFromCache() async {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let client = FakeHTTPClient(data: imageData)
        let cache = ImageCache(client: client, directory: directory)

        #expect(await cache.image(for: imageURL) == imageData)
        #expect(await cache.image(for: imageURL) == imageData)
        #expect(client.requestCount == 1)
    }

    @Test("Survives losing the memory tier by reading from disk")
    func survivesMemoryLossViaDisk() async {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let client = FakeHTTPClient(data: imageData)
        _ = await ImageCache(client: client, directory: directory).image(for: imageURL)

        // A fresh instance has an empty memory tier but the same disk tier.
        let restarted = ImageCache(client: client, directory: directory)
        #expect(await restarted.image(for: imageURL) == imageData)
        #expect(client.requestCount == 1)
    }

    @Test("A failed load returns nil rather than throwing")
    func failureReturnsNil() async {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = ImageCache(client: FakeHTTPClient(error: .offline), directory: directory)
        #expect(await cache.image(for: imageURL) == nil)
    }

    @Test("A failed load is not cached as a result")
    func failureIsNotCached() async {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let client = FakeHTTPClient(results: [.failure(.offline), .success(.data(imageData, .none))])
        let cache = ImageCache(client: client, directory: directory)

        #expect(await cache.image(for: imageURL) == nil)
        #expect(await cache.image(for: imageURL) == imageData)
    }

    @Test("Concurrent requests for one URL trigger a single download")
    func deduplicatesConcurrentRequests() async {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let client = FakeHTTPClient(data: imageData)
        let cache = ImageCache(client: client, directory: directory)

        await withTaskGroup(of: Data?.self) { group in
            for _ in 0..<10 {
                group.addTask { await cache.image(for: imageURL) }
            }
            for await result in group {
                #expect(result == imageData)
            }
        }
        #expect(client.requestCount == 1)
    }

    @Test("Reports what it is using on disk")
    func reportsDiskUsage() async {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = ImageCache(client: FakeHTTPClient(data: imageData), directory: directory)
        #expect(await cache.diskUsageBytes() == 0)

        _ = await cache.image(for: imageURL)
        #expect(await cache.diskUsageBytes() == Int64(imageData.count))
    }

    @Test("Clearing empties both tiers")
    func clearEmptiesBothTiers() async {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let client = FakeHTTPClient(data: imageData)
        let cache = ImageCache(client: client, directory: directory)
        _ = await cache.image(for: imageURL)

        await cache.clear()
        #expect(await cache.diskUsageBytes() == 0)

        // A refetch proves the memory tier was cleared too, not just disk.
        _ = await cache.image(for: imageURL)
        #expect(client.requestCount == 2)
    }

    @Test("Evicts least-recently-used files once over the cap")
    func evictsOverTheCap() async {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let cap = Int64(imageData.count * 3)
        let cache = ImageCache(client: FakeHTTPClient(data: imageData),
                               directory: directory, maxDiskBytes: cap)

        for index in 0..<8 {
            _ = await cache.image(for: URL(string: "https://example.test/\(index).jpg")!)
        }

        #expect(await cache.diskUsageBytes() <= cap)
    }

    @Test("Distinct URLs are cached separately")
    func distinctURLsAreSeparate() async {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = Data("first".utf8)
        let second = Data("second".utf8)
        let client = FakeHTTPClient(results: [
            .success(.data(first, .none)),
            .success(.data(second, .none)),
        ])
        let cache = ImageCache(client: client, directory: directory)

        #expect(await cache.image(for: URL(string: "https://example.test/a.jpg")!) == first)
        #expect(await cache.image(for: URL(string: "https://example.test/b.jpg")!) == second)
    }

    @Test("An empty response body is treated as a miss")
    func emptyBodyIsAMiss() async {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = ImageCache(client: FakeHTTPClient(data: Data()), directory: directory)
        #expect(await cache.image(for: imageURL) == nil)
    }
}
