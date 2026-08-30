import Testing
import Foundation
@testable import PodcastPlayer

@Suite("AppError")
struct AppErrorTests {
    static let all: [AppError] = [
        .invalidURL,
        .offline,
        .network(statusCode: nil),
        .network(statusCode: 500),
        .notFound,
        .invalidFeed(reason: "no channel element"),
        .noEpisodes,
        .playbackFailed,
    ]

    @Test("Transient failures are retryable, permanent ones are not")
    func retryableErrorsAreMarkedRetryable() {
        #expect(AppError.offline.isRetryable)
        #expect(AppError.network(statusCode: 500).isRetryable)
        #expect(AppError.playbackFailed.isRetryable)

        #expect(!AppError.invalidURL.isRetryable)
        #expect(!AppError.notFound.isRetryable)
        #expect(!AppError.invalidFeed(reason: "x").isRetryable)
        #expect(!AppError.noEpisodes.isRetryable)
    }

    @Test("Every error carries user-facing copy", arguments: AppErrorTests.all)
    func everyErrorHasUserFacingCopy(error: AppError) {
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.recoverySuggestion?.isEmpty == false)
    }

    @Test("No error message leaks a raw underlying description", arguments: AppErrorTests.all)
    func messagesAreHumanReadable(error: AppError) {
        let message = error.errorDescription ?? ""
        #expect(!message.contains("Error Domain"))
        #expect(!message.contains("AppError"))
    }

    @Test("Network errors compare by status code")
    func networkErrorsCompareByStatusCode() {
        #expect(AppError.network(statusCode: 500) == AppError.network(statusCode: 500))
        #expect(AppError.network(statusCode: 500) != AppError.network(statusCode: 503))
        #expect(AppError.network(statusCode: nil) != AppError.network(statusCode: 500))
    }
}

@Suite("ViewState")
struct ViewStateTests {
    @Test("States compare by case and payload")
    func statesCompareByCaseAndPayload() {
        #expect(ViewState<String>.idle == .idle)
        #expect(ViewState<String>.loaded("a") == .loaded("a"))
        #expect(ViewState<String>.loaded("a") != .loaded("b"))
        #expect(ViewState<String>.loading != .idle)
        #expect(ViewState<String>.failed(.offline) == .failed(.offline))
        #expect(ViewState<String>.failed(.offline) != .failed(.notFound))
    }

    @Test("isLoading is true only while loading")
    func isLoadingIsTrueOnlyWhileLoading() {
        #expect(ViewState<String>.loading.isLoading)
        #expect(!ViewState<String>.idle.isLoading)
        #expect(!ViewState<String>.loaded("a").isLoading)
    }

    @Test("value is the payload only when loaded")
    func valueIsThePayloadOnlyWhenLoaded() {
        #expect(ViewState.loaded("a").value == "a")
        #expect(ViewState<String>.loading.value == nil)
        #expect(ViewState<String>.failed(.offline).value == nil)
    }
}

@Suite("Domain models")
struct DomainModelTests {
    @Test("A podcast is identified by its feed URL")
    func podcastIsIdentifiedByFeedURL() {
        let url = URL(string: "https://example.test/feed.xml")!
        let podcast = Podcast(feedURL: url, title: "T", description: nil,
                              author: nil, imageURL: nil, categories: [], episodes: [])
        #expect(podcast.id == url)
    }

    @Test("Episodes keep the identity supplied by the feed")
    func episodeKeepsItsFeedIdentity() {
        let episode = Episode(id: "guid-1", title: "One", description: nil,
                              audioURL: URL(string: "https://example.test/1.mp3")!,
                              duration: 60, publishedAt: nil, imageURL: nil)
        #expect(episode.id == "guid-1")
    }
}

@Suite("Date providers")
struct DateProviderTests {
    @Test("A fixed provider never moves")
    func fixedProviderNeverMoves() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let provider = FixedDateProvider(now: t0)
        #expect(provider.now == t0)
        #expect(provider.now == t0)
    }

    @Test("An advancing provider moves by its step on every read")
    func advancingProviderStepsForward() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let provider = AdvancingDateProvider(start: t0, step: 10)
        #expect(provider.now == t0)
        #expect(provider.now == t0.addingTimeInterval(10))
        #expect(provider.now == t0.addingTimeInterval(20))
    }
}
