import Testing
import Foundation
@testable import PodcastPlayer

@Suite("Formatters")
struct FormattersTests {

    @Test("Formats episode lengths for a list row", arguments: [
        (nil as TimeInterval?, "—"),
        (0.0, "0m"),
        (90.0, "1m"),
        (2550.0, "42m"),
        (3600.0, "1h"),
        (3723.0, "1h 2m"),
        (7380.0, "2h 3m"),
    ])
    func formatsDurations(input: TimeInterval?, expected: String) {
        #expect(Formatters.duration(input) == expected)
    }

    @Test("Rejects nonsense durations rather than printing them")
    func rejectsInvalidDurations() {
        #expect(Formatters.duration(-5) == "—")
        #expect(Formatters.duration(.infinity) == "—")
        #expect(Formatters.duration(.nan) == "—")
    }

    @Test("Formats transport timecodes", arguments: [
        (0.0, "00:00"),
        (65.0, "01:05"),
        (2550.0, "42:30"),
        (3723.0, "01:02:03"),
    ])
    func formatsTimecodes(input: TimeInterval, expected: String) {
        #expect(Formatters.timecode(input) == expected)
    }

    @Test("A non-finite timecode degrades rather than crashing")
    func handlesInvalidTimecodes() {
        #expect(Formatters.timecode(.nan) == "00:00")
        #expect(Formatters.timecode(-10) == "00:00")
    }

    @Test("Counts time remaining down")
    func formatsRemaining() {
        #expect(Formatters.remaining(elapsed: 150, duration: 600) == "-07:30")
        #expect(Formatters.remaining(elapsed: 600, duration: 600) == "-00:00")
    }

    @Test("Remaining never goes negative when elapsed overshoots")
    func remainingNeverGoesNegative() {
        #expect(Formatters.remaining(elapsed: 700, duration: 600) == "-00:00")
    }

    @Test("An unknown duration shows placeholders, not a wrong number")
    func remainingWithoutDuration() {
        #expect(Formatters.remaining(elapsed: 10, duration: 0) == "--:--")
    }

    @Test("Pluralises the feed count correctly at one")
    func formatsFeedCount() {
        #expect(Formatters.feedCount(0) == "0 feeds")
        #expect(Formatters.feedCount(1) == "1 feed")
        #expect(Formatters.feedCount(3) == "3 feeds")
    }

    @Test("Formats byte counts")
    func formatsByteCount() {
        #expect(Formatters.byteCount(0).contains("Zero"))
        #expect(Formatters.byteCount(5 * 1024 * 1024).contains("MB"))
    }

    @Test("Speaks durations as words, since VoiceOver reads 42:30 as a clock time")
    func speaksDurations() {
        #expect(Formatters.spokenDuration(3723) == "1 hour 2 minutes")
        #expect(Formatters.spokenDuration(2550) == "42 minutes")
        #expect(Formatters.spokenDuration(30) == "less than a minute")
        #expect(Formatters.spokenDuration(0) == "unknown length")
    }
}
