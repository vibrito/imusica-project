import Foundation

/// Playback plus the queue.
///
/// The queue lives here rather than on a screen because next/previous must keep
/// working when the UI that started playback is long gone — from the mini
/// player, the lock screen, or a pair of headphones.
@MainActor
@Observable
final class AudioPlayerService: AudioPlaying {
    private(set) var currentEpisode: Episode?
    private(set) var currentPodcast: Podcast?
    private(set) var isPlaying = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    private var queue: [Episode] = []
    private var index: Int = 0

    private let engine: PlaybackEngine
    private let nowPlaying: NowPlayingPublishing
    private let images: ImageLoading?

    var canGoNext: Bool { index + 1 < queue.count }
    var canGoPrevious: Bool { index > 0 }

    init(engine: PlaybackEngine, nowPlaying: NowPlayingPublishing, images: ImageLoading? = nil) {
        self.engine = engine
        self.nowPlaying = nowPlaying
        self.images = images
        wireEngine()
    }

    func load(queue episodes: [Episode], startingAt startIndex: Int, podcast: Podcast) {
        guard !episodes.isEmpty else { return }

        queue = episodes
        index = min(max(startIndex, 0), episodes.count - 1)
        currentPodcast = podcast
        activate(queue[index])
    }

    func play() {
        guard currentEpisode != nil else { return }
        engine.play()
        isPlaying = true
        publishPlaybackState()
    }

    func pause() {
        engine.pause()
        isPlaying = false
        publishPlaybackState()
    }

    func next() {
        guard canGoNext else {
            // The end of the queue stops rather than wrapping. Silently
            // restarting a show someone just finished is worse than stopping.
            pause()
            return
        }
        index += 1
        let wasPlaying = isPlaying
        activate(queue[index])
        if wasPlaying { play() }
    }

    func previous() {
        // Matching every podcast app: the first press restarts the episode, and
        // only a second one goes back a track.
        guard canGoPrevious, elapsed <= Self.restartThreshold else {
            seek(to: 0)
            return
        }
        index -= 1
        let wasPlaying = isPlaying
        activate(queue[index])
        if wasPlaying { play() }
    }

    func seek(to time: TimeInterval) {
        let clamped = max(0, duration > 0 ? min(time, duration) : time)
        engine.seek(to: clamped)
        elapsed = clamped
        publishPlaybackState()
    }

    /// How long into an episode "previous" stops meaning "restart this one".
    static let restartThreshold: TimeInterval = 3

    // MARK: - Private

    private func activate(_ episode: Episode) {
        currentEpisode = episode
        elapsed = 0
        duration = episode.duration ?? 0
        engine.replaceItem(url: episode.audioURL)

        guard let podcast = currentPodcast else { return }
        nowPlaying.publish(episode: episode, podcast: podcast, artwork: nil)
        loadArtwork(for: episode, podcast: podcast)
    }

    private func loadArtwork(for episode: Episode, podcast: Podcast) {
        guard let images, let url = episode.imageURL ?? podcast.imageURL else { return }
        Task { [weak self] in
            let data = await images.image(for: url)
            guard let self, self.currentEpisode == episode, let data else { return }
            self.nowPlaying.publish(episode: episode, podcast: podcast, artwork: data)
            self.publishPlaybackState()
        }
    }

    private func publishPlaybackState() {
        nowPlaying.updatePlayback(elapsed: elapsed, duration: duration, isPlaying: isPlaying)
    }

    private func wireEngine() {
        engine.onProgress = { [weak self] elapsed, duration in
            guard let self else { return }
            self.elapsed = elapsed
            // A live duration from the asset beats the feed's claim, which is
            // frequently rounded or simply wrong.
            if duration > 0 { self.duration = duration }
            self.publishPlaybackState()
        }

        engine.onFinish = { [weak self] in
            self?.next()
        }

        engine.onFailure = { [weak self] in
            self?.isPlaying = false
        }
    }
}
