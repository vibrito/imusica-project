import SwiftUI

/// Screen 1: the RSS source form, plus the addresses used before.
struct FeedSourceView: View {
    @State private var viewModel: FeedSourceViewModel
    @FocusState private var fieldIsFocused: Bool
    @State private var showingClearHistory = false

    let onLoaded: (Podcast) -> Void

    init(viewModel: FeedSourceViewModel, onLoaded: @escaping (Podcast) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onLoaded = onLoaded
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                form
                if case .failed(let error) = viewModel.state {
                    errorBanner(error)
                }
                if !viewModel.history.isEmpty {
                    historySection
                }
                if viewModel.history.isEmpty, viewModel.state == .idle {
                    samples
                }
            }
            .padding(20)
        }
        .softScrollEdges()
        .navigationTitle("Podcasts")
        .task { await viewModel.loadHistory() }
        .onChange(of: viewModel.state) { _, state in
            if let podcast = state.value {
                fieldIsFocused = false
                onLoaded(podcast)
                viewModel.reset()
            }
        }
        .confirmationDialog("Clear recent addresses?", isPresented: $showingClearHistory) {
            Button("Clear", role: .destructive) {
                Task { await viewModel.clearHistory() }
            }
        }
    }

    // MARK: - Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a podcast")
                .font(.largeTitle.weight(.semibold))

            Text("Paste the address of any public podcast RSS feed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                // The placeholder is drawn manually: the built-in prompt
                // renders in link blue here, which reads as tappable. It is
                // hidden from VoiceOver — a raw URL is not a usable label, and
                // the field carries its own.
                ZStack(alignment: .leading) {
                    if viewModel.urlText.isEmpty {
                        Text(verbatim: "example.com/feed.xml")
                            .foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }

                    TextField("", text: $viewModel.urlText)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.primary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .focused($fieldIsFocused)
                        .onSubmit { submit() }
                        .accessibilityLabel("Podcast feed address")
                        .accessibilityHint("Enter the address of a public podcast RSS feed")
                        .accessibilityIdentifier("feed.urlField")
                }
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .glassCard(cornerRadius: 16)

                Button(action: submit) {
                    if viewModel.state.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.right")
                            .font(.body.weight(.semibold))
                    }
                }
                .frame(width: 48, height: 48)
                .glassCircle(tinted: true)
                .disabled(!viewModel.canSubmit)
                .accessibilityLabel("Load podcast")
                .accessibilityIdentifier("feed.submitButton")
            }
        }
    }

    private func submit() {
        guard viewModel.canSubmit else { return }
        Task { await viewModel.submit() }
    }

    // MARK: - Error

    private func errorBanner(_ error: AppError) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(error.errorDescription ?? "Something went wrong", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("state.errorTitle")

            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if error.isRetryable {
                Button("Try Again") { Task { await viewModel.retry() } }
                    .buttonStyle(.glass)
                    .padding(.top, 4)
                    .accessibilityIdentifier("state.retry")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 18)
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent")
                    .font(.headline)
                Spacer()
                Button("Clear") { showingClearHistory = true }
                    .font(.subheadline)
                    .accessibilityIdentifier("feed.clearHistory")
            }

            VStack(spacing: 8) {
                ForEach(viewModel.history) { item in
                    Button {
                        Task { await viewModel.select(item) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title ?? item.url.host() ?? item.url.absoluteString)
                                    .font(.body.weight(.medium))
                                    .lineLimit(1)
                                Text(Self.compactAddress(item.url))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .glassCard(cornerRadius: 16)
                    .accessibilityIdentifier("feed.historyRow")
                }
            }
            .accessibilityIdentifier("feed.historyList")
        }
    }

    /// A feed address short enough to read in a list row.
    ///
    /// The scheme is noise and the full path rarely fits, least of all in a
    /// split-view sidebar. VoiceOver still gets the whole address from the
    /// row's combined label.
    static func compactAddress(_ url: URL) -> String {
        let host = url.host() ?? url.absoluteString
        let path = url.path()
        return path.isEmpty || path == "/" ? host : host + path
    }

    // MARK: - Samples

    private static let sampleFeeds: [(name: String, url: String)] = [
        ("La Cotorrisa", "https://feeds.megaphone.fm/la-cotorrisa"),
        ("Instituto Claro", "https://anchor.fm/s/7a186bc/podcast/rss"),
        ("Geek Nights", "http://feeds.feedburner.com/GeekNights"),
    ]

    private var samples: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Try one of these")
                .font(.headline)

            ForEach(Self.sampleFeeds, id: \.url) { sample in
                Button {
                    viewModel.urlText = sample.url
                    submit()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .foregroundStyle(.tint)
                        Text(sample.name)
                            .font(.body.weight(.medium))
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .glassCard(cornerRadius: 16)
            }
        }
    }
}
