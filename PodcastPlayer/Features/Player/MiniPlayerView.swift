import SwiftUI

/// The docked player that rides above the tab bar.
///
/// Lives in `.tabViewBottomAccessory`, so it behaves the way every listener
/// already expects from Apple Music: always reachable, never in the way, and it
/// expands into the full player on tap.
struct MiniPlayerView: View {
    @State private var viewModel: PlayerViewModel
    let expand: () -> Void

    init(viewModel: PlayerViewModel, expand: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.expand = expand
    }

    var body: some View {
        if let episode = viewModel.episode {
            HStack(spacing: 12) {
                AsyncCachedImage(
                    url: episode.imageURL ?? viewModel.podcast?.imageURL,
                    cornerRadius: 8
                )
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text(episode.title)
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                        .accessibilityIdentifier("mini.title")

                    if let podcast = viewModel.podcast {
                        Text(podcast.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Button(action: viewModel.togglePlayPause) {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.body)
                        .frame(width: 40, height: 40)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
                .accessibilityIdentifier("mini.playPause")
            }
            .padding(.horizontal, 12)
            .contentShape(.rect)
            .onTapGesture(perform: expand)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mini.container")
        }
    }
}
