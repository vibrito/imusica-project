import SwiftUI

/// Cache inspection and clearing, as the brief requires.
struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @State private var pendingAction: ClearAction?

    init(viewModel: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    enum ClearAction: String, Identifiable {
        case feeds, images, history
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .feeds: "Clear podcast cache?"
            case .images: "Clear image cache?"
            case .history: "Clear recent addresses?"
            }
        }

        var message: LocalizedStringKey {
            switch self {
            case .feeds: "Podcasts will be downloaded again next time you open them."
            case .images: "Artwork will be downloaded again as you browse."
            case .history: "The list of addresses you've opened will be forgotten."
            }
        }
    }

    var body: some View {
        List {
            Section {
                row(label: "Podcasts", value: viewModel.feedCacheText,
                    valueIdentifier: "settings.feedCacheValue",
                    buttonIdentifier: "settings.clearFeeds",
                    enabled: viewModel.hasFeedCache) { pendingAction = .feeds }

                row(label: "Images", value: viewModel.imageCacheText,
                    valueIdentifier: "settings.imageCacheValue",
                    buttonIdentifier: "settings.clearImages",
                    enabled: viewModel.hasImageCache) { pendingAction = .images }
            } header: {
                Text("Cache")
            } footer: {
                Text("Podcasts are re-checked with the server every hour and used offline in between.")
            }

            Section {
                row(label: "Recent addresses", value: viewModel.historyText,
                    valueIdentifier: "settings.historyValue",
                    buttonIdentifier: "settings.clearHistory",
                    enabled: viewModel.hasHistory) { pendingAction = .history }
            } header: {
                Text("History")
            }
        }
        .navigationTitle("Settings")
        .task { await viewModel.refresh() }
        .alert(
            pendingAction?.title ?? LocalizedStringKey(""),
            isPresented: Binding(get: { pendingAction != nil },
                                 set: { if !$0 { pendingAction = nil } }),
            presenting: pendingAction
        ) { action in
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                Task {
                    switch action {
                    case .feeds: await viewModel.clearFeedCache()
                    case .images: await viewModel.clearImageCache()
                    case .history: await viewModel.clearHistory()
                    }
                }
            }
        } message: { action in
            Text(action.message)
        }
    }

    private func row(
        // LocalizedStringKey, not String: Text(String) uses the non-localizing
        // initializer and would ship these untranslated.
        label: LocalizedStringKey,
        value: String,
        valueIdentifier: String,
        buttonIdentifier: String,
        enabled: Bool,
        clear: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(valueIdentifier)
            Button("Clear", action: clear)
                .buttonStyle(.borderless)
                .disabled(!enabled)
                .accessibilityIdentifier(buttonIdentifier)
        }
    }
}
