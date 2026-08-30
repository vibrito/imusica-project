import Testing
import Foundation
import MediaPlayer
import UIKit
@testable import PodcastPlayer

@MainActor
@Suite("NowPlayingPublisher", .serialized)
struct NowPlayingPublisherTests {

    private func makeImageData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        let image = renderer.image { context in
            UIColor.systemPurple.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        return image.pngData() ?? Data()
    }

    @Test("Publishes the metadata a lock screen needs")
    func publishesMetadata() {
        let sut = NowPlayingPublisher()
        defer { sut.clear() }

        sut.publish(episode: sampleEpisodes[0], podcast: samplePodcast, artwork: nil)

        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        #expect(info?[MPMediaItemPropertyTitle] as? String == sampleEpisodes[0].title)
        #expect(info?[MPMediaItemPropertyArtist] as? String == samplePodcast.title)
        #expect(info?[MPMediaItemPropertyPlaybackDuration] as? TimeInterval == 1800)
    }

    @Test("Playback updates reach the info centre")
    func updatesPlaybackState() {
        let sut = NowPlayingPublisher()
        defer { sut.clear() }

        sut.publish(episode: sampleEpisodes[0], podcast: samplePodcast, artwork: nil)
        sut.updatePlayback(elapsed: 42, duration: 600, isPlaying: true)

        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        #expect(info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? TimeInterval == 42)
        #expect(info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1.0)
    }

    @Test("Clearing removes the now playing entry")
    func clearRemovesInfo() {
        let sut = NowPlayingPublisher()
        sut.publish(episode: sampleEpisodes[0], podcast: samplePodcast, artwork: nil)
        sut.clear()

        #expect(MPNowPlayingInfoCenter.default().nowPlayingInfo == nil)
    }

    /// Regression test for a crash that only ever reproduced against real
    /// feeds: MediaPlayer invokes the artwork request handler on a background
    /// queue, and a handler built inside a @MainActor method carries an
    /// isolation assertion that traps when it does. Fixture feeds have no
    /// resolvable artwork, so nothing caught it until a live feed did.
    @Test("Artwork can be requested off the main actor without trapping")
    func artworkHandlerIsSafeOffTheMainActor() throws {
        let sut = NowPlayingPublisher()
        defer { sut.clear() }

        sut.publish(episode: sampleEpisodes[0], podcast: samplePodcast, artwork: makeImageData())

        let artwork = try #require(
            MPNowPlayingInfoCenter.default()
                .nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork,
            "Artwork was not published"
        )

        // Exactly what MediaPlayer does: request the image from a background
        // thread. A synchronous dispatch, so there is no actor hop to launder
        // the isolation the crash depended on. Before the fix this trapped
        // with SIGILL inside dispatch_assert_queue.
        var size: CGSize?
        DispatchQueue.global(qos: .userInitiated).sync {
            size = artwork.image(at: CGSize(width: 10, height: 10))?.size
        }

        #expect(size != nil)
    }

    @Test("A feed with no artwork publishes without one")
    func handlesMissingArtwork() {
        let sut = NowPlayingPublisher()
        defer { sut.clear() }

        sut.publish(episode: sampleEpisodes[0], podcast: samplePodcast, artwork: Data("not an image".utf8))

        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        #expect(info?[MPMediaItemPropertyArtwork] == nil)
        #expect(info?[MPMediaItemPropertyTitle] as? String == sampleEpisodes[0].title)
    }
}
