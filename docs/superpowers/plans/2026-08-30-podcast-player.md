# Podcast Player Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native iOS podcast player that loads public RSS feeds, caches feeds and images, and plays episodes with full transport controls.

**Architecture:** MVVM over a thin domain layer. `Features` (View + `@Observable` ViewModel) and `Data` (network, parsing, persistence, audio) both depend inward on `Domain`, which holds value-type models plus the protocols that define every boundary. ViewModels expose a single `ViewState<T>` enum and never import a `Data` type, so every one is testable against a hand-written fake.

**Tech Stack:** Swift 6.2 (strict concurrency), SwiftUI with Liquid Glass, SwiftData, `URLSession`, `XMLParser`, `AVPlayer` + `MPNowPlayingInfoCenter`, Swift Testing, XCUITest. Zero third-party dependencies.

**Spec:** `CLAUDE.md` (the working agreement) and `Exercicio - Podcast.pdf` (the original brief).

## Global Constraints

- Deploy target **iOS 26.0**; Swift 6 language mode with strict concurrency.
- **Zero third-party dependencies.** First-party Apple frameworks only.
- `Domain/` imports nothing but `Foundation`. No `SwiftUI`, no `SwiftData`, no `AVFoundation`.
- ViewModels are `@MainActor @Observable`, depend only on `Domain` protocols, and expose one `ViewState<T>`.
- SwiftData `@Model` types and raw parser output never leave `Data/`. Map to `Domain` structs at the repository boundary.
- **No `try!`, no force-unwrap, no `fatalError`, no `as!` in app code.** Tests may force-unwrap fixtures.
- No network in tests. Inject a fake `HTTPClient`. Inject a clock; never call `Date()` inside code under test.
- Every task ends green: `xcodebuild -scheme PodcastPlayer -destination 'platform=iOS Simulator,name=iPhone 17' test` passes before the commit.
- Conventional Commits, one logical change per commit.
- Accessibility identifiers on anything a UI test queries. Never query localized display strings.

---

## File Structure

| Path | Responsibility |
|---|---|
| `PodcastPlayer/App/PodcastPlayerApp.swift` | `@main` entry, SwiftData container setup |
| `PodcastPlayer/App/AppEnvironment.swift` | Composition root; builds and holds every dependency |
| `PodcastPlayer/App/RootView.swift` | `TabView` + `.tabViewBottomAccessory` mini-player host |
| `PodcastPlayer/Domain/Podcast.swift` | `Podcast` value type |
| `PodcastPlayer/Domain/Episode.swift` | `Episode` value type |
| `PodcastPlayer/Domain/AppError.swift` | The one error type crossing layer boundaries |
| `PodcastPlayer/Domain/ViewState.swift` | Shared screen state enum |
| `PodcastPlayer/Domain/Protocols.swift` | `PodcastRepository`, `ImageLoading`, `AudioPlaying`, `FeedHistoryStore`, `CacheManaging`, `Clock` |
| `PodcastPlayer/Data/Network/HTTPClient.swift` | `URLSession` wrapper, conditional GET, error mapping |
| `PodcastPlayer/Data/Parsing/RSSFeedParser.swift` | `XMLParser` SAX delegate → `ParsedFeed` |
| `PodcastPlayer/Data/Parsing/DurationParser.swift` | `itunes:duration` in all three formats |
| `PodcastPlayer/Data/Parsing/HTMLStripper.swift` | HTML → display text |
| `PodcastPlayer/Data/Persistence/CachedFeed.swift` | SwiftData models + domain mappers |
| `PodcastPlayer/Data/Persistence/FeedCacheStore.swift` | SwiftData reads/writes, TTL, clearing |
| `PodcastPlayer/Data/Persistence/FeedHistoryStoreImpl.swift` | URL history |
| `PodcastPlayer/Data/Images/ImageCache.swift` | `NSCache` + disk, LRU, size reporting, clearing |
| `PodcastPlayer/Data/Repository/PodcastRepositoryImpl.swift` | Stale-while-revalidate orchestration |
| `PodcastPlayer/Data/Audio/AudioPlayerService.swift` | `AVPlayer`, queue, Now Playing, remote commands |
| `PodcastPlayer/Core/Formatters.swift` | Duration and date formatting |
| `PodcastPlayer/Core/StateView.swift` | Renders `ViewState` uniformly |
| `PodcastPlayer/Core/AsyncCachedImage.swift` | Cache-backed image view |
| `PodcastPlayer/Core/Glass/GlassStyles.swift` | Every Liquid Glass modifier the app uses |
| `PodcastPlayer/Features/FeedSource/*` | Screen 1 |
| `PodcastPlayer/Features/PodcastDetail/*` | Screen 2 |
| `PodcastPlayer/Features/Player/*` | Screen 3 + mini-player |
| `PodcastPlayer/Features/Settings/*` | Cache inspection and clearing |

---

### Task 1: Project scaffold

**Files:**
- Create: `PodcastPlayer.xcodeproj/project.pbxproj`, `PodcastPlayer.xcodeproj/xcshareddata/xcschemes/PodcastPlayer.xcscheme`
- Create: `PodcastPlayer/App/PodcastPlayerApp.swift`, `PodcastPlayer/Info.plist`
- Create: `PodcastPlayerTests/SmokeTests.swift`, `PodcastPlayerUITests/LaunchUITests.swift`
- Create: `.gitignore`, `README.md`

**Interfaces:**
- Consumes: nothing.
- Produces: three targets — `PodcastPlayer` (app), `PodcastPlayerTests` (unit), `PodcastPlayerUITests` (UI). All three use `PBXFileSystemSynchronizedRootGroup`, so **new files on disk are compiled automatically with no `pbxproj` edit.**

- [ ] **Step 1: Author the project, plist, and app entry point**

`Info.plist` must include `UIBackgroundModes` with `audio` — background playback depends on it and retrofitting it later is easy to forget.

- [ ] **Step 2: Write a smoke test that proves the test target is wired**

```swift
import Testing
@testable import PodcastPlayer

@Test func testTargetIsWired() {
    #expect(Bundle(for: BundleMarker.self).bundleIdentifier != nil)
}
```

- [ ] **Step 3: Build and test**

Run: `xcodebuild -scheme PodcastPlayer -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: BUILD SUCCEEDED, tests pass.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "chore: scaffold Xcode project with app, unit test, and UI test targets"
```

---

### Task 2: Domain layer

**Files:**
- Create: `PodcastPlayer/Domain/Podcast.swift`, `Episode.swift`, `AppError.swift`, `ViewState.swift`, `Protocols.swift`
- Test: `PodcastPlayerTests/Domain/AppErrorTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces — every later task codes against these exact signatures:

```swift
struct Podcast: Equatable, Sendable, Identifiable {
    var id: URL { feedURL }
    let feedURL: URL
    let title: String
    let description: String?
    let author: String?
    let imageURL: URL?
    let categories: [String]
    let episodes: [Episode]
}

struct Episode: Equatable, Sendable, Identifiable {
    let id: String            // guid, or enclosure URL as fallback
    let title: String
    let description: String?
    let audioURL: URL
    let duration: TimeInterval?
    let publishedAt: Date?
    let imageURL: URL?
}

enum AppError: Error, Equatable, LocalizedError {
    case invalidURL
    case offline
    case network(statusCode: Int?)
    case notFound
    case invalidFeed(reason: String)
    case noEpisodes
    case playbackFailed

    var errorDescription: String? { get }
    var recoverySuggestion: String? { get }
    var isRetryable: Bool { get }
}

enum ViewState<T: Equatable>: Equatable {
    case idle, loading, loaded(T), empty, failed(AppError)
}

protocol PodcastRepository: Sendable {
    func podcast(for url: URL, forceRefresh: Bool) async throws(AppError) -> Podcast
}

protocol ImageLoading: Sendable {
    func image(for url: URL) async -> Data?
}

@MainActor protocol AudioPlaying: AnyObject {
    var currentEpisode: Episode? { get }
    var isPlaying: Bool { get }
    var elapsed: TimeInterval { get }
    var duration: TimeInterval { get }
    var canGoNext: Bool { get }
    var canGoPrevious: Bool { get }

    func load(queue: [Episode], startingAt index: Int, podcast: Podcast)
    func play()
    func pause()
    func next()
    func previous()
    func seek(to time: TimeInterval)
}

