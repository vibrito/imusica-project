import Foundation
import MediaPlayer
import UIKit

/// Publishes what is playing to the lock screen, Control Center, and CarPlay.
@MainActor
protocol NowPlayingPublishing: AnyObject {
    func publish(episode: Episode, podcast: Podcast, artwork: Data?)
    func updatePlayback(elapsed: TimeInterval, duration: TimeInterval, isPlaying: Bool)
    func clear()
}

@MainActor
final class NowPlayingPublisher: NowPlayingPublishing {
    private let center: MPNowPlayingInfoCenter

    init(center: MPNowPlayingInfoCenter = .default()) {
        self.center = center
    }

    func publish(episode: Episode, podcast: Podcast, artwork: Data?) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: episode.title,
            // The show name belongs in Artist: it is what identifies the
            // episode on a lock screen, where the album line is easy to miss.
            MPMediaItemPropertyArtist: podcast.title,
            MPMediaItemPropertyAlbumTitle: podcast.author ?? podcast.title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: false,
        ]

        if let duration = episode.duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        if let artwork, let image = UIImage(data: artwork) {
            info[MPMediaItemPropertyArtwork] = Self.makeArtwork(image)
        }

        center.nowPlayingInfo = info
    }

    func updatePlayback(elapsed: TimeInterval, duration: TimeInterval, isPlaying: Bool) {
        guard var info = center.nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        center.nowPlayingInfo = info
    }

    func clear() {
        center.nowPlayingInfo = nil
    }

    /// Builds the artwork wrapper outside main-actor isolation.
    ///
    /// MediaPlayer calls this request handler on a background queue. Creating
    /// the closure inside a @MainActor method makes Swift 6 attach an isolation
    /// assertion to it, which then traps the moment the system asks for
    /// artwork — a hard crash, and only ever on feeds that actually have an
    /// image. Reading an already-decoded UIImage concurrently is safe, so the
    /// handler is deliberately nonisolated.
    private nonisolated static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
