import SwiftUI

/// Screen 2: the podcast, and every episode in it.
struct PodcastDetailView: View {
    @State private var viewModel: PodcastDetailViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

    /// At accessibility sizes an unconstrained header fills the entire screen,
    /// leaving no episode visible — the lazy grid never even materialises a
    /// row. The header gives ground so the list stays reachable.
    private var isAccessibilitySize: Bool { typeSize.isAccessibilitySize }

    init(viewModel: PodcastDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        StateView(state: viewModel.state, retry: { Task { await viewModel.retry() } },
                  emptyMessage: "No episodes published yet") { podcast in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24, pinnedViews: []) {
                    header(podcast)
                    episodeList(podcast)
                }
                .padding(.bottom, 24)
            }
            .refreshable { await viewModel.refresh() }
            .softScrollEdges()
        }
        .navigationTitle(viewModel.state.value?.title ?? "Podcast")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    // MARK: - Header

    private func header(_ podcast: Podcast) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                AsyncCachedImage(url: podcast.imageURL, cornerRadius: 16)
                    .frame(width: isAccessibilitySize ? 84 : 132,
                           height: isAccessibilitySize ? 84 : 132)

                VStack(alignment: .leading, spacing: 6) {
                    Text(podcast.title)
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("detail.title")

                    if let author = podcast.author {
                        Text(author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("detail.author")
                    }

                    if let genre = podcast.primaryCategory {
                        Text(genre)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .glassCard(cornerRadius: 10)
                            .accessibilityIdentifier("detail.genre")
                    }

                    Text(Formatters.episodeCount(podcast.episodes.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if let description = podcast.description {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    // Capped at accessibility sizes so the show blurb cannot
                    // push every episode below the fold. VoiceOver still reads
                    // the full text.
                    .lineLimit(isAccessibilitySize ? 4 : nil)
                    .accessibilityIdentifier("detail.description")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassHeaderBackground()
    }

    // MARK: - Episodes

    private var columns: [GridItem] {
        // Wide screens get two columns so an iPad does not show one narrow
        // ribbon of text down the middle.
        sizeClass == .regular
            ? [GridItem(.adaptive(minimum: 320), spacing: 12)]
            : [GridItem(.flexible())]
    }

    private func episodeList(_ podcast: Podcast) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(podcast.episodes.enumerated()), id: \.element.id) { index, episode in
                EpisodeRow(
                    episode: episode,
                    fallbackImageURL: podcast.imageURL,
                    isCurrent: viewModel.isCurrent(episode)
                ) {
                    viewModel.play(episode)
                }
                .accessibilityIdentifier("detail.episodeRow.\(index)")
            }
        }
        .padding(.horizontal, 20)
        .accessibilityIdentifier("detail.episodeList")
    }
}