protocol FeedHistoryStore: Sendable {
    func history() async -> [FeedHistoryItem]
    func record(url: URL, title: String?) async
    func clear() async
}

struct FeedHistoryItem: Equatable, Sendable, Identifiable {
    var id: URL { url }
    let url: URL
    let title: String?
    let lastAccessedAt: Date
}

protocol CacheManaging: Sendable {
    func statistics() async -> CacheStatistics
    func clearFeedCache() async
    func clearImageCache() async
}

struct CacheStatistics: Equatable, Sendable {
    let cachedFeedCount: Int
    let imageCacheBytes: Int64
}

protocol Clock: Sendable { var now: Date { get } }
struct SystemClock: Clock { var now: Date { Date() } }
struct FixedClock: Clock { let now: Date }
```

- [ ] **Step 1: Write the failing test**

```swift
@Test func retryableErrorsAreMarkedRetryable() {
    #expect(AppError.offline.isRetryable)
    #expect(AppError.network(statusCode: 500).isRetryable)
    #expect(!AppError.invalidURL.isRetryable)
    #expect(!AppError.invalidFeed(reason: "no channel").isRetryable)
}

@Test func everyErrorHasUserFacingCopy() {
    let all: [AppError] = [.invalidURL, .offline, .network(statusCode: nil),
                           .notFound, .invalidFeed(reason: "x"), .noEpisodes, .playbackFailed]
    for error in all {
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.recoverySuggestion?.isEmpty == false)
    }
}
```

- [ ] **Step 2: Run and confirm it fails to compile** (`AppError` does not exist yet).
- [ ] **Step 3: Implement the domain types exactly as specified above.**
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** — `feat: add domain models, error type, and boundary protocols`

---

### Task 3: Duration parsing

Split out from the feed parser because it is the single highest-risk piece of parsing in this brief and deserves its own test cycle.

**Files:**
- Create: `PodcastPlayer/Data/Parsing/DurationParser.swift`
- Test: `PodcastPlayerTests/Data/DurationParserTests.swift`

**Interfaces:**
- Produces: `enum DurationParser { static func parse(_ raw: String?) -> TimeInterval? }`

- [ ] **Step 1: Write the failing test**

```swift
@Test(arguments: [
    ("01:02:03", 3723.0),   // HH:MM:SS
    ("1:02:03",  3723.0),   // unpadded hours
    ("42:30",    2550.0),   // MM:SS
    ("07:05",     425.0),
    ("3600",     3600.0),   // raw seconds
    ("0",           0.0),
])
func parsesEveryDurationFormat(raw: String, expected: TimeInterval) {
    #expect(DurationParser.parse(raw) == expected)
}

@Test(arguments: ["", "  ", "abc", "1:2:3:4", "-30", nil as String?])
func returnsNilForUnparseableInput(raw: String?) {
    #expect(DurationParser.parse(raw) == nil)
}

@Test func trimsSurroundingWhitespace() {
    #expect(DurationParser.parse("  12:00\n") == 720)
}
```

- [ ] **Step 2: Run and confirm failure.**
- [ ] **Step 3: Implement** — trim, split on `:`, switch on component count (1 = seconds, 2 = MM:SS, 3 = HH:MM:SS), reject negatives and non-numeric parts, return `nil` rather than throwing.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** — `feat: parse itunes:duration in HH:MM:SS, MM:SS, and seconds formats`

---

### Task 4: HTML stripping

**Files:**
- Create: `PodcastPlayer/Data/Parsing/HTMLStripper.swift`
- Test: `PodcastPlayerTests/Data/HTMLStripperTests.swift`

**Interfaces:**
- Produces: `enum HTMLStripper { static func plainText(from html: String) -> String }`

- [ ] **Step 1: Write the failing test**

```swift
@Test func removesTagsAndKeepsText() {
    #expect(HTMLStripper.plainText(from: "<p>Hello <b>world</b></p>") == "Hello world")
}

@Test func preservesParagraphBreaks() {
    #expect(HTMLStripper.plainText(from: "<p>One</p><p>Two</p>") == "One\n\nTwo")
}

@Test func convertsLineBreakTags() {
    #expect(HTMLStripper.plainText(from: "A<br/>B") == "A\nB")
}

@Test func decodesCommonEntities() {
    #expect(HTMLStripper.plainText(from: "Tom &amp; Jerry &#39;s &quot;show&quot;") == "Tom & Jerry 's \"show\"")
}

@Test func collapsesExcessiveWhitespace() {
    #expect(HTMLStripper.plainText(from: "<p>A</p>\n\n\n\n<p>B</p>") == "A\n\nB")
}
```

Use a hand-rolled scanner, not `NSAttributedString(html:)` — the latter must run on the main thread and is far too slow to call per episode.

- [ ] **Step 2: Run and confirm failure.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** — `feat: strip HTML from feed descriptions for display`

---

### Task 5: RSS feed parser

**Files:**
- Create: `PodcastPlayer/Data/Parsing/RSSFeedParser.swift`
- Test: `PodcastPlayerTests/Data/RSSFeedParserTests.swift`
- Create fixtures: `PodcastPlayerTests/Fixtures/la-cotorrisa.xml`, `instituto-claro.xml`, `geek-nights.xml`, `malformed.xml`, `missing-optional-fields.xml`, `empty-channel.xml`

Download the three reference feeds once and check them in verbatim. **Tests never hit the network** — the checked-in copies are the contract.

**Interfaces:**
- Consumes: `DurationParser.parse`, `HTMLStripper.plainText`, `AppError`.
- Produces:

```swift
struct ParsedFeed: Equatable, Sendable {
    let title: String
    let description: String?
    let author: String?
    let imageURL: URL?
    let categories: [String]
    let items: [ParsedItem]
}

struct ParsedItem: Equatable, Sendable {
    let guid: String?
    let title: String
    let description: String?
    let audioURL: URL
    let duration: TimeInterval?
    let publishedAt: Date?
    let imageURL: URL?
}

struct RSSFeedParser: Sendable {
    func parse(_ data: Data) throws(AppError) -> ParsedFeed
}
```

- [ ] **Step 1: Write the failing tests**

```swift
private func fixture(_ name: String) throws -> Data {
    let url = Bundle(for: BundleMarker.self).url(forResource: name, withExtension: "xml")!
    return try Data(contentsOf: url)
}

@Test func parsesRealFeedChannelMetadata() throws {
    let feed = try RSSFeedParser().parse(try fixture("la-cotorrisa"))
    #expect(!feed.title.isEmpty)
    #expect(feed.imageURL != nil)
    #expect(!feed.items.isEmpty)
}

@Test(arguments: ["la-cotorrisa", "instituto-claro", "geek-nights"])
func everyReferenceFeedParsesWithPlayableEpisodes(name: String) throws {
    let feed = try RSSFeedParser().parse(try fixture(name))
    #expect(!feed.items.isEmpty)
    // audioURL is non-optional, so every returned item is playable by construction
    #expect(feed.items.allSatisfy { !$0.title.isEmpty })
}

@Test func missingOptionalFieldsDoNotThrow() throws {
    let feed = try RSSFeedParser().parse(try fixture("missing-optional-fields"))
    #expect(feed.author == nil)
    #expect(feed.items.first?.duration == nil)
    #expect(feed.items.first?.description == nil)
    #expect(!feed.items.isEmpty)   // still usable
}

@Test func itemsWithoutEnclosureAreSkippedNotFatal() throws {
    // missing-optional-fields.xml contains one item with no <enclosure>
    let feed = try RSSFeedParser().parse(try fixture("missing-optional-fields"))
    #expect(feed.items.allSatisfy { $0.audioURL.absoluteString.isEmpty == false })
}

@Test func malformedXMLThrowsInvalidFeed() throws {
    #expect(throws: AppError.self) {
        try RSSFeedParser().parse(try fixture("malformed"))
    }
}

@Test func channelWithNoItemsThrowsNoEpisodes() throws {
    #expect(throws: AppError.noEpisodes) {
        try RSSFeedParser().parse(try fixture("empty-channel"))
    }
}

@Test func fallsBackFromItunesImageToChannelImage() throws {
    let feed = try RSSFeedParser().parse(try fixture("missing-optional-fields"))
    #expect(feed.imageURL?.absoluteString.contains("channel-image") == true)
}

