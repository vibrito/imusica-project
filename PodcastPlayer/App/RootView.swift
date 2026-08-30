import SwiftUI

/// The app shell: tabs, navigation, and the docked mini player.
struct RootView: View {
    let environment: AppEnvironment

    @State private var path: [Podcast] = []
    @State private var showingPlayer = false
    /// Held here so the selected tab survives the accessory being attached the
    /// first time something plays.
    @State private var selectedTab = Tabs.browse

    private enum Tabs: Hashable { case browse, settings }

    var body: some View {
        Group {
            // The accessory is attached only while something is playing.
            // Attaching it unconditionally leaves an empty glass pill floating
            // above the tab bar on first launch.
            if environment.player.currentEpisode != nil {
                tabs.tabViewBottomAccessory {
                    MiniPlayerView(viewModel: environment.makePlayerViewModel()) {
                        showingPlayer = true
                    }
                }
            } else {
                tabs
            }
        }
        .sheet(isPresented: $showingPlayer) {
            PlayerView(viewModel: environment.makePlayerViewModel())
                .presentationDetents([.large])
        }
        .environment(\.imageLoader, environment.images)
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Browse", systemImage: "waveform", value: Tabs.browse) {
                BrowseView(environment: environment, path: $path)
            }

            Tab("Settings", systemImage: "gearshape", value: Tabs.settings) {
                NavigationStack {
                    SettingsView(viewModel: environment.makeSettingsViewModel())
                }
            }
        }
        // The tab bar shrinks out of the way as you read down an episode list.
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

/// Screen 1 and 2, adapting to the width available.
private struct BrowseView: View {
    let environment: AppEnvironment
    @Binding var path: [Podcast]
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            // On iPad and in landscape, the form and the podcast sit side by
            // side rather than pushing each other off screen.
            NavigationSplitView {
                feedSource
            } detail: {
                if let podcast = path.last {
                    NavigationStack {
                        detail(for: podcast)
                    }
                } else {
                    ContentUnavailableView(
                        "No podcast selected",
                        systemImage: "waveform",
                        description: Text("Add a feed address to get started.")
                    )
                }
            }
        } else {
            NavigationStack(path: $path) {
                feedSource
                    .navigationDestination(for: Podcast.self) { podcast in
                        detail(for: podcast)
                    }
            }
        }
    }

    private var feedSource: some View {
        FeedSourceView(viewModel: environment.makeFeedSourceViewModel()) { podcast in
            path = [podcast]
        }
    }

    private func detail(for podcast: Podcast) -> some View {
        let viewModel = environment.makeDetailViewModel(for: podcast.feedURL)
        // Seeded with what screen 1 already fetched, so navigating in never
        // shows a spinner for data we are holding.
        viewModel.prime(with: podcast)
        return PodcastDetailView(viewModel: viewModel)
            .id(podcast.feedURL)
    }
}
