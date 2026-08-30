import Foundation
import SwiftData

/// The composition root.
///
/// The only place in the app where concrete types are named. Every other file
/// sees protocols, which is what makes the whole thing testable and what keeps
/// a change of persistence or networking library from rippling outward.
@MainActor
final class AppEnvironment {
    let repository: any PodcastRepository & CacheManaging
    let history: any FeedHistoryStore
    let images: any ImageLoading
    let player: AudioPlayerService
    private let session: AudioSessionController?

    private init(
        repository: any PodcastRepository & CacheManaging,
        history: any FeedHistoryStore,
        images: any ImageLoading,
        player: AudioPlayerService,
        session: AudioSessionController?
    ) {
        self.repository = repository
        self.history = history
        self.images = images
        self.player = player
        self.session = session
        session?.activate()
    }

    /// The real thing.
    static func live() throws -> AppEnvironment {
        try make(container: PersistenceContainer.make(), client: URLSessionHTTPClient())
    }

    /// Used when the app is launched by a UI test: in-memory storage and
    /// fixture responses, so the tests never touch the network and never
    /// inherit state from a previous run.
    static func uiTesting() -> AppEnvironment {
        let container = try? PersistenceContainer.make(inMemory: true)
        guard let container else { return fallback() }
        return make(container: container, client: FixtureHTTPClient())
    }

    /// Last resort when the on-disk store cannot be opened — a corrupt
    /// database, or no room to create one.
    ///
    /// Falling back to memory means the user gets a working app that forgets
    /// things, which is strictly better than an app that will not launch.
    static func fallback() -> AppEnvironment {
        let engine = AVPlayerEngine()
        let player = AudioPlayerService(engine: engine, nowPlaying: NowPlayingPublisher())
        return AppEnvironment(
            repository: UnavailableRepository(),
            history: UnavailableHistoryStore(),
            images: UnavailableImageLoader(),
            player: player,
            session: nil
        )
    }

    private static func make(container: ModelContainer, client: any HTTPClient) -> AppEnvironment {
        let cache = FeedCacheStore(modelContainer: container)
        let history = FeedHistoryStoreImpl(modelContainer: container)
        let images = ImageCache(client: client, directory: imageCacheDirectory())
        let repository = PodcastRepositoryImpl(client: client, cache: cache, images: images)

        let player = AudioPlayerService(
            engine: AVPlayerEngine(),
            nowPlaying: NowPlayingPublisher(),
            images: images
        )

        return AppEnvironment(
            repository: repository,
            history: history,
            images: images,
            player: player,
            session: AudioSessionController(player: player)
        )
    }

    /// Caches/, not Documents/ — this is data the system may reclaim and that
    /// should never be backed up to iCloud.
    private static func imageCacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PodcastImages", isDirectory: true)
    }

    // MARK: - View model factories

    func makeFeedSourceViewModel() -> FeedSourceViewModel {
        FeedSourceViewModel(repository: repository, history: history)
    }

    func makeDetailViewModel(for feedURL: URL) -> PodcastDetailViewModel {
        PodcastDetailViewModel(feedURL: feedURL, repository: repository, player: player)
    }

    func makePlayerViewModel() -> PlayerViewModel {
        PlayerViewModel(player: player)
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(cache: repository, history: history)
    }
}

// MARK: - Degraded implementations

/// Used only when persistence could not be opened at all.
private struct UnavailableRepository: PodcastRepository, CacheManaging {
    func podcast(for url: URL, forceRefresh: Bool) async throws(AppError) -> Podcast {
        throw .network(statusCode: nil)
    }
    func statistics() async -> CacheStatistics { .empty }
    func clearFeedCache() async {}
    func clearImageCache() async {}
}

private struct UnavailableHistoryStore: FeedHistoryStore {
    func history() async -> [FeedHistoryItem] { [] }
    func record(url: URL, title: String?) async {}
    func clear() async {}
}

private struct UnavailableImageLoader: ImageLoading {
    func image(for url: URL) async -> Data? { nil }
}

// MARK: - UI testing support

/// Serves the checked-in fixture feed to UI tests, so they exercise the real
/// parse-cache-render path without a network.
private struct FixtureHTTPClient: HTTPClient {
    func get(_ url: URL, conditional: ConditionalHeaders?) async throws(AppError) -> HTTPResponse {
        guard let fixture = Bundle.main.url(forResource: "uitest-feed", withExtension: "xml"),
              let data = try? Data(contentsOf: fixture) else {
            throw .notFound
        }
        return .data(data, .none)
    }
}