@Test func guidFallsBackToEnclosureURL() throws {
    let feed = try RSSFeedParser().parse(try fixture("missing-optional-fields"))
    let item = feed.items.first!
    #expect(item.guid == nil || !item.guid!.isEmpty)
}
```

- [ ] **Step 2: Run and confirm failure.**
- [ ] **Step 3: Implement the `XMLParserDelegate`**

Streaming SAX. Track the element path so `<title>` inside `<item>` is not confused with the channel's. Handle the `itunes:` namespace (`itunes:author`, `itunes:image` via its `href` attribute, `itunes:duration`, `itunes:summary`, `itunes:category` via its `text` attribute). Fallbacks: `itunes:image` → channel `<image><url>`; `itunes:summary` → `<description>`; `guid` → enclosure URL. Parse `pubDate` with RFC 822 first, then ISO 8601. **Skip items with no `<enclosure url>`** — they are not playable, and dropping one bad item beats failing the whole feed. Throw `.invalidFeed` if no channel parses, `.noEpisodes` if the channel is valid but yields zero playable items.

- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** — `feat: parse RSS 2.0 feeds with the iTunes podcast namespace`

---

### Task 6: HTTP client

**Files:**
- Create: `PodcastPlayer/Data/Network/HTTPClient.swift`
- Test: `PodcastPlayerTests/Data/HTTPClientTests.swift`

**Interfaces:**
- Produces:

```swift
struct ConditionalHeaders: Equatable, Sendable {
    let etag: String?
    let lastModified: String?
}

enum HTTPResponse: Equatable, Sendable {
    case notModified
    case data(Data, ConditionalHeaders)
}

protocol HTTPClient: Sendable {
    func get(_ url: URL, conditional: ConditionalHeaders?) async throws(AppError) -> HTTPResponse
}

struct URLSessionHTTPClient: HTTPClient { init(session: URLSession = .shared) }
```

Tests use a `URLProtocol` subclass registered on an ephemeral `URLSessionConfiguration` — this stays inside `URLSession` without touching the network.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func sendsConditionalHeadersWhenProvided() async throws {
    StubURLProtocol.handler = { request in
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"abc\"")
        #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == "Mon, 01 Jan 2024 00:00:00 GMT")
        return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
    }
    _ = try await makeClient().get(anyURL, conditional: .init(etag: "\"abc\"", lastModified: "Mon, 01 Jan 2024 00:00:00 GMT"))
}

@Test func mapsStatus304ToNotModified() async throws {
    StubURLProtocol.respond(status: 304)
    #expect(try await makeClient().get(anyURL, conditional: nil) == .notModified)
}

@Test func returnsDataAndValidatorsOn200() async throws {
    StubURLProtocol.respond(status: 200, body: Data("hi".utf8), headers: ["ETag": "\"v2\"", "Last-Modified": "Tue, 02 Jan 2024 00:00:00 GMT"])
    guard case let .data(body, headers) = try await makeClient().get(anyURL, conditional: nil) else {
        Issue.record("expected data"); return
    }
    #expect(body == Data("hi".utf8))
    #expect(headers.etag == "\"v2\"")
    #expect(headers.lastModified == "Tue, 02 Jan 2024 00:00:00 GMT")
}

@Test func maps404ToNotFound() async {
    StubURLProtocol.respond(status: 404)
    await #expect(throws: AppError.notFound) { try await makeClient().get(anyURL, conditional: nil) }
}

@Test func maps500ToNetworkWithStatusCode() async {
    StubURLProtocol.respond(status: 500)
    await #expect(throws: AppError.network(statusCode: 500)) { try await makeClient().get(anyURL, conditional: nil) }
}

@Test func mapsNotConnectedToOffline() async {
    StubURLProtocol.fail(with: URLError(.notConnectedToInternet))
    await #expect(throws: AppError.offline) { try await makeClient().get(anyURL, conditional: nil) }
}
```

- [ ] **Step 2: Run and confirm failure.**
- [ ] **Step 3: Implement.** Map `URLError.notConnectedToInternet` / `.networkConnectionLost` / `.timedOut` → `.offline`; `404` → `.notFound`; other non-2xx → `.network(statusCode:)`. **No `URLError` escapes this file.**
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** — `feat: add URLSession HTTP client with conditional GET and error mapping`

---

### Task 7: SwiftData feed cache

**Files:**
- Create: `PodcastPlayer/Data/Persistence/CachedFeed.swift`, `PodcastPlayer/Data/Persistence/FeedCacheStore.swift`
- Test: `PodcastPlayerTests/Data/FeedCacheStoreTests.swift`

**Interfaces:**
- Consumes: `Podcast`, `Episode`, `Clock`.
- Produces:

```swift
@Model final class CachedFeed {
    @Attribute(.unique) var feedURL: URL
    var title: String
    var feedDescription: String?
    var author: String?
    var imageURL: URL?
    var categories: [String]
    var fetchedAt: Date
    var etag: String?
    var lastModified: String?
    @Relationship(deleteRule: .cascade) var episodes: [CachedEpisode]
}

@Model final class CachedEpisode {
    var guid: String
    var title: String
    var episodeDescription: String?
    var audioURL: URL
    var duration: TimeInterval?
    var publishedAt: Date?
    var imageURL: URL?
    var order: Int
}

struct CachedEntry: Equatable, Sendable {
    let podcast: Podcast
    let fetchedAt: Date
    let headers: ConditionalHeaders
}

@ModelActor actor FeedCacheStore {
    func entry(for url: URL) throws -> CachedEntry?
    func save(_ podcast: Podcast, headers: ConditionalHeaders, at date: Date) throws
    func touchFetchedAt(_ url: URL, to date: Date) throws
    func feedCount() throws -> Int
    func clear() throws
}
```

Tests build the container in memory: `ModelConfiguration(isStoredInMemoryOnly: true)`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func savesAndReadsBackAPodcast() async throws {
    let store = makeInMemoryStore()
    try await store.save(samplePodcast, headers: .init(etag: "\"v1\"", lastModified: nil), at: .distantPast)
    let entry = try await store.entry(for: samplePodcast.feedURL)
    #expect(entry?.podcast == samplePodcast)
    #expect(entry?.headers.etag == "\"v1\"")
}

@Test func preservesEpisodeOrder() async throws {
    let store = makeInMemoryStore()
    try await store.save(samplePodcast, headers: .init(etag: nil, lastModified: nil), at: .now)
    let entry = try await store.entry(for: samplePodcast.feedURL)
    #expect(entry?.podcast.episodes.map(\.id) == samplePodcast.episodes.map(\.id))
}

@Test func savingSameURLTwiceReplacesRatherThanDuplicates() async throws {
    let store = makeInMemoryStore()
    try await store.save(samplePodcast, headers: .init(etag: nil, lastModified: nil), at: .now)
    try await store.save(samplePodcast, headers: .init(etag: nil, lastModified: nil), at: .now)
    #expect(try await store.feedCount() == 1)
}

@Test func returnsNilForUnknownURL() async throws {
    #expect(try await makeInMemoryStore().entry(for: anyURL) == nil)
}

