import Foundation
@testable import PodcastPlayer

@MainActor
final class FakePlaybackEngine: PlaybackEngine {
    var onProgress: ((TimeInterval, TimeInterval) -> Void)?
    var onFinish: (() -> Void)?
    var onFailure: (() -> Void)?

    private(set) var replacedURLs: [URL] = []
    private(set) var seekTimes: [TimeInterval] = []
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0

    func replaceItem(url: URL) { replacedURLs.append(url) }
    func play() { playCallCount += 1 }
    func pause() { pauseCallCount += 1 }
    func seek(to time: TimeInterval) { seekTimes.append(time) }

    func simulateProgress(elapsed: TimeInterval, duration: TimeInterval) {
        onProgress?(elapsed, duration)
    }
    func simulateFinish() { onFinish?() }
    func simulateFailure() { onFailure?() }
}

@MainActor
final class FakeNowPlayingPublisher: NowPlayingPublishing {
    private(set) var lastTitle: String?
    private(set) var lastArtist: String?
    private(set) var lastArtwork: Data?
    private(set) var lastIsPlaying: Bool?
    private(set) var lastElapsed: TimeInterval?
    private(set) var clearCallCount = 0
    private(set) var publishCallCount = 0

    func publish(episode: Episode, podcast: Podcast, artwork: Data?) {
        publishCallCount += 1
        lastTitle = episode.title
        lastArtist = podcast.title
        lastArtwork = artwork
    }

    func updatePlayback(elapsed: TimeInterval, duration: TimeInterval, isPlaying: Bool) {
        lastElapsed = elapsed
        lastIsPlaying = isPlaying
    }

    func clear() { clearCallCount += 1 }
}

/// Stands in for AudioPlayerService in ViewModel tests.
@MainActor
final class FakePlayer: AudioPlaying {
    var currentEpisode: Episode?
    var currentPodcast: Podcast?
    var isPlaying = false
    var elapsed: TimeInterval = 0
    var duration: TimeInterval = 0
    var canGoNext = true
    var canGoPrevious = true

    private(set) var loadedQueue: [Episode]?
    private(set) var startIndex: Int?
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var nextCallCount = 0
    private(set) var previousCallCount = 0
    private(set) var seekTimes: [TimeInterval] = []

    func load(queue: [Episode], startingAt index: Int, podcast: Podcast) {
        loadedQueue = queue
        startIndex = index
        currentPodcast = podcast
        currentEpisode = queue.indices.contains(index) ? queue[index] : nil
    }

    func play() { playCallCount += 1; isPlaying = true }
    func pause() { pauseCallCount += 1; isPlaying = false }
    func next() { nextCallCount += 1 }
    func previous() { previousCallCount += 1 }
    func seek(to time: TimeInterval) { seekTimes.append(time) }
}
