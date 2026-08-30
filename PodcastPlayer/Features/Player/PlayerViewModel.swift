import Foundation

/// Screen 3: what is playing, and the controls for it.
///
/// Holds no playback state of its own — the service owns that, because playback
/// outlives any screen. This exists to turn that state into something a view
/// can render, and to own the one piece of genuinely local state: scrubbing.
@MainActor
@Observable
final class PlayerViewModel {
    private let player: any AudioPlaying

    /// Where the user's finger is, while a drag is in progress. Nil otherwise.
    private(set) var scrubPosition: TimeInterval?

    init(player: any AudioPlaying) {
        self.player = player
    }

    var episode: Episode? { player.currentEpisode }
    var podcast: Podcast? { player.currentPodcast }
    var isPlaying: Bool { player.isPlaying }
    var canGoNext: Bool { player.canGoNext }
    var canGoPrevious: Bool { player.canGoPrevious }
    var hasEpisode: Bool { player.currentEpisode != nil }
    var isScrubbing: Bool { scrubPosition != nil }

    var duration: TimeInterval { player.duration }

    /// The position to display: the thumb while dragging, playback otherwise.
    var displayedElapsed: TimeInterval { scrubPosition ?? player.elapsed }

    /// 0...1, and safe before a duration is known.
    var progress: Double {
        guard player.duration > 0 else { return 0 }
        return min(1, max(0, displayedElapsed / player.duration))
    }

    var elapsedText: String { Formatters.timecode(displayedElapsed) }

    var remainingText: String {
        Formatters.remaining(elapsed: displayedElapsed, duration: player.duration)
    }

    /// What VoiceOver announces for the progress slider.
    var progressAccessibilityValue: String {
        guard player.duration > 0 else { return "Position unknown" }
        return "\(Formatters.spokenDuration(displayedElapsed)) elapsed, "
             + "\(Formatters.spokenDuration(max(0, player.duration - displayedElapsed))) remaining"
    }

    func togglePlayPause() {
        if player.isPlaying { player.pause() } else { player.play() }
    }

    func next() { player.next() }
    func previous() { player.previous() }

    func skipForward() { player.seek(to: player.elapsed + 30) }
    func skipBackward() { player.seek(to: max(0, player.elapsed - 15)) }

    // MARK: - Scrubbing

    func beginScrubbing() {
        scrubPosition = player.elapsed
    }

    /// Tracks the thumb without seeking. Seeking on every drag update would
    /// stutter the audio and hammer the player with work it will discard.
    func scrub(to fraction: Double) {
        guard player.duration > 0 else { return }
        scrubPosition = min(1, max(0, fraction)) * player.duration
    }

    func endScrubbing() {
        guard let scrubPosition else { return }
        player.seek(to: scrubPosition)
        self.scrubPosition = nil
    }
}