@Test func clearRemovesEverything() async throws {
    let store = makeInMemoryStore()
    try await store.save(samplePodcast, headers: .init(etag: nil, lastModified: nil), at: .now)
    try await store.clear()
    #expect(try await store.feedCount() == 0)
    #expect(try await store.entry(for: samplePodcast.feedURL) == nil)
}
```

- [ ] **Step 2: Run and confirm failure.**
- [ ] **Step 3: Implement models, mappers, and the actor.** Mapping lives here; **`CachedFeed` never escapes this file.**
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** — `feat: persist podcast feeds with SwiftData`

---

### Task 8: Image cache

**Files:**
- Create: `PodcastPlayer/Data/Images/ImageCache.swift`
- Test: `PodcastPlayerTests/Data/ImageCacheTests.swift`

**Interfaces:**
- Consumes: `ImageLoading`, `HTTPClient`.
- Produces:

```swift
actor ImageCache: ImageLoading {
    init(client: HTTPClient, directory: URL, maxDiskBytes: Int64 = 100 * 1024 * 1024)
    func image(for url: URL) async -> Data?
    func diskUsageBytes() -> Int64
    func clear()
}
```

Two tiers: `NSCache` in memory, SHA-256-keyed files on disk. Tests pass a temp directory and delete it in teardown.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func fetchesOnceThenServesFromCache() async {
    let client = FakeHTTPClient(result: .data(pngData, .init(etag: nil, lastModified: nil)))
    let cache = ImageCache(client: client, directory: tempDir)
    #expect(await cache.image(for: anyURL) == pngData)
    #expect(await cache.image(for: anyURL) == pngData)
    #expect(client.requestCount == 1)      // second read never hit the network
}

@Test func survivesMemoryCacheLossByReadingFromDisk() async {
    let client = FakeHTTPClient(result: .data(pngData, .init(etag: nil, lastModified: nil)))
    _ = await ImageCache(client: client, directory: tempDir).image(for: anyURL)
    let freshInstance = ImageCache(client: client, directory: tempDir)   // empty memory tier
    #expect(await freshInstance.image(for: anyURL) == pngData)
    #expect(client.requestCount == 1)
}

@Test func returnsNilOnFailureWithoutThrowing() async {
    let cache = ImageCache(client: FakeHTTPClient(error: .offline), directory: tempDir)
    #expect(await cache.image(for: anyURL) == nil)   // a missing image is never an error state
}

@Test func reportsDiskUsage() async {
    let cache = ImageCache(client: FakeHTTPClient(result: .data(pngData, .init(etag: nil, lastModified: nil))), directory: tempDir)
    #expect(await cache.diskUsageBytes() == 0)
    _ = await cache.image(for: anyURL)
    #expect(await cache.diskUsageBytes() > 0)
}

@Test func clearEmptiesBothTiers() async {
    let client = FakeHTTPClient(result: .data(pngData, .init(etag: nil, lastModified: nil)))
    let cache = ImageCache(client: client, directory: tempDir)
    _ = await cache.image(for: anyURL)
    await cache.clear()
    #expect(await cache.diskUsageBytes() == 0)
    _ = await cache.image(for: anyURL)
    #expect(client.requestCount == 2)   // proves the memory tier was cleared too
}

@Test func evictsOldestFilesWhenOverTheSizeCap() async {
    let cache = ImageCache(client: FakeHTTPClient(result: .data(pngData, .init(etag: nil, lastModified: nil))),
                           directory: tempDir, maxDiskBytes: Int64(pngData.count * 2))
    for i in 0..<5 { _ = await cache.image(for: URL(string: "https://x.test/\(i).png")!) }
    #expect(await cache.diskUsageBytes() <= Int64(pngData.count * 2))
}
```

- [ ] **Step 2: Run and confirm failure.**
- [ ] **Step 3: Implement.** Deduplicate concurrent requests for the same URL by holding in-flight `Task`s in a dictionary — otherwise a grid of episodes with the same artwork fires N identical downloads. Evict by oldest access date when over the cap.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** — `feat: add two-tier image cache with LRU eviction and clearing`

---

### Task 9: Podcast repository

The composition point: cache, network, and parser become one stale-while-revalidate policy.

**Files:**
- Create: `PodcastPlayer/Data/Repository/PodcastRepositoryImpl.swift`
- Test: `PodcastPlayerTests/Data/PodcastRepositoryTests.swift`

**Interfaces:**
- Consumes: `HTTPClient`, `RSSFeedParser`, `FeedCacheStore`, `Clock`, `AppError`.
- Produces: `struct PodcastRepositoryImpl: PodcastRepository, CacheManaging` with
  `init(client: HTTPClient, parser: RSSFeedParser, cache: FeedCacheStore, images: ImageCache, clock: Clock, ttl: TimeInterval = 3600)`

- [ ] **Step 1: Write the failing tests**

```swift
@Test func freshCacheIsServedWithoutAnyNetworkCall() async throws {
    let client = FakeHTTPClient(result: .data(feedXML, .init(etag: nil, lastModified: nil)))
    let sut = makeSUT(client: client, clock: FixedClock(now: t0), ttl: 3600)
    try await sut.cache.save(samplePodcast, headers: .init(etag: nil, lastModified: nil), at: t0)
    _ = try await sut.repository.podcast(for: feedURL, forceRefresh: false)
    #expect(client.requestCount == 0)
}

@Test func expiredCacheTriggersConditionalRevalidation() async throws {
    let client = FakeHTTPClient(result: .notModified)
    let sut = makeSUT(client: client, clock: FixedClock(now: t0.addingTimeInterval(7200)), ttl: 3600)
    try await sut.cache.save(samplePodcast, headers: .init(etag: "\"v1\"", lastModified: nil), at: t0)
    let podcast = try await sut.repository.podcast(for: feedURL, forceRefresh: false)
    #expect(client.lastConditional?.etag == "\"v1\"")
    #expect(podcast == samplePodcast)          // 304 keeps the cached copy
}

@Test func notModifiedResponseRefreshesTheTimestamp() async throws {
    let now = t0.addingTimeInterval(7200)
    let sut = makeSUT(client: FakeHTTPClient(result: .notModified), clock: FixedClock(now: now), ttl: 3600)
    try await sut.cache.save(samplePodcast, headers: .init(etag: "\"v1\"", lastModified: nil), at: t0)
    _ = try await sut.repository.podcast(for: feedURL, forceRefresh: false)
    #expect(try await sut.cache.entry(for: feedURL)?.fetchedAt == now)
}

@Test func changedFeedReplacesTheCache() async throws {
    let sut = makeSUT(client: FakeHTTPClient(result: .data(updatedFeedXML, .init(etag: "\"v2\"", lastModified: nil))),
                      clock: FixedClock(now: t0.addingTimeInterval(7200)), ttl: 3600)
    try await sut.cache.save(samplePodcast, headers: .init(etag: "\"v1\"", lastModified: nil), at: t0)
    let podcast = try await sut.repository.podcast(for: feedURL, forceRefresh: false)
    #expect(podcast.episodes.count != samplePodcast.episodes.count)
    #expect(try await sut.cache.entry(for: feedURL)?.headers.etag == "\"v2\"")
}

@Test func offlineWithCacheServesCacheInsteadOfFailing() async throws {
    let sut = makeSUT(client: FakeHTTPClient(error: .offline),
                      clock: FixedClock(now: t0.addingTimeInterval(7200)), ttl: 3600)
    try await sut.cache.save(samplePodcast, headers: .init(etag: nil, lastModified: nil), at: t0)
    #expect(try await sut.repository.podcast(for: feedURL, forceRefresh: false) == samplePodcast)
}

@Test func offlineWithoutCachePropagatesTheError() async {
    let sut = makeSUT(client: FakeHTTPClient(error: .offline), clock: FixedClock(now: t0), ttl: 3600)
    await #expect(throws: AppError.offline) {
        try await sut.repository.podcast(for: feedURL, forceRefresh: false)
    }
}

@Test func forceRefreshBypassesAFreshCache() async throws {
    let client = FakeHTTPClient(result: .data(feedXML, .init(etag: nil, lastModified: nil)))
    let sut = makeSUT(client: client, clock: FixedClock(now: t0), ttl: 3600)
    try await sut.cache.save(samplePodcast, headers: .init(etag: nil, lastModified: nil), at: t0)
    _ = try await sut.repository.podcast(for: feedURL, forceRefresh: true)
    #expect(client.requestCount == 1)
}

@Test func statisticsReportCachedFeedCount() async throws {
    let sut = makeSUT(client: FakeHTTPClient(result: .notModified), clock: FixedClock(now: t0), ttl: 3600)
    try await sut.cache.save(samplePodcast, headers: .init(etag: nil, lastModified: nil), at: t0)
    #expect(await sut.repository.statistics().cachedFeedCount == 1)
}
```

- [ ] **Step 2: Run and confirm failure.**
- [ ] **Step 3: Implement the policy** exactly as the tests describe: fresh cache → return it; stale or forced → conditional GET; `304` → touch timestamp, return cache; `200` → parse, save, return; error with a cache present → return cache; error with no cache → throw.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** — `feat: add stale-while-revalidate podcast repository`

---

### Task 10: Feed URL history

**Files:**
- Create: `PodcastPlayer/Data/Persistence/FeedHistoryStoreImpl.swift`
- Test: `PodcastPlayerTests/Data/FeedHistoryStoreTests.swift`

**Interfaces:**
- Consumes: `FeedHistoryStore`, `FeedHistoryItem`, `Clock`.
- Produces: `@ModelActor actor FeedHistoryStoreImpl: FeedHistoryStore` plus `@Model final class FeedHistoryEntry`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func recordsAndReturnsAURL() async {
    let store = makeInMemoryHistory(clock: FixedClock(now: t0))
    await store.record(url: feedURL, title: "Show")
    #expect(await store.history().map(\.url) == [feedURL])
}

