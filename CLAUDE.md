# CLAUDE.md

Working agreement for this repository. Read before touching code.

## What this is

A native iOS podcast player built from public RSS feeds, as specified in
`Exercicio - Podcast.pdf`. It is a technical assessment: **architecture, commit
structure, and error handling are graded alongside whether the app works.**
Treat "it runs" as the floor, never the goal.

Three required screens, plus one we add to satisfy the cache requirement:

1. **Feed Source** — text field for a podcast RSS URL, action button, history of
   previously used URLs.
2. **Podcast Detail** — artwork, title, description, author, genre, and the
   episode list with durations. Any episode is playable from here.
3. **Player** — episode metadata, progress bar, play/pause, next, previous.
4. **Settings** — cache inspection and clearing (the brief requires clear-cache
   options for both RSS and images).

Reference feeds (also checked in as test fixtures):

- `https://feeds.megaphone.fm/la-cotorrisa`
- `https://anchor.fm/s/7a186bc/podcast/rss`
- `http://feeds.feedburner.com/GeekNights`

Feeds must be parsed per the Apple Podcast requirements spec (RSS 2.0 + the
`itunes:` namespace).

## Stack

| | |
|---|---|
| Language | Swift 6, strict concurrency |
| UI | SwiftUI with the Liquid Glass design system |
| Pattern | MVVM |
| Deploy target | iOS 26 |
| Persistence | SwiftData (feeds, episodes, URL history) |
| Networking | `URLSession` — no third-party HTTP client |
| Audio | `AVPlayer` + `AVAudioSession` + `MPNowPlayingInfoCenter` |
| Images | Hand-rolled two-tier cache (`NSCache` + disk) |
| Tests | Swift Testing (`@Test` / `#expect`) + XCUITest |
| Dependencies | **None.** Everything is first-party Apple frameworks. |

### Why iOS 26

Liquid Glass (`.glassEffect`, `GlassEffectContainer`, `.tabViewBottomAccessory`)
is iOS 26+. Supporting iOS 17 would mean wrapping every glass surface in
`if #available` with a `.ultraThinMaterial` fallback — roughly doubling the UI
code for a take-home. If a reviewer must build on an older Xcode, the walk-back
is contained: lower the target and swap the `Glass/` modifiers in `Core/` for
their material equivalents. The rest of the app is unaffected, because no
feature code calls a glass API directly.

## Architecture

MVVM over a thin domain layer. Dependencies point inward: `Features` → `Domain`
← `Data`. **`Domain` imports nothing but `Foundation`.**

```
PodcastPlayer/
  App/          PodcastPlayerApp, AppEnvironment (DI composition root), RootView
  Features/
    FeedSource/     FeedSourceView + FeedSourceViewModel
    PodcastDetail/  PodcastDetailView + PodcastDetailViewModel
    Player/         PlayerView, MiniPlayerView + PlayerViewModel
    Settings/       SettingsView + SettingsViewModel
  Domain/       Podcast, Episode, AppError, ViewState
                Protocols: PodcastRepository, ImageLoading, AudioPlaying,
                           FeedHistoryStore, CacheManaging
  Data/         HTTPClient, RSSFeedParser, PodcastRepositoryImpl,
                SwiftData models + domain mappers, ImageCache,
                AudioPlayerService, FeedHistoryStoreImpl
  Core/         Formatters, Glass/ modifiers, AsyncCachedImage, StateView
  Resources/
PodcastPlayerTests/      Unit tests + Fixtures/*.xml
PodcastPlayerUITests/    Smoke flows
```

### Non-negotiable rules

- **Views hold no logic and no state beyond view-local UI state** (sheet
  presented, text field focus). No networking, no formatting, no branching on
  raw model data. If a View needs an `if`, ask whether the ViewModel should have
  decided it.
- **ViewModels are `@MainActor @Observable`**, expose exactly one
  `ViewState<T>` plus intent methods (`load()`, `retry()`, `select(_:)`), and
  depend **only on `Domain` protocols**. A ViewModel that imports a `Data` type
  is a bug — it means it cannot be tested with a fake.
- **`Data` types never leave the `Data` layer.** SwiftData `@Model` classes and
  raw parser output are mapped to `Domain` structs at the repository boundary.
  This is what keeps SwiftData from leaking into every ViewModel and what makes
  the persistence layer replaceable.
- **Dependencies are constructor-injected** from `AppEnvironment`. The only
  process-wide singleton is the audio session, because `AVAudioSession` is.
- **Domain models are value types.** `Podcast` and `Episode` are `struct`,
  `Sendable`, `Equatable`, `Identifiable`.
- **No `try!`, no force-unwrap, no `fatalError`, no `as!` in app code.** Tests
  may force-unwrap fixtures. Optionality in a feed is data, not a crash.

### One state enum, everywhere

