import SwiftUI

/// One episode in the list. Tapping anywhere plays it.
struct EpisodeRow: View {
    let episode: Episode
    let fallbackImageURL: URL?
    let isCurrent: Bool
    let play: () -> Void

    var body: some View {
        Button(action: play) {
            HStack(alignment: .top, spacing: 12) {
                AsyncCachedImage(url: episode.imageURL ?? fallbackImageURL, cornerRadius: 10)
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(episode.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let description = episode.description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    HStack(spacing: 8) {
                        if let published = episode.publishedAt {
                            Text(Formatters.relativeDate(published))
                        }
                        Text(Formatters.duration(episode.duration))
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)

                Image(systemName: isCurrent ? "speaker.wave.2.fill" : "play.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 36, height: 36)
                    .glassCircle()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 18)
        // One element for VoiceOver, not five fragments.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Plays this episode")
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        var parts = [episode.title]
        if let duration = episode.duration {
            parts.append(Formatters.spokenDuration(duration))
        }
        if isCurrent { parts.append("Now playing") }
        return parts.joined(separator: ", ")
    }
}