@Test func returnsMostRecentlyAccessedFirst() async {
    let store = makeInMemoryHistory(clock: AdvancingClock(start: t0))
    await store.record(url: urlA, title: nil)
    await store.record(url: urlB, title: nil)
    #expect(await store.history().map(\.url) == [urlB, urlA])
}

@Test func rerecordingMovesAURLToTheTopWithoutDuplicating() async {
    let store = makeInMemoryHistory(clock: AdvancingClock(start: t0))
    await store.record(url: urlA, title: nil)
    await store.record(url: urlB, title: nil)
    await store.record(url: urlA, title: "Now titled")
    #expect(await store.history().map(\.url) == [urlA, urlB])
    #expect(await store.history().first?.title == "Now titled")
}

@Test func clearEmptiesHistory() async {
    let store = makeInMemoryHistory(clock: FixedClock(now: t0))
    await store.record(url: feedURL, title: nil)
    await store.clear()
    #expect(await store.history().isEmpty)
}
```

- [ ] **Step 2: Run and confirm failure.**
- [ ] **Step 3: Implement.** Upsert on unique `url`; sort by `lastAccessedAt` descending; cap at 20 entries.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** — `feat: persist recently used feed URLs`

---

### Task 11: Audio player service

**Files:**
- Create: `PodcastPlayer/Data/Audio/AudioPlayerService.swift`, `PodcastPlayer/Data/Audio/AVPlayerEngine.swift`
- Test: `PodcastPlayerTests/Data/AudioPlayerServiceTests.swift`

Queue logic is separated from `AVPlayer` behind a `PlaybackEngine` protocol so the queue — the part with real branching — is testable without audio hardware.

**Interfaces:**
- Consumes: `AudioPlaying`, `Episode`, `Podcast`.
- Produces:

```swift
@MainActor protocol PlaybackEngine: AnyObject {
    var onProgress: ((TimeInterval, TimeInterval) -> Void)? { get set }
    var onFinish: (() -> Void)? { get set }
    func replaceItem(url: URL)
    func play()
    func pause()
    func seek(to time: TimeInterval)
}

@MainActor @Observable final class AudioPlayerService: AudioPlaying {
    init(engine: PlaybackEngine, nowPlaying: NowPlayingPublishing)
}

@MainActor final class AVPlayerEngine: PlaybackEngine { init() }
```

- [ ] **Step 1: Write the failing tests**

```swift
@Test func loadingAQueueSelectsTheStartingEpisode() {
    let sut = makeSUT()
    sut.player.load(queue: threeEpisodes, startingAt: 1, podcast: samplePodcast)
    #expect(sut.player.currentEpisode == threeEpisodes[1])
    #expect(sut.engine.replacedURLs == [threeEpisodes[1].audioURL])
}

@Test func nextAdvancesThroughTheQueue() {
    let sut = makeSUT()
    sut.player.load(queue: threeEpisodes, startingAt: 0, podcast: samplePodcast)
    sut.player.next()
    #expect(sut.player.currentEpisode == threeEpisodes[1])
}

@Test func nextOnTheLastEpisodeStopsAndDoesNotWrap() {
    let sut = makeSUT()
    sut.player.load(queue: threeEpisodes, startingAt: 2, podcast: samplePodcast)
    sut.player.next()
    #expect(sut.player.currentEpisode == threeEpisodes[2])
    #expect(!sut.player.isPlaying)
    #expect(!sut.player.canGoNext)
}

@Test func previousRestartsWhenAlreadyOnTheFirstEpisode() {
    let sut = makeSUT()
    sut.player.load(queue: threeEpisodes, startingAt: 0, podcast: samplePodcast)
    sut.player.previous()
    #expect(sut.player.currentEpisode == threeEpisodes[0])
    #expect(sut.engine.seekTimes.last == 0)
    #expect(!sut.player.canGoPrevious)
}

@Test func previousGoesBackFromTheMiddle() {
    let sut = makeSUT()
    sut.player.load(queue: threeEpisodes, startingAt: 1, podcast: samplePodcast)
    sut.player.previous()
    #expect(sut.player.currentEpisode == threeEpisodes[0])
}

@Test func finishingAnEpisodeAutoAdvances() {
    let sut = makeSUT()
    sut.player.load(queue: threeEpisodes, startingAt: 0, podcast: samplePodcast)
    sut.engine.simulateFinish()
    #expect(sut.player.currentEpisode == threeEpisodes[1])
}

@Test func playAndPauseTrackIsPlaying() {
    let sut = makeSUT()
    sut.player.load(queue: threeEpisodes, startingAt: 0, podcast: samplePodcast)
    sut.player.play()
    #expect(sut.player.isPlaying)
    sut.player.pause()
    #expect(!sut.player.isPlaying)
}

@Test func progressCallbacksUpdateElapsedAndDuration() {
    let sut = makeSUT()
    sut.player.load(queue: threeEpisodes, startingAt: 0, podcast: samplePodcast)
    sut.engine.simulateProgress(elapsed: 30, duration: 600)
    #expect(sut.player.elapsed == 30)
    #expect(sut.player.duration == 600)
}

@Test func loadingAQueuePublishesNowPlayingMetadata() {
    let sut = makeSUT()
    sut.player.load(queue: threeEpisodes, startingAt: 0, podcast: samplePodcast)
    #expect(sut.nowPlaying.lastTitle == threeEpisodes[0].title)
    #expect(sut.nowPlaying.lastArtist == samplePodcast.title)
}
```

- [ ] **Step 2: Run and confirm failure.**
- [ ] **Step 3: Implement `AudioPlayerService`** against `FakePlaybackEngine`, then write `AVPlayerEngine` as the thin real adapter (`addPeriodicTimeObserver` for progress, `AVPlayerItemDidPlayToEndTime` for finish, observer token removed on `deinit`).
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** — `feat: add audio player service with queue navigation`

---

### Task 12: Background audio and remote controls

**Files:**
- Create: `PodcastPlayer/Data/Audio/NowPlayingPublisher.swift`, `PodcastPlayer/Data/Audio/AudioSessionController.swift`
- Modify: `PodcastPlayer/Info.plist` (confirm `UIBackgroundModes: [audio]`)
- Test: `PodcastPlayerTests/Data/NowPlayingPublisherTests.swift`

**Interfaces:**
- Produces:

```swift
@MainActor protocol NowPlayingPublishing: AnyObject {
    func publish(episode: Episode, podcast: Podcast, artwork: Data?)
    func updatePlayback(elapsed: TimeInterval, duration: TimeInterval, isPlaying: Bool)
    func clear()
}

@MainActor final class NowPlayingPublisher: NowPlayingPublishing { init() }

@MainActor final class AudioSessionController {
    init(player: AudioPlaying)
    func activate() throws
}
```

- [ ] **Step 1: Write the failing test**

```swift
@Test func publishesTitleArtistAndDurationToNowPlayingCenter() {
    NowPlayingPublisher().publish(episode: threeEpisodes[0], podcast: samplePodcast, artwork: nil)
    let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
    #expect(info?[MPMediaItemPropertyTitle] as? String == threeEpisodes[0].title)
    #expect(info?[MPMediaItemPropertyArtist] as? String == samplePodcast.title)
}

@Test func clearRemovesNowPlayingInfo() {
    let sut = NowPlayingPublisher()
    sut.publish(episode: threeEpisodes[0], podcast: samplePodcast, artwork: nil)
    sut.clear()
    #expect(MPNowPlayingInfoCenter.default().nowPlayingInfo == nil)
}
```

- [ ] **Step 2: Run and confirm failure.**
- [ ] **Step 3: Implement.** `AudioSessionController` sets category `.playback` mode `.spokenAudio`, wires `MPRemoteCommandCenter` (play, pause, next, previous, `changePlaybackPosition`), and observes `AVAudioSession.interruptionNotification` — pause on `.began`, resume on `.ended` **only** when the options contain `.shouldResume` — plus `routeChangeNotification` to pause on `.oldDeviceUnavailable`.
- [ ] **Step 4: Run the tests, then verify manually** — play an episode, lock the device, confirm audio continues and lock-screen controls work.
- [ ] **Step 5: Commit** — `feat: support background playback with lock screen controls`

---

### Task 13: Core UI components

**Files:**
- Create: `PodcastPlayer/Core/Formatters.swift`, `StateView.swift`, `AsyncCachedImage.swift`, `Glass/GlassStyles.swift`
- Test: `PodcastPlayerTests/Core/FormattersTests.swift`

**Interfaces:**
- Produces:

```swift
enum Formatters {
    static func duration(_ seconds: TimeInterval?) -> String     // "1h 2m", "42m", "—"
    static func timecode(_ seconds: TimeInterval) -> String      // "01:02:03" / "42:30"
    static func relativeDate(_ date: Date?, now: Date) -> String
    static func byteCount(_ bytes: Int64) -> String
}

