import Testing
import Foundation
@testable import PodcastPlayer

@MainActor
@Suite("PodcastDetailViewModel")
struct PodcastDetailViewModelTests {

    @Test("Loading moves from idle to loaded")
    func loadReachesLoaded() async {
        let sut = PodcastDetailViewModel(
            feedURL: anyFeedURL,
            repository: FakeRepository(result: .success(samplePodcast)),
            player: FakePlayer()
        )
        #expect(sut.state == .idle)

        await sut.load()

        #expect(sut.state == .loaded(samplePodcast))
    }

    @Test("A podcast with no episodes is empty, not loaded")
    func emptyPodcastIsEmpty() async {
        let bare = Podcast(feedURL: anyFeedURL, title: "Bare", description: nil,
                           author: nil, imageURL: nil, categories: [], episodes: [])
        let sut = PodcastDetailViewModel(
            feedURL: anyFeedURL,
            repository: FakeRepository(result: .success(bare)),
            player: FakePlayer()
        )

        await sut.load()

        #expect(sut.state == .empty)
    }

    @Test("Priming with an already-fetched podcast avoids a redundant spinner")
    func primingAvoidsRefetch() async {
        let repository = FakeRepository(result: .success(samplePodcast))
        let sut = PodcastDetailViewModel(feedURL: anyFeedURL, repository: repository, player: FakePlayer())

        sut.prime(with: samplePodcast)
        #expect(sut.state == .loaded(samplePodcast))

        await sut.load()
        #expect(repository.callCount == 0)
    }

    @Test("A failure is surfaced and can be retried")
    func failureIsRetryable() async {
        let sut = PodcastDetailViewModel(
            feedURL: anyFeedURL,
            repository: FakeRepository(results: [.failure(.network(statusCode: 500)), .success(samplePodcast)]),
            player: FakePlayer()
        )

        await sut.load()
        #expect(sut.state == .failed(.network(statusCode: 500)))

        await sut.retry()
        #expect(sut.state == .loaded(samplePodcast))
    }

    @Test("Refresh forces a revalidation")
    func refreshForcesRevalidation() async {
        let repository = FakeRepository(result: .success(samplePodcast))
        let sut = PodcastDetailViewModel(feedURL: anyFeedURL, repository: repository, player: FakePlayer())

        await sut.refresh()

        #expect(repository.lastForceRefresh == true)
    }

    @Test("A failed refresh keeps the content already on screen")
    func failedRefreshKeepsContent() async {
        let repository = FakeRepository(results: [.success(samplePodcast), .failure(.offline)])
        let sut = PodcastDetailViewModel(feedURL: anyFeedURL, repository: repository, player: FakePlayer())

        await sut.load()
        await sut.refresh()

        // Pull-to-refresh on a train must not destroy the page being read.
        #expect(sut.state == .loaded(samplePodcast))
    }

    @Test("Playing an episode queues the whole list so next and previous work")
    func playQueuesTheWholeList() async {
        let player = FakePlayer()
        let sut = PodcastDetailViewModel(
            feedURL: anyFeedURL,
            repository: FakeRepository(result: .success(samplePodcast)),
            player: player
        )
        await sut.load()

        sut.play(samplePodcast.episodes[1])

        #expect(player.loadedQueue == samplePodcast.episodes)
        #expect(player.startIndex == 1)
        #expect(player.playCallCount == 1)
    }

    @Test("Playing before the feed loads is ignored")
    func playBeforeLoadIsIgnored() {
        let player = FakePlayer()
        let sut = PodcastDetailViewModel(feedURL: anyFeedURL, repository: FakeRepository(), player: player)

        sut.play(sampleEpisodes[0])

        #expect(player.loadedQueue == nil)
        #expect(player.playCallCount == 0)
    }

    @Test("Reports which row is currently playing")
    func reportsCurrentEpisode() async {
        let player = FakePlayer()
        let sut = PodcastDetailViewModel(
            feedURL: anyFeedURL,
            repository: FakeRepository(result: .success(samplePodcast)),
            player: player
        )
        await sut.load()
        sut.play(samplePodcast.episodes[1])

        #expect(sut.isCurrent(samplePodcast.episodes[1]))
        #expect(!sut.isCurrent(samplePodcast.episodes[0]))
    }

    @Test("Loading twice does not refetch")
    func loadIsIdempotent() async {
        let repository = FakeRepository(result: .success(samplePodcast))
        let sut = PodcastDetailViewModel(feedURL: anyFeedURL, repository: repository, player: FakePlayer())

        await sut.load()
        await sut.load()

        #expect(repository.callCount == 1)
    }
}
