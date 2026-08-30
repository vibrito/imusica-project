import Testing
import Foundation
@testable import PodcastPlayer

@MainActor
@Suite("AudioPlayerService")
struct AudioPlayerServiceTests {

    private struct SUT {
        let player: AudioPlayerService
        let engine: FakePlaybackEngine
        let nowPlaying: FakeNowPlayingPublisher
    }

    private func makeSUT() -> SUT {
        let engine = FakePlaybackEngine()
        let nowPlaying = FakeNowPlayingPublisher()
        return SUT(
            player: AudioPlayerService(engine: engine, nowPlaying: nowPlaying),
            engine: engine,
            nowPlaying: nowPlaying
        )
    }

    // MARK: - Loading

    @Test("Loading a queue selects the requested episode")
    func loadSelectsStartingEpisode() {
        let sut = makeSUT()
        sut.player.load(queue: sampleEpisodes, startingAt: 1, podcast: samplePodcast)

        #expect(sut.player.currentEpisode == sampleEpisodes[1])
        #expect(sut.player.currentPodcast == samplePodcast)
        #expect(sut.engine.replacedURLs == [sampleEpisodes[1].audioURL])
    }

    @Test("An out-of-range start index is clamped rather than crashing")
    func outOfRangeIndexIsClamped() {
        let sut = makeSUT()
        sut.player.load(queue: sampleEpisodes, startingAt: 99, podcast: samplePodcast)
        #expect(sut.player.currentEpisode == sampleEpisodes[2])

        sut.player.load(queue: sampleEpisodes, startingAt: -5, podcast: samplePodcast)
        #expect(sut.player.currentEpisode == sampleEpisodes[0])
    }

    @Test("Loading an empty queue is ignored")
    func emptyQueueIsIgnored() {
        let sut = makeSUT()
        sut.player.load(queue: [], startingAt: 0, podcast: samplePodcast)
        #expect(sut.player.currentEpisode == nil)
    }

    // MARK: - Queue navigation

    @Test("Next advances through the queue")
    func nextAdvances() {
        let sut = makeSUT()
        sut.player.load(queue: sampleEpisodes, startingAt: 0, podcast: samplePodcast)
        sut.player.next()
        #expect(sut.player.currentEpisode == sampleEpisodes[1])
    }

    @Test("Next on the last episode stops instead of wrapping")
    func nextAtEndStops() {
        let sut = makeSUT()
        sut.player.load(queue: sampleEpisodes, startingAt: 2, podcast: samplePodcast)
        sut.player.play()
        sut.player.next()

        #expect(sut.player.currentEpisode == sampleEpisodes[2])
        #expect(!sut.player.isPlaying)
        #expect(!sut.player.canGoNext)
    }

    @Test("Next preserves whether we were playing")
    func nextPreservesPlaybackState() {
        let sut = makeSUT()
        sut.player.load(queue: sampleEpisodes, startingAt: 0, podcast: samplePodcast)
        sut.player.play()
        sut.player.next()
        #expect(sut.player.isPlaying)

        sut.player.pause()
        sut.player.next()
        #expect(!sut.player.isPlaying)
    }

    // The convention every podcast app follows: pressing back in the first few
    // seconds means "wrong episode, go back"; pressing it later means "replay
    // what I just missed".
    @Test("Previous goes back a track when barely started")
    func previousGoesBackNearTheStart() {
        let sut = makeSUT()
        sut.player.load(queue: sampleEpisodes, startingAt: 1, podcast: samplePodcast)
        sut.engine.simulateProgress(elapsed: 1, duration: 600)

        sut.player.previous()

        #expect(sut.player.currentEpisode == sampleEpisodes[0])
    }

    @Test("Previous restarts the current episode once past the threshold")
    func previousRestartsWhenPastThreshold() {
        let sut = makeSUT()
        sut.player.load(queue: sampleEpisodes, startingAt: 1, podcast: samplePodcast)
        sut.engine.simulateProgress(elapsed: 120, duration: 600)

        sut.player.previous()

        #expect(sut.player.currentEpisode == sampleEpisodes[1])
        #expect(sut.engine.seekTimes.last == 0)
    }

    @Test("Previous on the first episode restarts it and never underflows")
    func previousAtStartRestarts() {
        let sut = makeSUT()
        sut.player.load(queue: sampleEpisodes, startingAt: 0, podcast: samplePodcast)
        sut.engine.simulateProgress(elapsed: 120, duration: 600)

        sut.player.previous()

        #expect(sut.player.currentEpisode == sampleEpisodes[0])
        #expect(sut.engine.seekTimes.last == 0)
        #expect(!sut.player.canGoPrevious)
    }

