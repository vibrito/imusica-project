import Foundation

/// Display formatting, in one place so the same value never reads two ways on
/// two screens.
enum Formatters {

    /// Episode length for a list row: "1h 2m", "42m", "—".
    static func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }

        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60

        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
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
        guard duration > 0 else { return "--:--" }
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

    /// "1 feed" / "3 feeds" — a plural that reads correctly at one.
    static func feedCount(_ count: Int) -> String {
        count == 1 ? "1 feed" : "\(count) feeds"
    }

    /// Spoken form for VoiceOver, where "42:30" is read as a time of day.
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "unknown length" }

        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60

        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hour\(hours == 1 ? "" : "s")") }
        if minutes > 0 { parts.append("\(minutes) minute\(minutes == 1 ? "" : "s")") }
        return parts.isEmpty ? "less than a minute" : parts.joined(separator: " ")
    }
}
