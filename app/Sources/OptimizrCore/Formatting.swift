import Foundation

public enum Format {
    /// Human-friendly byte count, e.g. "12.4 GB".
    public static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: max(0, value))
    }

    /// Compact byte count for tight spaces, e.g. "12.4G".
    public static func bytesShort(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        formatter.includesCount = true
        formatter.zeroPadsFractionDigits = false
        return formatter.string(fromByteCount: max(0, value))
    }

    public static func percent(_ fraction: Double, decimals: Int = 0) -> String {
        let clamped = min(max(fraction, 0), 1)
        return String(format: "%.\(decimals)f%%", clamped * 100)
    }

    public static func decimal(_ value: Double, decimals: Int = 2) -> String {
        String(format: "%.\(decimals)f", value)
    }

    /// "3d 4h", "52m", "18s".
    public static func uptime(_ interval: TimeInterval) -> String {
        let seconds = Int(max(0, interval))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }

    public static func relativeTime(from date: Date, now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

public enum ByteMath {
    public static let kilobyte: Int64 = 1_000
    public static let megabyte: Int64 = 1_000_000
    public static let gigabyte: Int64 = 1_000_000_000
    public static let terabyte: Int64 = 1_000_000_000_000

    /// Parses values such as "12.4M", "1.2G", or "512K" into bytes.
    public static func parseCompact(_ value: Double, unit: String) -> Int64 {
        let multiplier: Double
        switch unit.uppercased() {
        case "K", "KB": multiplier = 1_000
        case "M", "MB": multiplier = 1_000_000
        case "G", "GB": multiplier = 1_000_000_000
        case "T", "TB": multiplier = 1_000_000_000_000
        case "B": multiplier = 1
        default: multiplier = 1
        }
        return Int64((value * multiplier).rounded())
    }

    /// Severity for a reclaimable directory based on configurable thresholds.
    public static func severity(
        for bytes: Int64,
        reportThreshold: Int64,
        highThreshold: Int64,
        criticalThreshold: Int64
    ) -> Severity? {
        if bytes < reportThreshold { return nil }
        if bytes >= criticalThreshold { return .critical }
        if bytes >= highThreshold { return .high }
        return .medium
    }
}
