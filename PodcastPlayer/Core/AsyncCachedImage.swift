import SwiftUI

/// Artwork, served from the app's own cache.
///
/// Deliberately not `AsyncImage`: that uses URLCache, which the app bypasses so
/// its own cache policy and the Settings clear button actually mean something.
struct AsyncCachedImage: View {
    let url: URL?
    var cornerRadius: CGFloat = 12

    @Environment(\.imageLoader) private var loader
    @State private var data: Data?
    @State private var didFinish = false

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
        // Artwork is decorative; the surrounding row already carries the title.
        .accessibilityHidden(true)
        .task(id: url) { await load() }
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if !didFinish {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func load() async {
        data = nil
        didFinish = false
        guard let url, let loader else {
            didFinish = true
            return
        }
        data = await loader.image(for: url)
        didFinish = true
    }
}

// MARK: - Environment

private struct ImageLoaderKey: EnvironmentKey {
    static let defaultValue: (any ImageLoading)? = nil
}

extension EnvironmentValues {
    var imageLoader: (any ImageLoading)? {
        get { self[ImageLoaderKey.self] }
        set { self[ImageLoaderKey.self] = newValue }
    }
}