```swift
enum ViewState<T: Equatable>: Equatable {
    case idle, loading, loaded(T), empty, failed(AppError)
}
```

Every screen renders it through the shared `StateView`, so loading spinners,
empty states, and error-with-retry look and behave identically app-wide. Adding
a screen means writing a ViewModel that populates this enum — not inventing a
fourth way to show a spinner.

### Data flow

```
View → ViewModel → PodcastRepository (protocol)
                 → { SwiftData cache | HTTPClient + RSSFeedParser }
                 → Domain models → ViewState → View
```

## Caching

Both caches are required by the brief, and both must be clearable independently.

### RSS — stale-while-revalidate

1. Cached feed renders **immediately** (no spinner on a warm cache).
2. A conditional `GET` revalidates in the background using the stored `ETag` /
   `Last-Modified`.
3. `304 Not Modified` → keep the cache, just bump `fetchedAt`.
4. `200` → reparse, replace, re-render.
5. TTL is 1 hour; past it, revalidation is forced before render on a cold start.

SwiftData models: `CachedFeed` (url, title, description, author, imageURL,
categories, fetchedAt, etag, lastModified), `CachedEpisode` (guid, title,
description, audioURL, duration, pubDate, order), `FeedHistoryEntry` (url,
title, lastAccessedAt).

### Images — two tiers

`NSCache<NSURL, UIImage>` in memory with a cost limit, backed by a disk store in
`Caches/Images/` keyed by the SHA-256 of the URL, with a size cap and LRU
eviction. Consumed only through `AsyncCachedImage`; never call the cache from a
View directly.

### Settings

Reports live feed count and on-disk image cache size, and offers three separate
destructive actions, each confirmed: **clear RSS cache**, **clear image cache**,
**clear URL history**. Clearing must not crash a screen that is currently
displaying cached content.

## RSS parsing

`XMLParser` (`SAX`), streaming, never loading a whole feed into a DOM.

- Handles the `itunes:` namespace: `itunes:author`, `itunes:image`,
  `itunes:duration`, `itunes:summary`, `itunes:category`, `itunes:explicit`.
- **Parses all three `itunes:duration` formats**: `HH:MM:SS`, `MM:SS`, and raw
  seconds. This is the single most common source of bugs here — it has
  dedicated tests.
- Falls back sanely: `itunes:image` → channel `image/url`; `itunes:summary` →
  `description`; missing `guid` → `enclosure` URL.
- Strips HTML from descriptions for display, preserving paragraph breaks.
- **Every optional field is genuinely optional.** A feed missing an author, an
  image, or a duration renders — it does not throw. Only a feed with no
  parseable channel or no episodes is an error (`.invalidFeed` / `.noEpisodes`).

## Error handling

A single domain error type, translated at the repository boundary:

```swift
enum AppError: Error, Equatable, LocalizedError {
    case invalidURL
    case offline
    case network(statusCode: Int?)
    case notFound
    case invalidFeed(reason: String)
    case noEpisodes
    case playbackFailed
}
```

- `URLError` and parse failures are mapped to `AppError` **in `Data`**. No
  `URLError` ever reaches a ViewModel.
- Every `AppError` has a user-facing `errorDescription` and a
  `recoverySuggestion`. No raw error dumps in the UI, ever.
- Errors that can be retried surface a **Retry** button wired to the
  ViewModel's `retry()`.
- **Offline with a cache hit is not an error.** Show the cached content with a
  non-blocking "Showing offline content" banner.
- URL validation happens before the network call: scheme, host, and a clear
  message for the common paste mistakes.

## Audio

`AudioPlayerService: AudioPlaying` wraps `AVPlayer` and owns the queue (the
episode list plus the current index), which is what makes next/previous
meaningful rather than per-screen state.

- `AVAudioSession` category `.playback` so audio continues when the app is
  backgrounded or the screen locks. `UIBackgroundModes: [audio]` in the plist.
- `MPNowPlayingInfoCenter` publishes title, podcast, artwork, duration, and
  elapsed time; `MPRemoteCommandCenter` wires play, pause, next, previous, and
  scrubbing to the lock screen, Control Center, and AirPods.
- Progress via `addPeriodicTimeObserver`; the observer token is removed on
  deinit.
- Queue boundaries are explicit and tested: previous on the first episode
  restarts it, next on the last stops playback.
- Interruptions (calls) and route changes (headphones unplugged) are handled —
  pause, and resume only when the system says `shouldResume`.

## Design — Liquid Glass

The design language is Apple's Liquid Glass. It is applied through modifiers in
`Core/Glass/`; feature code should read as intent, not as effect plumbing.

- **Content is opaque, chrome is glass.** Controls, bars, and floating
  accessories get glass. Never put text or artwork behind glass on top of more
  content — legibility beats effect every time.
