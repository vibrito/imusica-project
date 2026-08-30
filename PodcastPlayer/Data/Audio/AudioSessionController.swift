import AVFoundation
import Foundation
import MediaPlayer

/// Owns the parts of background playback that are process-wide: the audio
/// session and the remote command centre.
///
/// Separate from AudioPlayerService because these are singletons imposed by the
/// system, and mixing them into the queue logic would make that untestable.
@MainActor
final class AudioSessionController {
    private let player: AudioPlaying
    private let session: AVAudioSession
    private let commands: MPRemoteCommandCenter
    private var wasPlayingBeforeInterruption = false

    init(
        player: AudioPlaying,
        session: AVAudioSession = .sharedInstance(),
        commands: MPRemoteCommandCenter = .shared()
    ) {
        self.player = player
        self.session = session
        self.commands = commands
    }

    func activate() {
        configureSession()
        configureRemoteCommands()
        observeInterruptions()
    }

    private func configureSession() {
        do {
            // .spokenAudio gets podcast-appropriate behaviour: it ducks rather
            // than stops for navigation prompts, and honours the system's
            // spoken-content routing.
            try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
            try session.setActive(true)
        } catch {
            // A session that will not activate means no audio, but the rest of
            // the app still works — browsing and caching are unaffected.
        }
    }

    private func configureRemoteCommands() {
        commands.playCommand.addTarget { [weak self] _ in
            self?.player.play()
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            self?.player.pause()
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if player.isPlaying { player.pause() } else { player.play() }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            guard let self, player.canGoNext else { return .noSuchContent }
            player.next()
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            self?.player.previous()
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            player.seek(to: event.positionTime)
            return .success
        }

        // Skip buttons are what listeners actually reach for in spoken audio.
        commands.skipForwardCommand.preferredIntervals = [30]
        commands.skipBackwardCommand.preferredIntervals = [15]
        commands.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            player.seek(to: player.elapsed + 30)
            return .success
        }
        commands.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            player.seek(to: max(0, player.elapsed - 15))
            return .success
        }
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            // Notification is not Sendable, so pull the primitives out here and
            // carry only those across the actor hop.
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            MainActor.assumeIsolated {
                self?.handleInterruption(typeRaw: type, optionsRaw: options)
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                self?.handleRouteChange(reasonRaw: reason)
            }
        }
    }

    private func handleInterruption(typeRaw: UInt?, optionsRaw: UInt?) {
        guard let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }

        switch type {
        case .began:
            wasPlayingBeforeInterruption = player.isPlaying
            player.pause()

        case .ended:
            // Resume only when the system says so. Barging back in after a
            // phone call the user is still on is exactly the wrong behaviour.
            guard wasPlayingBeforeInterruption,
                  let optionsRaw,
                  AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume)
            else { return }
            player.play()

        @unknown default:
            break
        }
    }

    private func handleRouteChange(reasonRaw: UInt?) {
        guard let reasonRaw,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }

        // Headphones unplugged: pause, never blast the episode out loud.
        if reason == .oldDeviceUnavailable {
            player.pause()
        }
    }
}