struct StateView<T: Equatable, Content: View>: View {
    init(state: ViewState<T>, retry: (() -> Void)?, @ViewBuilder content: @escaping (T) -> Content)
}

struct AsyncCachedImage: View {
    init(url: URL?, cornerRadius: CGFloat = 12)
}

extension View {
    func glassCard() -> some View
    func glassTransport() -> some View
    func glassHeaderBackground() -> some View
}
```

**All Liquid Glass API usage is confined to `Glass/GlassStyles.swift`** — this is what makes the deploy-target walk-back documented in `CLAUDE.md` a one-file change. No feature file calls `.glassEffect` directly.

- [ ] **Step 1: Write the failing tests**

```swift
@Test(arguments: [(nil as TimeInterval?, "—"), (0, "0m"), (90, "1m"), (2550, "42m"), (3723, "1h 2m")])
func formatsDurationsForDisplay(input: TimeInterval?, expected: String) {
    #expect(Formatters.duration(input) == expected)
}

@Test(arguments: [(0.0, "00:00"), (2550.0, "42:30"), (3723.0, "01:02:03")])
func formatsTimecodes(input: TimeInterval, expected: String) {
    #expect(Formatters.timecode(input) == expected)
}

@Test func formatsByteCounts() {
    #expect(Formatters.byteCount(0) == "Zero KB")
    #expect(Formatters.byteCount(5 * 1024 * 1024).contains("MB"))
}
```

- [ ] **Step 2: Run and confirm failure.**
- [ ] **Step 3: Implement formatters, then the views.** `StateView` renders: `.idle`/`.loading` → `ProgressView`; `.empty` → `ContentUnavailableView`; `.failed` → `ContentUnavailableView` with `errorDescription`, `recoverySuggestion`, and a Retry button shown only when `error.isRetryable`; `.loaded` → the content builder.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** — `feat: add shared state view, cached image view, and glass styles`

---

### Task 14: Feed Source screen (Screen 1)

**Files:**
- Create: `PodcastPlayer/Features/FeedSource/FeedSourceViewModel.swift`, `FeedSourceView.swift`
- Test: `PodcastPlayerTests/Features/FeedSourceViewModelTests.swift`

**Interfaces:**
- Consumes: `PodcastRepository`, `FeedHistoryStore`, `ViewState`, `AppError`.
- Produces:

```swift
@MainActor @Observable final class FeedSourceViewModel {
    var urlText: String
    private(set) var state: ViewState<Podcast>
    private(set) var history: [FeedHistoryItem]

    init(repository: PodcastRepository, history: FeedHistoryStore)
    func loadHistory() async
    func submit() async
    func select(_ item: FeedHistoryItem) async
    func clearHistory() async
    func retry() async
}
```

Accessibility identifiers: `feed.urlField`, `feed.submitButton`, `feed.historyList`, `feed.historyRow.<url>`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func rejectsAnEmptyURLWithoutCallingTheRepository() async {
    let repo = FakeRepository()
    let sut = FeedSourceViewModel(repository: repo, history: FakeHistory())
    sut.urlText = "   "
    await sut.submit()
    #expect(sut.state == .failed(.invalidURL))
    #expect(repo.callCount == 0)
}

@Test func rejectsAMalformedURL() async {
    let sut = FeedSourceViewModel(repository: FakeRepository(), history: FakeHistory())
    sut.urlText = "not a url"
    await sut.submit()
    #expect(sut.state == .failed(.invalidURL))
}

@Test func acceptsAURLWithoutASchemeByAssumingHTTPS() async {
    let repo = FakeRepository(result: .success(samplePodcast))
    let sut = FeedSourceViewModel(repository: repo, history: FakeHistory())
    sut.urlText = "feeds.megaphone.fm/la-cotorrisa"
    await sut.submit()
    #expect(repo.lastURL?.scheme == "https")
}

@Test func successMovesToLoadedAndRecordsHistory() async {
    let history = FakeHistory()
    let sut = FeedSourceViewModel(repository: FakeRepository(result: .success(samplePodcast)), history: history)
    sut.urlText = feedURL.absoluteString
    await sut.submit()
    #expect(sut.state == .loaded(samplePodcast))
    #expect(history.recorded.map(\.0) == [feedURL])
    #expect(history.recorded.first?.1 == samplePodcast.title)
}

@Test func failureSurfacesTheDomainError() async {
    let sut = FeedSourceViewModel(repository: FakeRepository(result: .failure(.notFound)), history: FakeHistory())
    sut.urlText = feedURL.absoluteString
    await sut.submit()
    #expect(sut.state == .failed(.notFound))
}

@Test func retryAfterAFailureCanSucceed() async {
    let repo = FakeRepository(results: [.failure(.offline), .success(samplePodcast)])
    let sut = FeedSourceViewModel(repository: repo, history: FakeHistory())
    sut.urlText = feedURL.absoluteString
    await sut.submit()
    #expect(sut.state == .failed(.offline))
    await sut.retry()
    #expect(sut.state == .loaded(samplePodcast))
}

@Test func aFailedLoadIsNotRecordedInHistory() async {
    let history = FakeHistory()
    let sut = FeedSourceViewModel(repository: FakeRepository(result: .failure(.notFound)), history: history)
    sut.urlText = feedURL.absoluteString
    await sut.submit()
    #expect(history.recorded.isEmpty)
}

@Test func selectingAHistoryItemLoadsIt() async {
    let repo = FakeRepository(result: .success(samplePodcast))
    let sut = FeedSourceViewModel(repository: repo, history: FakeHistory())
    await sut.select(FeedHistoryItem(url: feedURL, title: "Show", lastAccessedAt: t0))
    #expect(repo.lastURL == feedURL)
    #expect(sut.state == .loaded(samplePodcast))
}
```

- [ ] **Step 2: Run and confirm failure.**
- [ ] **Step 3: Implement the ViewModel, then the View.** URL normalization (trim, prepend `https://` when no scheme, require a host) lives in the ViewModel — that is exactly the kind of decision a View must not make.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** — `feat: add feed source screen with URL validation and history`

---

### Task 15: Podcast Detail screen (Screen 2)

**Files:**
- Create: `PodcastPlayer/Features/PodcastDetail/PodcastDetailViewModel.swift`, `PodcastDetailView.swift`, `EpisodeRow.swift`
- Test: `PodcastPlayerTests/Features/PodcastDetailViewModelTests.swift`

Every element the brief lists must be on screen: **title, image, description, author, duration, genre.**

**Interfaces:**
- Consumes: `PodcastRepository`, `AudioPlaying`.
- Produces:

```swift
@MainActor @Observable final class PodcastDetailViewModel {
    private(set) var state: ViewState<Podcast>
    init(feedURL: URL, repository: PodcastRepository, player: AudioPlaying)
    func load() async
    func refresh() async        // pull-to-refresh; forceRefresh: true
    func retry() async
    func play(_ episode: Episode)
}
```

Accessibility identifiers: `detail.title`, `detail.author`, `detail.genre`, `detail.episodeList`, `detail.episodeRow.<index>`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func loadMovesIdleToLoadingToLoaded() async {
    let sut = PodcastDetailViewModel(feedURL: feedURL, repository: FakeRepository(result: .success(samplePodcast)), player: FakePlayer())
    #expect(sut.state == .idle)
    await sut.load()
    #expect(sut.state == .loaded(samplePodcast))
}

@Test func aPodcastWithNoEpisodesIsEmptyNotLoaded() async {
    let bare = Podcast(feedURL: feedURL, title: "T", description: nil, author: nil, imageURL: nil, categories: [], episodes: [])
    let sut = PodcastDetailViewModel(feedURL: feedURL, repository: FakeRepository(result: .success(bare)), player: FakePlayer())
    await sut.load()
    #expect(sut.state == .empty)
}

