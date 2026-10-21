import Foundation

public enum SizeText {
    /// Finder-style decimal sizes: 1 KB = 1,000 bytes.
    public static func string(_ bytes: Int64) -> String {
        let value = Double(max(0, bytes))
        if value < 1_000 {
            let count = Int(value)
            return count == 1 ? "1 byte" : "\(count) bytes"
        }

        let units = ["KB", "MB", "GB", "TB", "PB"]
        var scaled = value / 1_000
        var unitIndex = 0
        while scaled >= 1_000, unitIndex < units.count - 1 {
            scaled /= 1_000
            unitIndex += 1
        }

        if scaled >= 100 {
            return String(format: "%.0f %@", scaled, units[unitIndex])
        }

        let formatted = String(format: "%.1f", scaled)
        let trimmed = formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted
        return "\(trimmed) \(units[unitIndex])"
    }

    public static func string(_ bytes: Int64, signed: Bool) -> String {
        bytes > 0 && signed ? "+" + string(bytes) : string(bytes)
    }

    public static func percent(_ fraction: Double) -> String {
        guard fraction.isFinite else { return "0%" }
        let clamped = min(1, max(0, fraction))
        if clamped > 0 && clamped < 0.01 {
            return "<1%"
        }
        return "\(Int((clamped * 100).rounded()))%"
    }

    public static func abbreviatedPath(_ path: String, home: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    public static func relativeDate(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
