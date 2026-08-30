import Testing
import Foundation
@testable import PodcastPlayer

@Suite("DurationParser")
struct DurationParserTests {
    @Test("Parses every format the iTunes spec permits", arguments: [
        ("01:02:03", 3723.0),   // HH:MM:SS, zero-padded
        ("1:02:03", 3723.0),    // HH:MM:SS, unpadded hours
        ("10:00:00", 36000.0),  // double-digit hours
        ("42:30", 2550.0),      // MM:SS
        ("07:05", 425.0),       // MM:SS, zero-padded
        ("0:30", 30.0),         // MM:SS, unpadded
        ("3600", 3600.0),       // raw seconds
        ("0", 0.0),             // zero seconds
        ("90", 90.0),
    ])
    func parsesEveryDurationFormat(raw: String, expected: TimeInterval) {
        #expect(DurationParser.parse(raw) == expected)
    }

    @Test("Returns nil rather than throwing on unusable input", arguments: [
        "", "   ", "abc", "1:2:3:4", "-30", "12:ab", "::", "1:", ":30", "1.5.2",
    ])
    func returnsNilForUnparseableInput(raw: String) {
        #expect(DurationParser.parse(raw) == nil)
    }

    @Test("A nil field is not an error")
    func returnsNilForNilInput() {
        #expect(DurationParser.parse(nil) == nil)
    }

    @Test("Tolerates the whitespace real feeds contain")
    func trimsSurroundingWhitespace() {
        #expect(DurationParser.parse("  12:00\n") == 720)
        #expect(DurationParser.parse("\t3600 ") == 3600)
    }

    @Test("Accepts fractional seconds some encoders emit")
    func acceptsFractionalSeconds() {
        #expect(DurationParser.parse("1800.5") == 1800.5)
    }

    @Test("Rejects out-of-range minute and second components")
    func rejectsOutOfRangeComponents() {
        #expect(DurationParser.parse("1:75:00") == nil)   // 75 minutes
        #expect(DurationParser.parse("10:99") == nil)     // 99 seconds
    }
}
