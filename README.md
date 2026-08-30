# Podcast Player

A native iOS podcast player built from public RSS feeds.

Full write-up — architecture, screenshots, and trade-offs — lands with Task 21.
Until then:

- **Working agreement:** [`CLAUDE.md`](CLAUDE.md)
- **Implementation plan:** [`docs/superpowers/plans/2026-08-30-podcast-player.md`](docs/superpowers/plans/2026-08-30-podcast-player.md)
- **Original brief:** `Exercicio - Podcast.pdf`

## Requirements

Xcode 26 or later, iOS 26 simulator or device. No package manager step — the
project has zero third-party dependencies.

## Build and test

```bash
open PodcastPlayer.xcodeproj          # then ⌘R

xcodebuild -scheme PodcastPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## Sample feeds

- `https://feeds.megaphone.fm/la-cotorrisa`
- `https://anchor.fm/s/7a186bc/podcast/rss`
- `http://feeds.feedburner.com/GeekNights`
