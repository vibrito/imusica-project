import Foundation

/// Display formatting, in one place so the same value never reads two ways on
/// two screens.
enum Formatters {

    /// Episode length for a list row: "1h 2m", "42m", "—".
    static func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else {
            return String(localized: "—", comment: "Shown when an episode declares no duration")
        }

        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60

        if hours > 0 {
            return minutes > 0
                ? String(localized: "\(hours)h \(minutes)m")
                : String(localized: "\(hours)h")
        }
        return String(localized: "\(minutes)m")
    }

    /// Transport timecode: "42:30", or "01:02:03" once past an hour.
    static func timecode(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }

        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        return hours > 0
            ? String(format: "%02d:%02d:%02d", hours, minutes, secs)
            : String(format: "%02d:%02d", minutes, secs)
    }

    /// Time remaining, as the transport shows it: "-07:30".
    static func remaining(elapsed: TimeInterval, duration: TimeInterval) -> String {
        guard duration > 0 else { return "--:--" }   // punctuation, not prose
        return "-" + timecode(max(0, duration - elapsed))
    }

    // Read-only after construction, so sharing is safe and beats rebuilding
    // a formatter per episode row.
    nonisolated(unsafe) private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func relativeDate(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        return relative.localizedString(for: date, relativeTo: now)
    }

    static func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Plural rules differ by language, so these come from the string
    /// catalogue rather than a ternary.
    static func feedCount(_ count: Int) -> String {
        String(localized: "\(count) feeds")
    }

    static func addressCount(_ count: Int) -> String {
        String(localized: "\(count) addresses")
    }

    static func episodeCount(_ count: Int) -> String {
        String(localized: "\(count) episodes")
    }

    /// Spoken form for VoiceOver, where "42:30" is read as a time of day.
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return String(localized: "unknown length") }

        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60

        var parts: [String] = []
        if hours > 0 { parts.append(String(localized: "\(hours) hours")) }
        if minutes > 0 { parts.append(String(localized: "\(minutes) minutes")) }
        return parts.isEmpty
            ? String(localized: "less than a minute")
            : parts.joined(separator: " ")
    }
}
