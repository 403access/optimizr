import Foundation

public enum SystemProfiler {
    /// Collects the dashboard snapshot. Every field degrades gracefully so a
    /// missing utility never prevents a scan.
    public static func snapshot(runner: any CommandRunning = ShellCommandRunner()) -> SystemSnapshot {
        let processInfo = ProcessInfo.processInfo
        var snapshot = SystemSnapshot(
            hostName: processInfo.hostName,
            osVersion: processInfo.operatingSystemVersionString,
            physicalMemory: Int64(processInfo.physicalMemory),
            cpuCount: processInfo.processorCount,
            uptime: processInfo.systemUptime
        )

        let vmOutput = runner.run("/usr/bin/vm_stat", arguments: [], timeout: 5)
        let vm = VMStatistics.parse(vmOutput.stdout)

        let swapOutput = runner.run("/usr/sbin/sysctl", arguments: ["-n", "vm.swapusage"], timeout: 3)
        let swap = SwapUsage.parse(swapOutput.stdout)

        let pressureOutput = runner.run("/usr/bin/memory_pressure", arguments: [], timeout: 5)
        let freePercent = MemoryPressureParser.parseFreePercentage(pressureOutput.stdout)

        let loadOutput = runner.run("/usr/sbin/sysctl", arguments: ["-n", "vm.loadavg"], timeout: 3)
        let loads = LoadAverageParser.parse(loadOutput.stdout)

        if let vm {
            snapshot.memoryFreePercent = freePercent ?? (Double(vm.freeBytes) / Double(max(1, snapshot.physicalMemory)) * 100)
        } else if let freePercent {
            snapshot.memoryFreePercent = freePercent
        }

        let usedFraction = min(1, max(0, 1 - snapshot.memoryFreePercent / 100))
        snapshot.memoryUsed = Int64(Double(snapshot.physicalMemory) * usedFraction)

        if let swap {
            snapshot.swapTotal = swap.totalBytes
            snapshot.swapUsed = swap.usedBytes
        }

        // Swap pressure is weighted heavily: macOS only swaps under real memory
        // pressure, and a nearly full swap file is a strong signal.
        snapshot.memoryPressure = min(1, max(0, usedFraction * 0.55 + snapshot.swapFraction * 0.45))
        snapshot.loadAverages = Array(loads.prefix(3))

        if let attributes = try? FileManager.default.attributesOfFileSystem(forPath: "/") {
            snapshot.diskTotal = (attributes[.systemSize] as? NSNumber)?.int64Value ?? 0
            snapshot.diskFree = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        }

        return snapshot
    }
}

// MARK: - Launch items

public enum LaunchItemScope: String, Codable, Sendable, CaseIterable {
    case userAgent
    case globalAgent
    case globalDaemon

    public var title: String {
        switch self {
        case .userAgent: return "User agent"
        case .globalAgent: return "Global agent"
        case .globalDaemon: return "Global daemon"
        }
    }
}

public struct LaunchItem: Identifiable, Codable, Sendable, Hashable {
    public let label: String
    public let path: String
    public let scope: LaunchItemScope

    public var id: String { path }

    public init(label: String, path: String, scope: LaunchItemScope) {
        self.label = label
        self.path = path
        self.scope = scope
    }

    public var vendor: String {
        let components = label.split(separator: ".")
        if components.count >= 2 {
            return String(components[0]) + "." + String(components[1])
        }
        return label
    }
}

public enum LaunchItemInventory {
    /// Lists third-party launch agents and daemons. Apple's own services are skipped.
    public static func scan(fileManager: FileManager = .default) -> [LaunchItem] {
        let directories: [(URL, LaunchItemScope)] = [
            (Paths.home("Library/LaunchAgents"), .userAgent),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), .globalAgent),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), .globalDaemon)
        ]

        var items: [LaunchItem] = []
        var seen = Set<String>()

        for (directory, scope) in directories {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents where url.pathExtension.lowercased() == "plist" {
                let fallback = url.deletingPathExtension().lastPathComponent
                let label = readLabel(from: url) ?? fallback
                guard !label.hasPrefix("com.apple.") else { continue }
                guard seen.insert(url.path).inserted else { continue }
                items.append(LaunchItem(label: label, path: url.path, scope: scope))
            }
        }

        return items.sorted {
            if $0.scope != $1.scope { return $0.scope.rawValue < $1.scope.rawValue }
            return $0.label.localizedStandardCompare($1.label) == .orderedAscending
        }
    }

    private static func readLabel(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary["Label"] as? String
    }
}

// MARK: - Disk helpers

public enum DuParser {
    /// Parses `du -sk` output into bytes.
    public static func bytes(_ output: String) -> Int64? {
        let firstLine = output.split(separator: "\n").first.map(String.init) ?? output
        guard let first = firstLine.split(separator: "\t").first ?? firstLine.split(separator: " ").first,
              let kilobytes = Int64(first) else { return nil }
        return kilobytes * 1_024
    }
}

public struct LargeFile: Identifiable, Codable, Sendable, Hashable {
    public let path: String
    public let bytes: Int64

    public var id: String { path }
    public var displayPath: String {
        let homePath = Paths.home.path
        if path.hasPrefix(homePath + "/") {
            return "~/" + String(path.dropFirst(homePath.count + 1))
        }
        return path
    }

    public init(path: String, bytes: Int64) {
        self.path = path
        self.bytes = bytes
    }
}

public enum LargeFileParser {
    /// Parses the output of
    /// `find … -exec stat -f "%z|%N" {} +`.
    public static func parse(_ output: String) -> [LargeFile] {
        output.split(separator: "\n").compactMap { line in
            let text = String(line)
            guard let separator = text.firstIndex(of: "|") else { return nil }
            guard let bytes = Int64(text[..<separator]) else { return nil }
            let path = String(text[text.index(after: separator)...])
            guard !path.isEmpty, bytes > 0 else { return nil }
            return LargeFile(path: path, bytes: bytes)
        }
    }
}