@Test func failureIsSurfacedAndRetryable() async {
    let repo = FakeRepository(results: [.failure(.network(statusCode: 500)), .success(samplePodcast)])
    let sut = PodcastDetailViewModel(feedURL: feedURL, repository: repo, player: FakePlayer())
    await sut.load()
    #expect(sut.state == .failed(.network(statusCode: 500)))
    await sut.retry()
    #expect(sut.state == .loaded(samplePodcast))
}

@Test func refreshForcesANetworkRevalidation() async {
    let repo = FakeRepository(result: .success(samplePodcast))
    let sut = PodcastDetailViewModel(feedURL: feedURL, repository: repo, player: FakePlayer())
    await sut.refresh()
    #expect(repo.lastForceRefresh == true)
}

@Test func playingAnEpisodeLoadsTheWholeListAsTheQueue() async {
    let player = FakePlayer()
    let sut = PodcastDetailViewModel(feedURL: feedURL, repository: FakeRepository(result: .success(samplePodcast)), player: player)
    await sut.load()
    sut.play(samplePodcast.episodes[1])
    #expect(player.loadedQueue == samplePodcast.episodes)   // next/previous must work from here
    #expect(player.startIndex == 1)
    #expect(player.playCallCount == 1)
}

@Test func playingIsIgnoredBeforeTheFeedLoads() {
    let player = FakePlayer()
    let sut = PodcastDetailViewModel(feedURL: feedURL, repository: FakeRepository(), player: player)
    sut.play(samplePodcast.episodes[0])
    #expect(player.loadedQueue == nil)
}
```

- [ ] **Step 2: Run and confirm failure.**
- [ ] **Step 3: Implement.** The header uses `glassHeaderBackground()` with `.backgroundExtensionEffect()`; the episode list is an adaptive grid so it becomes multi-column at regular width.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** — `feat: add podcast detail screen with playable episode list`

---

### Task 16: Player and mini-player (Screen 3)

**Files:**
- Create: `PodcastPlayer/Features/Player/PlayerViewModel.swift`, `PlayerView.swift`, `MiniPlayerView.swift`
- Test: `PodcastPlayerTests/Features/PlayerViewModelTests.swift`

**Interfaces:**
- Consumes: `AudioPlaying`, `Formatters`.
- Produces:

```swift
@MainActor @Observable final class PlayerViewModel {
    var scrubPosition: TimeInterval?      // non-nil only while the user drags
    private(set) var isScrubbing: Bool

    init(player: AudioPlaying)

    var episode: Episode? { get }
    var progress: Double { get }          // 0...1, safe when duration == 0
    var elapsedText: String { get }
    var remainingText: String { get }
    var canGoNext: Bool { get }
    var canGoPrevious: Bool { get }
    var isPlaying: Bool { get }

    func togglePlayPause()
    func next()
    func previous()
    func beginScrubbing()
    func scrub(to fraction: Double)
    func endScrubbing()
}
```

Accessibility identifiers: `player.playPause`, `player.next`, `player.previous`, `player.progress`, `player.title`, `mini.container`, `mini.title`, `mini.playPause`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func progressIsZeroWhenDurationIsUnknown() {
    let player = FakePlayer(); player.duration = 0; player.elapsed = 0
    #expect(PlayerViewModel(player: player).progress == 0)   // must not divide by zero
}

@Test func progressReflectsElapsedOverDuration() {
    let player = FakePlayer(); player.duration = 600; player.elapsed = 150
    #expect(PlayerViewModel(player: player).progress == 0.25)
}

@Test func togglePlayPauseFlipsBetweenPlayAndPause() {
    let player = FakePlayer(); player.isPlaying = false
    let sut = PlayerViewModel(player: player)
    sut.togglePlayPause()
    #expect(player.playCallCount == 1)
    player.isPlaying = true
    sut.togglePlayPause()
    #expect(player.pauseCallCount == 1)
}

@Test func scrubbingDoesNotSeekUntilTheDragEnds() {
    let player = FakePlayer(); player.duration = 600
    let sut = PlayerViewModel(player: player)
    sut.beginScrubbing()
    sut.scrub(to: 0.5)
    #expect(player.seekTimes.isEmpty)      // no seek storm while dragging
    #expect(sut.elapsedText == "05:00")    // but the label tracks the thumb
    sut.endScrubbing()
    #expect(player.seekTimes == [300])
}

@Test func remainingTimeCountsDown() {
    let player = FakePlayer(); player.duration = 600; player.elapsed = 150
    #expect(PlayerViewModel(player: player).remainingText == "-07:30")
}

@Test func transportButtonsDelegateToThePlayer() {
    let player = FakePlayer()
    let sut = PlayerViewModel(player: player)
    sut.next(); sut.previous()
    #expect(player.nextCallCount == 1)
    #expect(player.previousCallCount == 1)
}

@Test func transportAvailabilityMirrorsTheQueue() {
    let player = FakePlayer(); player.canGoNext = false; player.canGoPrevious = true
    let sut = PlayerViewModel(player: player)
    #expect(!sut.canGoNext)
    #expect(sut.canGoPrevious)
}
```

- [ ] **Step 2: Run and confirm failure.**
- [ ] **Step 3: Implement the ViewModel, then the views.**

`PlayerView` shows artwork, episode title, podcast title, author, a progress `Slider` with elapsed/remaining labels, and transport controls in a `GlassEffectContainer` using `glassTransport()`. `MiniPlayerView` shows artwork, title, and play/pause. Mount it via `.tabViewBottomAccessory` on the `TabView` in `RootView`, paired with `.tabBarMinimizeBehavior(.onScrollDown)`, and expand to `PlayerView` with a matched-geometry `.glassEffectID` transition.

The progress slider needs `accessibilityValue` announcing elapsed and remaining time.

- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** — `feat: add player screen and docked mini-player`

---

### Task 17: Settings and cache clearing

**Files:**
- Create: `PodcastPlayer/Features/Settings/SettingsViewModel.swift`, `SettingsView.swift`
- Test: `PodcastPlayerTests/Features/SettingsViewModelTests.swift`

The brief requires clear-cache options for **both** RSS and images. Each is confirmed before it runs.

**Interfaces:**
- Consumes: `CacheManaging`, `FeedHistoryStore`, `CacheStatistics`, `Formatters`.
- Produces:

```swift
@MainActor @Observable final class SettingsViewModel {
    private(set) var statistics: CacheStatistics
    var feedCacheText: String { get }        // "3 feeds"
    var imageCacheText: String { get }       // "12.4 MB"

    init(cache: CacheManaging, history: FeedHistoryStore)
    func refresh() async
    func clearFeedCache() async
    func clearImageCache() async
    func clearHistory() async
}
```

Accessibility identifiers: `settings.feedCacheValue`, `settings.imageCacheValue`, `settings.clearFeeds`, `settings.clearImages`, `settings.clearHistory`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func refreshLoadsStatistics() async {
    let cache = FakeCacheManager(stats: CacheStatistics(cachedFeedCount: 3, imageCacheBytes: 5_242_880))
    let sut = SettingsViewModel(cache: cache, history: FakeHistory())
    await sut.refresh()
    #expect(sut.statistics.cachedFeedCount == 3)
    #expect(sut.feedCacheText == "3 feeds")
    #expect(sut.imageCacheText.contains("MB"))
}

@Test func feedCacheTextIsSingularForOneFeed() async {
    let sut = SettingsViewModel(cache: FakeCacheManager(stats: .init(cachedFeedCount: 1, imageCacheBytes: 0)), history: FakeHistory())
    await sut.refresh()
    #expect(sut.feedCacheText == "1 feed")
}

@Test func clearingFeedCacheZeroesTheCountWithoutTouchingImages() async {
    let cache = FakeCacheManager(stats: .init(cachedFeedCount: 3, imageCacheBytes: 1024))
    let sut = SettingsViewModel(cache: cache, history: FakeHistory())
    await sut.refresh()
    await sut.clearFeedCache()
    #expect(cache.clearFeedCallCount == 1)
    #expect(cache.clearImageCallCount == 0)
    #expect(sut.statistics.cachedFeedCount == 0)
    #expect(sut.statistics.imageCacheBytes == 1024)
}

