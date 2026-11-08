import Foundation

// MARK: - vm_stat

public struct VMStatistics: Equatable, Sendable {
    public var pageSize: Int64 = 4_096
    public var freePages: Int64 = 0
    public var activePages: Int64 = 0
    public var inactivePages: Int64 = 0
    public var speculativePages: Int64 = 0
    public var throttledPages: Int64 = 0
    public var wiredPages: Int64 = 0
    public var purgeablePages: Int64 = 0
    public var compressorPages: Int64 = 0
    public var fileBackedPages: Int64 = 0
    public var anonymousPages: Int64 = 0
    public var swapouts: Int64 = 0
    public var pageins: Int64 = 0

    public init() {}

    public var freeBytes: Int64 { freePages * pageSize }
    public var activeBytes: Int64 { activePages * pageSize }
    public var inactiveBytes: Int64 { inactivePages * pageSize }
    public var wiredBytes: Int64 { wiredPages * pageSize }
    public var compressedBytes: Int64 { compressorPages * pageSize }
    public var purgeableBytes: Int64 { purgeablePages * pageSize }

    public var usedBytes: Int64 {
        max(0, activeBytes + wiredBytes + compressedBytes - purgeableBytes)
    }

    public static func parse(_ output: String) -> VMStatistics? {
        var stats = VMStatistics()
        var matchedAny = false

        for rawLine in output.split(separator: "\n") {
            let line = String(rawLine)
            if line.contains("page size of"),
               let range = line.range(of: #"page size of (\d+) bytes"#, options: .regularExpression) {
                let number = line[range]
                    .replacingOccurrences(of: "page size of ", with: "")
                    .replacingOccurrences(of: " bytes", with: "")
                if let size = Int64(number) { stats.pageSize = size }
                continue
            }

            guard let colon = line.firstIndex(of: ":") else { continue }
            let rawKey = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard let value = Int64(rawValue) else { continue }
            matchedAny = true

            switch rawKey {
            case "Pages free": stats.freePages = value
            case "Pages active": stats.activePages = value
            case "Pages inactive": stats.inactivePages = value
            case "Pages speculative": stats.speculativePages = value
            case "Pages throttled": stats.throttledPages = value
            case "Pages wired down": stats.wiredPages = value
            case "Pages purgeable": stats.purgeablePages = value
            case "Pages occupied by compressor": stats.compressorPages = value
            case "File-backed pages": stats.fileBackedPages = value
            case "Anonymous pages": stats.anonymousPages = value
            case "Swapouts": stats.swapouts = value
            case "Pageins": stats.pageins = value
            default: break
            }
        }

        return matchedAny ? stats : nil
    }
}

// MARK: - swap

public struct SwapUsage: Equatable, Sendable {
    public var totalBytes: Int64
    public var usedBytes: Int64
    public var freeBytes: Int64

    public init(totalBytes: Int64, usedBytes: Int64, freeBytes: Int64) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.freeBytes = freeBytes
    }

    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }

    /// Parses `sysctl -n vm.swapusage`:
    /// `total = 13312.00M  used = 12581.12M  free = 730.88M  (encrypted)`
    public static func parse(_ output: String) -> SwapUsage? {
        func value(for key: String) -> Int64? {
            let pattern = key + #"\s*=\s*([0-9.]+)\s*([KMG]?)"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return nil
            }
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            guard let match = regex.firstMatch(in: output, options: [], range: range),
                  match.numberOfRanges >= 2,
                  let numberRange = Range(match.range(at: 1), in: output),
                  let number = Double(output[numberRange]) else {
                return nil
            }
            var unit = "M"
            if match.numberOfRanges >= 3, let unitRange = Range(match.range(at: 2), in: output) {
                let parsed = String(output[unitRange])
                if !parsed.isEmpty { unit = parsed }
            }
            return ByteMath.parseCompact(number, unit: unit)
        }

        guard let total = value(for: "total"),
              let used = value(for: "used") else { return nil }
        let free = value(for: "free") ?? max(0, total - used)
        return SwapUsage(totalBytes: total, usedBytes: used, freeBytes: free)
    }
}