- Group adjacent glass elements in a **`GlassEffectContainer`** so they blend and
  morph as one, and give them `.glassEffectID(_:in:)` with a shared
  `@Namespace` so transitions animate rather than cross-fade.
- Player transport controls use `.buttonStyle(.glass)`; the primary play/pause
  uses a tinted, `.interactive()` glass effect.
- The mini-player lives in **`.tabViewBottomAccessory`**, so it docks above the
  tab bar and expands into the full player exactly as Apple Music does. Pair it
  with `.tabBarMinimizeBehavior(.onScrollDown)`.
- Podcast artwork on the detail header uses `.backgroundExtensionEffect()` to
  bleed under the navigation bar.
- Scroll edges use `.scrollEdgeEffectStyle(.soft, for: .top)`.
- **Do not hand-roll glass.** No stacked blurs, no manual gradient overlays, no
  `.ultraThinMaterial` imitations. Use the system APIs or use nothing.

### Responsive layout

Required by the brief. `NavigationSplitView` at regular width (iPad, landscape),
`NavigationStack` at compact — driven by `@Environment(\.horizontalSizeClass)`.
The episode list uses an adaptive grid so it becomes multi-column on wide
screens. Test on iPhone SE, iPhone Pro Max, and iPad in both orientations.

### Accessibility

Not optional, and cheap to get right from the start. Dynamic Type through to the
accessibility sizes (no fixed frame heights on text), VoiceOver labels on every
icon-only control, `accessibilityValue` on the progress slider announcing
elapsed and remaining time, 44×44pt minimum hit targets, and correctness under
Reduce Transparency and Reduce Motion.

## Testing

**TDD for anything with logic**: write the failing test first, watch it fail,
then implement. Views are exempt; ViewModels are not.

### Rules

- **No network in tests, ever.** `HTTPClient` is a protocol; tests inject a fake
  returning fixture data.
- **Hand-written fakes, no mocking framework.** A fake that records calls and
  returns canned results is clearer than a DSL, and adds no dependency.
- Fixtures live in `PodcastPlayerTests/Fixtures/`: the three reference feeds
  saved verbatim, plus `malformed.xml`, `missing-optional-fields.xml`,
  `empty-channel.xml`, and `duration-formats.xml`.
- Tests are deterministic. Inject a clock for TTL logic; never call
  `Date()` inside code under test.

### Coverage that matters

| Area | What is proven |
|---|---|
| `RSSFeedParser` | All three duration formats, iTunes namespace, missing optional fields, malformed XML, empty channel, HTML stripping |
| Cache policy | TTL expiry, ETag revalidation, 304 handling, stale-while-revalidate ordering |
| `ImageCache` | Memory hit, disk hit, eviction under the size cap, clear |
| Repository | Cache-then-network ordering, offline falls back to cache, error mapping |
| ViewModels | `loading → loaded`, `loading → failed`, `retry → success`, empty feed → `.empty`, URL validation |
| Queue logic | next/previous, and both boundaries |

### UI tests (XCUITest)

Three smoke flows, run against a launch argument that injects fixture data:

1. Enter a URL → detail screen shows the podcast title and episode list.
2. Tap an episode → mini-player appears with the correct title → expand → full
   player shows matching metadata.
3. Settings → clear image cache → confirm → size reads zero.

Use `accessibilityIdentifier` for queries, never localized display strings.

## Commits

The brief grades commit structure explicitly. History should read as the build.

- [Conventional Commits](https://www.conventionalcommits.org/):
  `feat:`, `fix:`, `test:`, `refactor:`, `docs:`, `chore:`, `style:`
- **One logical change per commit.** A commit that touches the parser and the
  player is two commits.
- Each commit builds and has passing tests. No "wip", no "fix typo" noise —
  amend or squash before pushing.
- Body explains **why**, not what. The diff already says what.
- Suggested order: scaffold → domain models → parser (+ tests) → caches →
  repository → feed source screen → detail screen → player → mini-player and
  background audio → settings/clear cache → accessibility and polish.

## Commands

```bash
# Build
xcodebuild -scheme PodcastPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# Unit + UI tests
xcodebuild -scheme PodcastPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' test

# Unit tests only
xcodebuild -scheme PodcastPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PodcastPlayerTests test
```

Verify against a real simulator before claiming anything works. Xcode here is
26.2 / Swift 6.2.3 / iOS 26.2 SDK.

## Working style

- Read the surrounding code before adding to it; match its idiom.
- Prefer deleting to adding. YAGNI applies hard — this is an assessment, not a
  product. No feature the PDF did not ask for.
- When a file grows past a few hundred lines, it is doing too much. Split it.
- If a requirement in the PDF is ambiguous, pick the reading a careful reviewer
  would expect, implement it, and note the assumption in `README.md`.
- Never claim a test passes without having run it and read the output.
