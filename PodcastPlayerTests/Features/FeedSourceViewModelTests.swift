import Testing
import Foundation
@testable import PodcastPlayer

@MainActor
@Suite("FeedSourceViewModel")
struct FeedSourceViewModelTests {

    // MARK: - URL validation

    @Test("Rejects blank input without troubling the network")
    func rejectsBlankInput() async {
        let repository = FakeRepository()
        let sut = FeedSourceViewModel(repository: repository, history: FakeHistoryStore())
        sut.urlText = "   "

        await sut.submit()

        #expect(sut.state == .failed(.invalidURL))
        #expect(repository.callCount == 0)
    }

    @Test("Rejects text that is not a URL", arguments: ["not a url", "http://", "just-words", "ftp://x.com"])
    func rejectsMalformedInput(text: String) async {
        let repository = FakeRepository()
        let sut = FeedSourceViewModel(repository: repository, history: FakeHistoryStore())
        sut.urlText = text

        await sut.submit()

        #expect(sut.state == .failed(.invalidURL))
        #expect(repository.callCount == 0)
    }

    @Test("Assumes https when the pasted address has no scheme")
    func assumesHTTPSWhenSchemeIsMissing() async {
        let repository = FakeRepository(result: .success(samplePodcast))
        let sut = FeedSourceViewModel(repository: repository, history: FakeHistoryStore())
        sut.urlText = "feeds.megaphone.fm/la-cotorrisa"

        await sut.submit()

        #expect(repository.lastURL?.scheme == "https")
        #expect(repository.lastURL?.host() == "feeds.megaphone.fm")
    }

    @Test("Keeps an explicit http scheme, since some feeds are still http-only")
    func keepsExplicitHTTP() async {
        let repository = FakeRepository(result: .success(samplePodcast))
        let sut = FeedSourceViewModel(repository: repository, history: FakeHistoryStore())
        sut.urlText = "http://feeds.feedburner.com/GeekNights"

        await sut.submit()

        #expect(repository.lastURL?.scheme == "http")
    }

    @Test("Trims whitespace around a pasted address")
    func trimsPastedWhitespace() async {
        let repository = FakeRepository(result: .success(samplePodcast))
        let sut = FeedSourceViewModel(repository: repository, history: FakeHistoryStore())
        sut.urlText = "  https://example.test/feed.xml \n"

        await sut.submit()

        #expect(repository.lastURL == URL(string: "https://example.test/feed.xml"))
    }

    // MARK: - Loading

    @Test("A successful load lands in loaded and records history")
    func successLoadsAndRecordsHistory() async {
        let history = FakeHistoryStore()
        let sut = FeedSourceViewModel(
            repository: FakeRepository(result: .success(samplePodcast)),
            history: history
        )
        sut.urlText = anyFeedURL.absoluteString

        await sut.submit()

        #expect(sut.state == .loaded(samplePodcast))
        #expect(history.recorded.map(\.url) == [anyFeedURL])
        #expect(history.recorded.first?.title == samplePodcast.title)
    }

    @Test("A podcast with no episodes is empty, not loaded")
    func emptyPodcastIsEmptyState() async {
        let bare = Podcast(feedURL: anyFeedURL, title: "Bare", description: nil,
                           author: nil, imageURL: nil, categories: [], episodes: [])
        let sut = FeedSourceViewModel(
            repository: FakeRepository(result: .success(bare)),
            history: FakeHistoryStore()
        )
        sut.urlText = anyFeedURL.absoluteString

        await sut.submit()

        #expect(sut.state == .empty)
    }

    @Test("A failure surfaces the domain error")
    func failureSurfacesError() async {
        let sut = FeedSourceViewModel(
            repository: FakeRepository(result: .failure(.notFound)),
            history: FakeHistoryStore()
        )
        sut.urlText = anyFeedURL.absoluteString

        await sut.submit()

        #expect(sut.state == .failed(.notFound))
    }

    @Test("A failed load is never written to history")
    func failedLoadIsNotRecorded() async {
        let history = FakeHistoryStore()
        let sut = FeedSourceViewModel(
            repository: FakeRepository(result: .failure(.notFound)),
            history: history
        )
        sut.urlText = anyFeedURL.absoluteString

        await sut.submit()

        #expect(history.recorded.isEmpty)
    }

    @Test("Retry repeats the failed load and can succeed")
    func retryCanSucceed() async {
        let sut = FeedSourceViewModel(
            repository: FakeRepository(results: [.failure(.offline), .success(samplePodcast)]),
            history: FakeHistoryStore()
        )
        sut.urlText = anyFeedURL.absoluteString

        await sut.submit()
        #expect(sut.state == .failed(.offline))

        await sut.retry()
        #expect(sut.state == .loaded(samplePodcast))
    }

    @Test("Retry repeats the attempted URL even after the field is edited")
    func retryUsesTheAttemptedURL() async {
        let repository = FakeRepository(results: [.failure(.offline), .success(samplePodcast)])
        let sut = FeedSourceViewModel(repository: repository, history: FakeHistoryStore())
        sut.urlText = anyFeedURL.absoluteString

        await sut.submit()
        sut.urlText = "something the user started typing"
        await sut.retry()

        #expect(repository.lastURL == anyFeedURL)
    }

