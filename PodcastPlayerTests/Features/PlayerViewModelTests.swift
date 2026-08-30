import Testing
import Foundation
@testable import PodcastPlayer

@MainActor
@Suite("PlayerViewModel")
struct PlayerViewModelTests {

    private func makeSUT(
        duration: TimeInterval = 600,
        elapsed: TimeInterval = 0,
        isPlaying: Bool = false
    ) -> (sut: PlayerViewModel, player: FakePlayer) {
        let player = FakePlayer()
        player.duration = duration
        player.elapsed = elapsed
        player.isPlaying = isPlaying
        player.currentEpisode = sampleEpisodes[0]
        return (PlayerViewModel(player: player), player)
    }

    // MARK: - Progress

    @Test("Progress is zero before a duration is known, and never divides by it")
    func progressIsSafeWithoutDuration() {
        let (sut, _) = makeSUT(duration: 0, elapsed: 0)
        #expect(sut.progress == 0)
    }

    @Test("Progress reflects elapsed over duration")
    func progressReflectsPosition() {
        let (sut, _) = makeSUT(duration: 600, elapsed: 150)
        #expect(sut.progress == 0.25)
    }

    @Test("Progress is clamped when elapsed overshoots the duration")
    func progressIsClamped() {
        let (sut, _) = makeSUT(duration: 600, elapsed: 900)
        #expect(sut.progress == 1)
    }

    @Test("Elapsed and remaining read as transport timecodes")
    func formatsTransportText() {
        let (sut, _) = makeSUT(duration: 600, elapsed: 150)
        #expect(sut.elapsedText == "02:30")
        #expect(sut.remainingText == "-07:30")
    }

    // MARK: - Transport

    @Test("Toggle plays when paused and pauses when playing")
    func toggleFlipsPlayback() {
        let (sut, player) = makeSUT(isPlaying: false)

        sut.togglePlayPause()
        #expect(player.playCallCount == 1)

        player.isPlaying = true
        sut.togglePlayPause()
        #expect(player.pauseCallCount == 1)
    }

    @Test("Next and previous delegate to the player")
    func transportDelegates() {
        let (sut, player) = makeSUT()

        sut.next()
        sut.previous()

        #expect(player.nextCallCount == 1)
        #expect(player.previousCallCount == 1)
    }

    @Test("Transport availability mirrors the queue")
    func availabilityMirrorsQueue() {
        let (sut, player) = makeSUT()
        player.canGoNext = false
        player.canGoPrevious = true

        #expect(!sut.canGoNext)
        #expect(sut.canGoPrevious)
    }

    @Test("Skip forward and back move by the spoken-audio conventions")
    func skipsByConventionalIntervals() {
        let (sut, player) = makeSUT(duration: 600, elapsed: 100)

        sut.skipForward()
        #expect(player.seekTimes.last == 130)

        sut.skipBackward()
        #expect(player.seekTimes.last == 85)
    }

    @Test("Skipping back near the start clamps to zero")
    func skipBackClampsAtZero() {
        let (sut, player) = makeSUT(duration: 600, elapsed: 5)
        sut.skipBackward()
        #expect(player.seekTimes.last == 0)
    }

    // MARK: - Scrubbing

    @Test("Dragging does not seek until the finger lifts")
    func scrubbingDefersTheSeek() {
        let (sut, player) = makeSUT(duration: 600, elapsed: 0)

        sut.beginScrubbing()
        sut.scrub(to: 0.5)

        // Seeking on every drag update would stutter the audio.
        #expect(player.seekTimes.isEmpty)
        #expect(sut.elapsedText == "05:00")
        #expect(sut.isScrubbing)

        sut.endScrubbing()
        #expect(player.seekTimes == [300])
        #expect(!sut.isScrubbing)
    }

    @Test("While dragging, the labels follow the thumb rather than playback")
    func labelsFollowTheThumb() {
        let (sut, player) = makeSUT(duration: 600, elapsed: 100)

        sut.beginScrubbing()
        sut.scrub(to: 0.75)
        player.elapsed = 105     // playback continues underneath

        #expect(sut.displayedElapsed == 450)
        #expect(sut.remainingText == "-02:30")
    }

    @Test("Scrub fractions are clamped to the track")
    func scrubIsClamped() {
        let (sut, player) = makeSUT(duration: 600)

        sut.beginScrubbing()
        sut.scrub(to: 1.5)
        sut.endScrubbing()
        #expect(player.seekTimes.last == 600)

        sut.beginScrubbing()
        sut.scrub(to: -0.5)
        sut.endScrubbing()
        #expect(player.seekTimes.last == 0)
    }

    @Test("Ending a drag that never began does not seek")
    func endWithoutBeginDoesNothing() {
        let (sut, player) = makeSUT()
        sut.endScrubbing()
        #expect(player.seekTimes.isEmpty)
    }

    @Test("Scrubbing without a known duration is ignored")
    func scrubbingWithoutDurationIsIgnored() {
        let (sut, player) = makeSUT(duration: 0)
        sut.beginScrubbing()
        sut.scrub(to: 0.5)
        sut.endScrubbing()
        #expect(player.seekTimes == [0])
    }

    // MARK: - Accessibility

    @Test("VoiceOver hears a spoken position, not a clock time")
    func announcesSpokenPosition() {
        let (sut, _) = makeSUT(duration: 3600, elapsed: 1800)
        #expect(sut.progressAccessibilityValue == "30 minutes elapsed, 30 minutes remaining")
    }

    @Test("An unknown duration announces as unknown rather than as zero")
    func announcesUnknownPosition() {
        let (sut, _) = makeSUT(duration: 0)
        #expect(sut.progressAccessibilityValue == "Position unknown")
    }

    @Test("Reports whether anything is loaded at all")
    func reportsWhetherLoaded() {
        let player = FakePlayer()
        let sut = PlayerViewModel(player: player)
        #expect(!sut.hasEpisode)

        player.currentEpisode = sampleEpisodes[0]
        #expect(sut.hasEpisode)
    }
}
