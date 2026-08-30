import Foundation

/// Two-tier image cache: memory for the current scroll, disk for everything
/// since.
///
/// An actor rather than a lock-guarded class, so the in-flight request table
/// that deduplicates concurrent loads is safe by construction.
///
/// Returns nil rather than throwing. A missing image is cosmetic, and must
/// never push a screen into an error state.
actor ImageCache: ImageLoading, CacheManaging {
    private let client: HTTPClient
    private let directory: URL
    private let maxDiskBytes: Int64
    private let fileManager: FileManager

    /// Memory tier. NSCache evicts itself under pressure, which is exactly the
    /// behaviour wanted for decoded artwork.
    private let memory = NSCache<NSString, NSData>()

    /// In-flight loads, so a grid of episodes sharing one artwork URL fires a
    /// single download rather than one per cell.
    private var inFlight: [URL: Task<Data?, Never>] = [:]

    init(
        client: HTTPClient,
        directory: URL,
        maxDiskBytes: Int64 = 100 * 1024 * 1024,
        fileManager: FileManager = .default
    ) {
        self.client = client
        self.directory = directory
        self.maxDiskBytes = maxDiskBytes
        self.fileManager = fileManager
        memory.totalCostLimit = 32 * 1024 * 1024
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func image(for url: URL) async -> Data? {
        let key = Self.key(for: url)

        if let hit = memory.object(forKey: key as NSString) {
            return hit as Data
        }

        if let hit = readFromDisk(key) {
            memory.setObject(hit as NSData, forKey: key as NSString, cost: hit.count)
            return hit
        }

        if let existing = inFlight[url] {
            return await existing.value
        }

        let task = Task<Data?, Never> { [client] in
            guard case let .data(data, _) = try? await client.get(url, conditional: nil),
                  !data.isEmpty else { return nil }
            return data
        }
        inFlight[url] = task

        let data = await task.value
        inFlight[url] = nil

        if let data {
            memory.setObject(data as NSData, forKey: key as NSString, cost: data.count)
            writeToDisk(data, key: key)
            evictIfNeeded()
        }
        return data
    }

    // MARK: - CacheManaging

    func statistics() async -> CacheStatistics {
        CacheStatistics(cachedFeedCount: 0, imageCacheBytes: diskUsageBytes())
    }

    func clearFeedCache() async {
        // Feeds are not this cache's concern; PodcastRepositoryImpl composes
        // the two and routes each clear to the right owner.
    }

    func clearImageCache() async {
        clear()
    }

    func diskUsageBytes() -> Int64 {
        contents().reduce(into: Int64(0)) { total, file in total += file.size }
    }

    func clear() {
        memory.removeAllObjects()
        for file in contents() {
            try? fileManager.removeItem(at: file.url)
        }
    }

    // MARK: - Disk tier

    /// SHA-256 of the URL, so the filename is fixed-length and filesystem-safe
    /// regardless of what the publisher put in the path or query.
    private static func key(for url: URL) -> String {
        SHA256Digest.hexString(of: Data(url.absoluteString.utf8))
    }

    private func fileURL(_ key: String) -> URL {
        directory.appendingPathComponent(key, isDirectory: false)
    }

    private func readFromDisk(_ key: String) -> Data? {
        let url = fileURL(key)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        // Touch so eviction can order by least-recently-used.
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    private func writeToDisk(_ data: Data, key: String) {
        try? data.write(to: fileURL(key), options: .atomic)
    }

    private struct CachedFile {
        let url: URL
        let size: Int64
        let accessedAt: Date
    }

    private func contents() -> [CachedFile] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys
        ) else { return [] }

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return CachedFile(
                url: url,
                size: Int64(values.fileSize ?? 0),
                accessedAt: values.contentModificationDate ?? .distantPast
            )
        }
    }

    /// Least-recently-used eviction down to the cap.
    private func evictIfNeeded() {
        var files = contents()
        var total = files.reduce(into: Int64(0)) { $0 += $1.size }
        guard total > maxDiskBytes else { return }

        files.sort { $0.accessedAt < $1.accessedAt }
        for file in files where total > maxDiskBytes {
            try? fileManager.removeItem(at: file.url)
            total -= file.size
        }
    }
}