// MARK: - memory pressure

public enum MemoryPressureParser {
    /// Extracts the free percentage from `/usr/bin/memory_pressure`.
    public static func parseFreePercentage(_ output: String) -> Double? {
        guard let regex = try? NSRegularExpression(
            pattern: #"System-wide memory free percentage:\s*([0-9.]+)%"#,
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, options: [], range: range),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: output),
              let value = Double(output[valueRange]) else {
            return nil
        }
        return min(100, max(0, value))
    }
}

// MARK: - processes

public struct ProcessSample: Identifiable, Codable, Sendable, Hashable {
    public let pid: Int
    public let name: String
    public let cpuPercent: Double
    public let memoryBytes: Int64

    public var id: Int { pid }

    public init(pid: Int, name: String, cpuPercent: Double, memoryBytes: Int64) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }

    /// A shortened, human-friendly process name.
    public var displayName: String {
        if let appRange = name.range(of: ".app/") {
            let prefix = String(name[..<appRange.lowerBound])
            return (prefix as NSString).lastPathComponent + ".app"
        }
        return (name as NSString).lastPathComponent
    }
}

public enum ProcessSampleParser {
    /// Parses `ps -axo pid=,rss=,pcpu=,comm=`. RSS is reported in kilobytes.
    public static func parse(_ output: String) -> [ProcessSample] {
        var samples: [ProcessSample] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4,
                  let pid = Int(parts[0]),
                  let rssKB = Int64(parts[1]),
                  let cpu = Double(parts[2]) else { continue }
            let name = String(parts[3]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, pid > 0 else { continue }
            samples.append(ProcessSample(
                pid: pid,
                name: name,
                cpuPercent: cpu,
                memoryBytes: rssKB * 1_024
            ))
        }
        return samples
    }
}

// MARK: - load average

public enum LoadAverageParser {
    /// Parses `sysctl -n vm.loadavg`: `{ 6.30 9.45 10.29 }`.
    public static func parse(_ output: String) -> [Double] {
        let cleaned = output
            .replacingOccurrences(of: "{", with: " ")
            .replacingOccurrences(of: "}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.split(separator: " ").compactMap { Double($0) }
    }
}

// MARK: - thermal / power

public struct ThermalState: Equatable, Sendable {
    public var speedLimit: Int?
    public var thermalWarningLevel: Int?

    public init(speedLimit: Int? = nil, thermalWarningLevel: Int? = nil) {
        self.speedLimit = speedLimit
        self.thermalWarningLevel = thermalWarningLevel
    }

    public var isThrottled: Bool {
        if let speedLimit, speedLimit < 100 { return true }
        if let thermalWarningLevel, thermalWarningLevel > 0 { return true }
        return false
    }

    /// Parses `pmset -g therm`. Missing values are normal on Apple silicon.
    public static func parse(_ output: String) -> ThermalState {
        var state = ThermalState()
        for line in output.split(separator: "\n") {
            let text = String(line)
            if let range = text.range(of: #"CPU_Speed_Limit\s*=\s*([0-9]+)"#, options: .regularExpression) {
                let number = text[range].split(separator: "=").last?
                    .trimmingCharacters(in: .whitespaces)
                state.speedLimit = number.flatMap(Int.init)
            }
            if let range = text.range(of: #"CPU_Thermal_Warning_Level\s*=\s*([0-9]+)"#, options: .regularExpression) {
                let number = text[range].split(separator: "=").last?
                    .trimmingCharacters(in: .whitespaces)
                state.thermalWarningLevel = number.flatMap(Int.init)
            }
        }
        return state
    }
}

public enum PowerSettingsParser {
    /// Returns `true` when `pmset -g` reports Low Power Mode is enabled.
    public static func lowPowerModeEnabled(_ output: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"lowpowermode\s+([01])"#) else {
            return false
        }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, options: [], range: range),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: output) else {
            return false
        }
        return output[valueRange] == "1"
    }
}