@Test func clearingImageCacheZeroesBytesWithoutTouchingFeeds() async {
    let cache = FakeCacheManager(stats: .init(cachedFeedCount: 3, imageCacheBytes: 1024))
    let sut = SettingsViewModel(cache: cache, history: FakeHistory())
    await sut.refresh()
    await sut.clearImageCache()
    #expect(sut.statistics.imageCacheBytes == 0)
    #expect(sut.statistics.cachedFeedCount == 3)
}

@Test func clearingHistoryDelegatesToTheHistoryStore() async {
    let history = FakeHistory()
    await SettingsViewModel(cache: FakeCacheManager(), history: history).clearHistory()
    #expect(history.clearCallCount == 1)
}
```

- [ ] **Step 2: Run and confirm failure.**
- [ ] **Step 3: Implement.** Each destructive row uses `.confirmationDialog` and `role: .destructive`; statistics refresh after every clear.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** — `feat: add settings screen with independent cache clearing`

---

### Task 18: Composition root and navigation

**Files:**
- Create: `PodcastPlayer/App/AppEnvironment.swift`, `PodcastPlayer/App/RootView.swift`
- Modify: `PodcastPlayer/App/PodcastPlayerApp.swift`
- Test: `PodcastPlayerTests/App/AppEnvironmentTests.swift`

**Interfaces:**
- Consumes: everything built so far.
- Produces:

```swift
@MainActor final class AppEnvironment {
    let repository: PodcastRepository & CacheManaging
    let history: FeedHistoryStore
    let images: ImageLoading
    let player: AudioPlayerService

    static func live() throws -> AppEnvironment
    static func preview() -> AppEnvironment          // in-memory, fixture-backed
    static func uiTesting() -> AppEnvironment        // used when launch args contain "-uiTesting"
}
```

This is the **only** place concrete types are named. Every other file sees protocols.

- [ ] **Step 1: Write the failing test**

```swift
@Test func liveEnvironmentWiresEveryDependency() throws {
    let env = try AppEnvironment.live()
    #expect(env.repository is PodcastRepositoryImpl)
}

@Test func uiTestingEnvironmentStartsWithNoCachedState() async {
    let env = AppEnvironment.uiTesting()
    #expect(await env.repository.statistics().cachedFeedCount == 0)
    #expect(await env.history.history().isEmpty)
}
```

- [ ] **Step 2: Run and confirm failure.**
- [ ] **Step 3: Implement.** `RootView` is a `TabView` (Browse / Settings) with the mini-player in `.tabViewBottomAccessory`, and a `NavigationSplitView`-vs-`NavigationStack` switch driven by `@Environment(\.horizontalSizeClass)`. `PodcastPlayerApp` builds the environment once and injects it; if `AppEnvironment.live()` throws (a corrupt store), it falls back to a fresh in-memory container and shows a non-blocking banner rather than crashing.
- [ ] **Step 4: Run the tests, then launch the app** and load a real feed end to end.
- [ ] **Step 5: Commit** — `feat: wire composition root and adaptive navigation`

---

### Task 19: UI smoke tests

**Files:**
- Create: `PodcastPlayerUITests/FeedFlowUITests.swift`, `PodcastPlayerUITests/CacheUITests.swift`

Launched with `-uiTesting` so `AppEnvironment.uiTesting()` serves fixture feeds from a stub client. **No network, no flake.**

- [ ] **Step 1: Write the failing tests**

```swift
@MainActor final class FeedFlowUITests: XCTestCase {
    func testLoadingAFeedShowsItsEpisodes() {
        let app = launch()
        app.textFields["feed.urlField"].tap()
        app.typeText("https://feeds.megaphone.fm/la-cotorrisa")
        app.buttons["feed.submitButton"].tap()
        XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["detail.episodeList"].exists)
    }

    func testPlayingAnEpisodeShowsTheMiniPlayerAndExpands() {
        let app = launchAtDetail()
        app.buttons["detail.episodeRow.0"].tap()
        XCTAssertTrue(app.otherElements["mini.container"].waitForExistence(timeout: 5))
        let title = app.staticTexts["mini.title"].label
        app.otherElements["mini.container"].tap()
        XCTAssertEqual(app.staticTexts["player.title"].label, title)
        XCTAssertTrue(app.buttons["player.playPause"].exists)
    }

    func testAnInvalidURLShowsARecoverableError() {
        let app = launch()
        app.textFields["feed.urlField"].tap()
        app.typeText("not a url")
        app.buttons["feed.submitButton"].tap()
        XCTAssertTrue(app.staticTexts["state.errorTitle"].waitForExistence(timeout: 3))
    }
}

@MainActor final class CacheUITests: XCTestCase {
    func testClearingImageCacheZeroesTheReportedSize() {
        let app = launchAtSettings()
        app.buttons["settings.clearImages"].tap()
        app.buttons["Clear"].tap()
        XCTAssertTrue(app.staticTexts["settings.imageCacheValue"].label.contains("Zero"))
    }
}
```

- [ ] **Step 2: Run and confirm failure.**
- [ ] **Step 3: Add the missing accessibility identifiers** to the views. Query identifiers only — never localized strings.
- [ ] **Step 4: Run the full suite.** Expected: PASS.
- [ ] **Step 5: Commit** — `test: add UI smoke tests for feed, playback, and cache flows`

---

### Task 20: Responsive layout and accessibility pass

**Files:**
- Modify: every file under `Features/`

- [ ] **Step 1: Audit at every size.** Run on iPhone 16e, iPhone 17 Pro Max, and iPad Pro in both orientations. Confirm the split view engages at regular width and the episode grid reflows.
- [ ] **Step 2: Audit Dynamic Type** at `AX5`. No clipped text, no fixed-height text containers. Transport controls stack vertically if they no longer fit.
- [ ] **Step 3: Audit VoiceOver.** Every icon-only button has a label; the progress slider announces elapsed and remaining; episode rows read as one element, not five fragments.
- [ ] **Step 4: Audit Reduce Transparency and Reduce Motion.** Glass surfaces must fall back to opaque; the mini-player expansion must not animate under Reduce Motion.
- [ ] **Step 5: Run the full suite, then commit** — `fix: support dynamic type, VoiceOver, and reduced transparency`

---

### Task 21: README and final verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Write the README** — what it is, screenshots of the three screens, architecture diagram and the reasoning behind it, how to build and run, how to run the tests, the sample feed URLs, and an **Assumptions & Trade-offs** section (iOS 26 for Liquid Glass, zero dependencies, 1-hour TTL, why the queue lives in the audio service).
- [ ] **Step 2: Run the full suite on a clean build.**

```bash
xcodebuild clean -scheme PodcastPlayer
xcodebuild -scheme PodcastPlayer -destination 'platform=iOS Simulator,name=iPhone 17' test
```

- [ ] **Step 3: Verify a clean clone builds** — `git clone` to a temp directory, open, build. This is the brief's first requirement and the easiest one to fail.
- [ ] **Step 4: Review the commit history** with `git log --oneline`. It should read as the build order. Squash any noise.
- [ ] **Step 5: Commit** — `docs: add README with architecture notes and setup instructions`

---

## Self-Review

**Spec coverage.** Screen 1 → Task 14 (URL field, action button, history). Screen 2 → Task 15 (title, image, description, author, duration, genre, play any episode). Screen 3 → Task 16 (progress bar, play/pause, next, previous, metadata). RSS cache → Tasks 7 and 9. Image cache → Task 8. Clear cache options → Task 17. MVVM → Tasks 14–18. Responsive → Tasks 18 and 20. Error handling → Tasks 2, 6, 9, and every ViewModel task. Commit structure → one commit per task, Conventional Commits. Apple podcast RSS spec → Tasks 3–5. Background audio and mini-player extras → Tasks 12 and 16.

**Type consistency.** `AppError`, `ViewState`, `Podcast`, `Episode`, `ConditionalHeaders`, `CacheStatistics`, and `FeedHistoryItem` are defined once in Task 2 or 6 and referenced with identical spelling thereafter. `PodcastRepository.podcast(for:forceRefresh:)`, `AudioPlaying.load(queue:startingAt:podcast:)`, and `CacheManaging.clearFeedCache()`/`clearImageCache()` keep the same signatures at every call site.

**Known gap, accepted:** playback position is not persisted across launches. The brief does not ask for it, and YAGNI applies. It is noted in the README as a deliberate trade-off.
