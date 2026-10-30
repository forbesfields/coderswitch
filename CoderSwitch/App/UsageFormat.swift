import Foundation

/// Pure text helpers shared by the popover, menu bar tooltip, and settings.
enum UsageFormat {
    static func percent(_ fraction: Double) -> String {
        "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }

    /// "3h 12m", "2d 4h", "45m", or "<1m".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }

    static func resetsIn(_ date: Date, now: Date = Date()) -> String {
        let remaining = date.timeIntervalSince(now)
        return remaining <= 0 ? "reset due" : "resets in \(duration(remaining))"
    }

    /// "Updated just now", "Updated 2m ago", or "Not updated yet".
    static func updated(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Not updated yet" }
        let elapsed = now.timeIntervalSince(date)
        return elapsed < 45 ? "Updated just now" : "Updated \(duration(elapsed)) ago"
    }

    static func tokens(_ value: Int) -> String {
        switch value {
        case 1_000_000...: String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...: String(format: "%.1fK", Double(value) / 1_000)
        default: "\(value)"
        }
    }
}
