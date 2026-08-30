import SwiftUI

@main
struct PodcastPlayerApp: App {
    @State private var environment: AppEnvironment

    init() {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

        if isUITesting {
            _environment = State(initialValue: .uiTesting())
        } else {
            // A corrupt or unopenable store must not stop the app launching.
            // Falling back gives the user an app that forgets things, which
            // beats one that will not start.
            _environment = State(initialValue: (try? .live()) ?? .fallback())
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
        }
    }
}
