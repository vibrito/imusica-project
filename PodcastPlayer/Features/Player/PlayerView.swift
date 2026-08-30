import SwiftUI

/// Screen 3: the full player.
struct PlayerView: View {
    @State private var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: PlayerViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let episode = viewModel.episode {
                content(episode)
            } else {
                ContentUnavailableView("Nothing playing", systemImage: "waveform")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDragIndicator(.visible)
    }

    private func content(_ episode: Episode) -> some View {
        VStack(spacing: 28) {
            Spacer(minLength: 12)

            AsyncCachedImage(
                url: episode.imageURL ?? viewModel.podcast?.imageURL,
                cornerRadius: 24
            )
            .frame(maxWidth: 320)
            .aspectRatio(1, contentMode: .fit)
            .shadow(color: .black.opacity(0.25), radius: 24, y: 12)

            metadata(episode)
            progress
            transport

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    // MARK: - Metadata

    private func metadata(_ episode: Episode) -> some View {
        VStack(spacing: 6) {
            Text(episode.title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                // Left free to wrap and grow. A fixed line limit clips the
                // title outright at accessibility text sizes.
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("player.title")

            if let podcast = viewModel.podcast {
                Text(podcast.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("player.podcast")

                if let author = podcast.author {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Progress

    private var progress: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { viewModel.progress },
                    set: { viewModel.scrub(to: $0) }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    if editing { viewModel.beginScrubbing() } else { viewModel.endScrubbing() }
                }
            )
            .disabled(viewModel.duration <= 0)
            .accessibilityIdentifier("player.progress")
            .accessibilityLabel("Playback position")
            .accessibilityValue(viewModel.progressAccessibilityValue)

            HStack {
                Text(viewModel.elapsedText)
                Spacer()
                Text(viewModel.remainingText)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Transport

    private var transport: some View {
        GlassGroup(spacing: 16) {
            HStack(spacing: 16) {
                transportButton("backward.end.fill", label: "Previous episode",
                                identifier: "player.previous", enabled: viewModel.canGoPrevious) {
                    viewModel.previous()
                }

                transportButton("gobackward.15", label: "Skip back 15 seconds",
                                identifier: "player.skipBack", enabled: true) {
                    viewModel.skipBackward()
                }

                Button(action: viewModel.togglePlayPause) {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title.weight(.semibold))
                        .frame(width: 76, height: 76)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassCircle(tinted: true)
                .disabled(!viewModel.hasEpisode)
                .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
                .accessibilityIdentifier("player.playPause")

                transportButton("goforward.30", label: "Skip forward 30 seconds",
                                identifier: "player.skipForward", enabled: true) {
                    viewModel.skipForward()
                }

                transportButton("forward.end.fill", label: "Next episode",
                                identifier: "player.next", enabled: viewModel.canGoNext) {
                    viewModel.next()
                }
            }
        }
    }

    private func transportButton(
        _ symbol: String,
        label: String,
        identifier: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                // 44pt is the minimum comfortable target; anything less is a
                // miss waiting to happen.
                .frame(width: 52, height: 52)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassCircle()
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
