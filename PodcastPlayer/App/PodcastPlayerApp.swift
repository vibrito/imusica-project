import SwiftUI

@main
struct PodcastPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            // Replaced by RootView in Task 18, once AppEnvironment exists to
            // inject. Kept deliberately trivial so the scaffold commit builds
            // and runs on its own.
            ContentUnavailableView(
                "Podcast Player",
                systemImage: "waveform",
                description: Text("Scaffold in place.")
            )
        }
    }
}