    @Test("Retry before any attempt does nothing")
    func retryWithoutAttemptDoesNothing() async {
        let repository = FakeRepository()
        let sut = FeedSourceViewModel(repository: repository, history: FakeHistoryStore())

        await sut.retry()

        #expect(repository.callCount == 0)
        #expect(sut.state == .idle)
    }

    // MARK: - History

    @Test("History loads on demand")
    func loadsHistory() async {
        let history = FakeHistoryStore(items: [
            FeedHistoryItem(url: anyFeedURL, title: "Show", lastAccessedAt: t0)
        ])
        let sut = FeedSourceViewModel(repository: FakeRepository(), history: history)

        await sut.loadHistory()

        #expect(sut.history.map(\.url) == [anyFeedURL])
    }

    @Test("Selecting a history entry loads it and fills the field")
    func selectingHistoryLoadsIt() async {
        let repository = FakeRepository(result: .success(samplePodcast))
        let sut = FeedSourceViewModel(repository: repository, history: FakeHistoryStore())

        await sut.select(FeedHistoryItem(url: anyFeedURL, title: "Show", lastAccessedAt: t0))

        #expect(repository.lastURL == anyFeedURL)
        #expect(sut.state == .loaded(samplePodcast))
        #expect(sut.urlText == anyFeedURL.absoluteString)
    }

    @Test("Clearing history empties it immediately")
    func clearingHistoryEmptiesIt() async {
        let history = FakeHistoryStore(items: [
            FeedHistoryItem(url: anyFeedURL, title: "Show", lastAccessedAt: t0)
        ])
        let sut = FeedSourceViewModel(repository: FakeRepository(), history: history)
        await sut.loadHistory()

        await sut.clearHistory()

        #expect(sut.history.isEmpty)
        #expect(history.clearCallCount == 1)
    }

    // MARK: - Offered samples

    @Test("Every offered sample address survives normalisation")
    func sampleFeedsAreUsableAddresses() {
        for sample in FeedSourceView.sampleFeeds {
            #expect(
                FeedSourceViewModel.normalized(sample.url) != nil,
                "Sample \(sample.name) has an unusable address: \(sample.url)"
            )
        }
    }

    @Test("Sample addresses are distinct")
    func sampleFeedsAreDistinct() {
        let urls = FeedSourceView.sampleFeeds.map(\.url)
        #expect(Set(urls).count == urls.count, "Two samples point at the same feed")
    }

    @Test("Every sample is labelled")
    func sampleFeedsAreLabelled() {
        for sample in FeedSourceView.sampleFeeds {
            #expect(!sample.name.isEmpty)
            #expect(!sample.detail.isEmpty)
        }
    }

    // MARK: - Clearing

    @Test("The clear affordance appears only when there is text to clear")
    func canClearOnlyWithText() {
        let sut = FeedSourceViewModel(repository: FakeRepository(), history: FakeHistoryStore())
        #expect(!sut.canClear)

        sut.urlText = "https://example.test/feed.xml"
        #expect(sut.canClear)
    }

    @Test("Clearing empties the field")
    func clearEmptiesTheField() {
        let sut = FeedSourceViewModel(repository: FakeRepository(), history: FakeHistoryStore())
        sut.urlText = "https://example.test/feed.xml"

        sut.clear()

        #expect(sut.urlText.isEmpty)
        #expect(!sut.canClear)
    }

    @Test("Clearing dismisses an error about the address just deleted")
    func clearDismissesAStaleError() async {
        let sut = FeedSourceViewModel(
            repository: FakeRepository(result: .failure(.notFound)),
            history: FakeHistoryStore()
        )
        sut.urlText = anyFeedURL.absoluteString
        await sut.submit()
        #expect(sut.state == .failed(.notFound))

        sut.clear()

        #expect(sut.state == .idle)
    }

    @Test("Clearing leaves a loaded podcast alone")
    func clearDoesNotDiscardALoadedPodcast() async {
        let sut = FeedSourceViewModel(
            repository: FakeRepository(result: .success(samplePodcast)),
            history: FakeHistoryStore()
        )
        sut.urlText = anyFeedURL.absoluteString
        await sut.submit()

        sut.clear()

        // Clearing the field is not a cancel.
        #expect(sut.state == .loaded(samplePodcast))
        #expect(sut.urlText.isEmpty)
    }

    @Test("Clearing does not disable submit for a fresh address")
    func clearThenTypeAgainCanSubmit() {
        let sut = FeedSourceViewModel(repository: FakeRepository(), history: FakeHistoryStore())
        sut.urlText = "https://example.test/feed.xml"
        sut.clear()
        #expect(!sut.canSubmit)

        sut.urlText = "https://other.test/feed.xml"
        #expect(sut.canSubmit)
    }

    // MARK: - Submit affordance

    @Test("Submit is disabled until there is something to submit")
    func submitRequiresInput() {
        let sut = FeedSourceViewModel(repository: FakeRepository(), history: FakeHistoryStore())
        #expect(!sut.canSubmit)

        sut.urlText = "  "
        #expect(!sut.canSubmit)

        sut.urlText = "https://example.test/feed.xml"
        #expect(sut.canSubmit)
    }
}
