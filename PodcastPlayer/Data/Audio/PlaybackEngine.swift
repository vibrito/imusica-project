import AVFoundation
import Foundation

/// The audio primitive, behind a protocol.
///
/// Queue navigation is where the real branching lives, and it has nothing to do
/// with AVFoundation. Splitting the engine out means next/previous/auto-advance
/// are testable without audio hardware or a simulator clock.
@MainActor
protocol PlaybackEngine: AnyObject {
    var onProgress: ((TimeInterval, TimeInterval) -> Void)? { get set }
    var onFinish: (() -> Void)? { get set }
    var onFailure: (() -> Void)? { get set }

    func replaceItem(url: URL)
    func play()
    func pause()
    func seek(to time: TimeInterval)
}

/// The real engine.
@MainActor
final class AVPlayerEngine: PlaybackEngine {
    var onProgress: ((TimeInterval, TimeInterval) -> Void)?
    var onFinish: (() -> Void)?
    var onFailure: (() -> Void)?

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        observeProgress()
    }

    // Isolated so it can touch main-actor state. The periodic observer retains
    // its closure; leaking it would keep the whole service alive after the
    // player is gone.
    isolated deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
    }

    func replaceItem(url: URL) {
        let item = AVPlayerItem(url: url)
        observeEnd(of: item)
        player.replaceCurrentItem(with: item)
    }

    func play() { player.play() }
    func pause() { player.pause() }

    func seek(to time: TimeInterval) {
        player.seek(
            to: CMTime(seconds: time, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func observeProgress() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                let duration = self.player.currentItem?.duration.seconds ?? 0
                self.onProgress?(time.seconds, duration.isFinite ? duration : 0)
            }
        }
    }

    private func observeEnd(of item: AVPlayerItem) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onFinish?() }
        }

        failureObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onFailure?() }
        }
    }
}