    @Test("Finishing an episode advances automatically")
    func finishAutoAdvances() {
        let sut = makeSUT()
        sut.player.load(queue: sampleEpisodes, startingAt: 0, podcast: samplePodcast)
        sut.engine.simulateFinish()
        #expect(sut.player.currentEpisode == sampleEpisodes[1])
    }

    @Test("Finishing the last episode stops rather than looping")
    func finishAtEndStops() {
        let sut = makeSUT()
        sut.player.load(queue: sampleEpisodes, startingAt: 2, podcast: samplePodcast)
        sut.player.play()
        sut.engine.simulateFinish()

        #expect(sut.player.currentEpisode == sampleEpisodes[2])
        #expect(!sut.player.isPlaying)
    }

    // MARK: - Transport

    @Test("Play and pause track isPlaying and reach the engine")
    func playAndPauseTrackState() {
        let sut = makeSUT()
        sut.player.load(queue: sampleEpisodes, startingAt: 0, podcast: samplePodcast)

        sut.player.play()
        #expect(sut.player.isPlaying)
        #expect(sut.engine.playCallCount == 1)

        sut.player.pause()
        #expect(!sut.player.isPlaying)
        #expect(sut.engine.pauseCallCount == 1)
    }

    @Test("Play with nothing loaded does nothing")
    func playWithoutEpisodeDoesNothing() {
        let sut = makeSUT()
        sut.player.play()
        #expect(!sut.player.isPlaying)
        #expect(sut.engine.playCallCount == 0)
    }

    @Test("Seeking is clamped to the episode")
    func seekIsClamped() {
        let sut = makeSUT()
        sut.player.load(queue: sampleEpisodes, startingAt: 0, podcast: samplePodcast)
        sut.engine.simulateProgress(elapsed: 0, duration: 600)

        sut.player.seek(to: -50)
        #expect(sut.engine.seekTimes.last == 0)

        sut.player.seek(to: 9999)
        #expect(sut.engine.seekTimes.last == 600)
    }

    @Test("Playback failure clears the playing flag")
    func failureClearsPlayingFlag() {
        let sut = makeSUT()
        sut.player.load(queue: sampleEpisodes, startingAt: 0, podcast: samplePodcast)
        sut.player.play()

        sut.engine.simulateFailure()
        #expect(!sut.player.isPlaying)
    }

    // MARK: - Progress

    @Test("Progress callbacks update elapsed and duration")
    func progressUpdatesState() {
        let sut = makeSUT()
        sut.player.load(queue: sampleEpisodes, startingAt: 0, podcast: samplePodcast)
        sut.engine.simulateProgress(elapsed: 30, duration: 600)

        #expect(sut.player.elapsed == 30)
        #expect(sut.player.duration == 600)
    }

    @Test("A live duration overrides the feed's claim")
    func liveDurationOverridesFeed() {
        let sut = makeSUT()
        sut.player.load(queue: sampleEpisodes, startingAt: 0, podcast: samplePodcast)
        #expect(sut.player.duration == 1800)   // from the feed

        sut.engine.simulateProgress(elapsed: 0, duration: 1755)
        #expect(sut.player.duration == 1755)   // from the asset
    }

    @Test("A zero duration from the engine is ignored")
    func zeroDurationIsIgnored() {
        let sut = makeSUT()
        sut.player.load(queue: sampleEpisodes, startingAt: 0, podcast: samplePodcast)
        sut.engine.simulateProgress(elapsed: 5, duration: 0)
        #expect(sut.player.duration == 1800)
    }

    // MARK: - Now Playing

    @Test("Loading publishes metadata for the lock screen")
    func loadPublishesNowPlaying() {
        let sut = makeSUT()
        sut.player.load(queue: sampleEpisodes, startingAt: 0, podcast: samplePodcast)

        #expect(sut.nowPlaying.lastTitle == sampleEpisodes[0].title)
        #expect(sut.nowPlaying.lastArtist == samplePodcast.title)
    }

    @Test("Transport changes are mirrored to the lock screen")
    func transportUpdatesNowPlaying() {
        let sut = makeSUT()
        sut.player.load(queue: sampleEpisodes, startingAt: 0, podcast: samplePodcast)

        sut.player.play()
        #expect(sut.nowPlaying.lastIsPlaying == true)

        sut.player.pause()
        #expect(sut.nowPlaying.lastIsPlaying == false)
    }

    @Test("Advancing republishes for the new episode")
    func advancingRepublishes() {
        let sut = makeSUT()
        sut.player.load(queue: sampleEpisodes, startingAt: 0, podcast: samplePodcast)
        sut.player.next()
        #expect(sut.nowPlaying.lastTitle == sampleEpisodes[1].title)
    }
}
