import Foundation

/// Parses `itunes:duration`, which the Apple spec permits in three shapes:
/// `HH:MM:SS`, `MM:SS`, or a plain count of seconds.
///
/// Real feeds use all three, sometimes within one publisher's catalogue, so
/// every shape is supported. Unusable input returns nil rather than throwing —
/// a missing duration is a cosmetic gap, never a reason to reject an episode.
enum DurationParser {
    static func parse(_ raw: String?) -> TimeInterval? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)

        switch parts.count {
        case 1:
            // Plain seconds. Fractional values appear from some encoders.
            guard let seconds = Double(parts[0]), seconds >= 0 else { return nil }
            return seconds

        case 2:
            guard let minutes = wholeNumber(parts[0]),
                  let seconds = wholeNumber(parts[1]),
                  seconds < 60 else { return nil }
            return TimeInterval(minutes * 60 + seconds)

        case 3:
            guard let hours = wholeNumber(parts[0]),
                  let minutes = wholeNumber(parts[1]),
                  let seconds = wholeNumber(parts[2]),
                  minutes < 60, seconds < 60 else { return nil }
            return TimeInterval(hours * 3600 + minutes * 60 + seconds)

        default:
            return nil
        }
    }

    /// A non-negative integer component. Rejects empty strings, signs, and
    /// decimals, all of which show up in malformed feeds.
    private static func wholeNumber(_ substring: Substring) -> Int? {
        guard !substring.isEmpty,
              substring.allSatisfy(\.isNumber),
              let value = Int(substring) else { return nil }
        return value
    }
}
