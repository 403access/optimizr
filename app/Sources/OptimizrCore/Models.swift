import Foundation

// MARK: - Categories

/// The three dimensions Optimizr audits.
public enum ScanCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case memory
    case cpu
    case storage

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .memory: return "Memory"
        case .cpu: return "CPU"
        case .storage: return "Storage"
        }
    }

    public var tagline: String {
        switch self {
        case .memory: return "Pressure, swap, and hungry apps"
        case .cpu: return "Load, background work, and thermals"
        case .storage: return "Caches, clutter, and free space"
        }
    }

    public var systemImage: String {
        switch self {
        case .memory: return "memorychip"
        case .cpu: return "cpu"
        case .storage: return "internaldrive"
        }
    }
}

// MARK: - Scope

/// Where a finding's condition lives. The fix may still be performed by the
/// user; this describes ownership of the mechanism, not of the remedy.
public enum FindingScope: String, Codable, CaseIterable, Sendable, Identifiable {
    /// A macOS or Apple-owned subsystem, setting, tool, or data store.
    case native
    /// Non-Apple software or an artifact it created.
    case thirdParty
    /// Depends on the app the user runs, or a native location holding third-party data.
    case mixed
    /// The user's own files rather than a vendor's software.
    case userData

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .native: return "Native"
        case .thirdParty: return "Third-party"
        case .mixed: return "Mixed"
        case .userData: return "User data"
        }
    }

    public var shortTitle: String {
        switch self {
        case .native: return "Native"
        case .thirdParty: return "3rd-party"
        case .mixed: return "Mixed"
        case .userData: return "Data"
        }
    }

    public var detail: String {
        switch self {
        case .native:
            return "Managed by macOS or Apple software. The fix is usually a system control or a restart."
        case .thirdParty:
            return "Owned by non-Apple software. Prefer the vendor's own tooling or uninstaller."
        case .mixed:
            return "Depends on the app you run, or a native location holding third-party data."
        case .userData:
            return "Your own files. Only you can decide whether they are still needed."
        }
    }

    public var systemImage: String {
        switch self {
        case .native: return "apple.logo"
        case .thirdParty: return "shippingbox"
        case .mixed: return "square.3.layers.3d"
        case .userData: return "person.crop.circle"
        }
    }
}

// MARK: - Severity

public enum Severity: Int, Codable, CaseIterable, Sendable, Comparable {
    case info = 0
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4

    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var title: String {
        switch self {
        case .critical: return "Critical"
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        case .info: return "Informational"
        }
    }

    /// Points deducted from a 100-point health score.
    public var scorePenalty: Double {
        switch self {
        case .critical: return 18
        case .high: return 11
        case .medium: return 6
        case .low: return 2.5
        case .info: return 0
        }
    }
}

// MARK: - Evidence

public struct Metric: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let label: String
    public let value: String
    public let isPrimary: Bool

    public init(label: String, value: String, isPrimary: Bool = false) {
        self.id = UUID().uuidString
        self.label = label
        self.value = value
        self.isPrimary = isPrimary
    }
}

public struct Reference: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let url: String

    public init(title: String, url: String) {
        self.id = url
        self.title = title
        self.url = url
    }
}

// MARK: - Remediation

public enum RemediationKind: String, Codable, Sendable {
    /// A shell command the user can copy and run themselves.
    case command
    /// A change made in System Settings or an app's own settings.
    case settings
    /// A manual, physical, or multi-app action.
    case manual
    /// A restart or sign-out is the cleanest resolution.
    case restart
}

public struct RemediationStep: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let detail: String
    public let command: String?
    public let kind: RemediationKind

    public init(
        title: String,
        detail: String,
        command: String? = nil,
        kind: RemediationKind = .manual
    ) {
        self.id = UUID().uuidString
        self.title = title
        self.detail = detail
        self.command = command
        self.kind = kind
    }
}

// MARK: - Finding

/// One concrete optimization opportunity, with evidence and a resolution path.
public struct Finding: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let category: ScanCategory
    public let title: String
    public let summary: String
    public let detail: String
    public let severity: Severity
    /// Where the condition lives: native, third-party, mixed, or user data.
    public let scope: FindingScope
    /// Estimated bytes that can be recovered. Nil when the finding is not about space.
    public let reclaimableBytes: Int64?
    public let metrics: [Metric]
    public let remediation: [RemediationStep]
    public let references: [Reference]
    /// Files or directories this finding refers to, used for "Reveal in Finder".
    public let paths: [String]
    public let tags: [String]

    public init(
        id: String,
        category: ScanCategory,
        title: String,
        summary: String,
        detail: String,
        severity: Severity,
        scope: FindingScope,
        reclaimableBytes: Int64? = nil,
        metrics: [Metric] = [],
        remediation: [RemediationStep] = [],
        references: [Reference] = [],
        paths: [String] = [],
        tags: [String] = []
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.summary = summary
        self.detail = detail
        self.severity = severity
        self.scope = scope
        self.reclaimableBytes = reclaimableBytes
        self.metrics = metrics
        self.remediation = remediation
        self.references = references
        self.paths = paths
        self.tags = tags
    }
}

// MARK: - Snapshot

public struct SystemSnapshot: Codable, Sendable, Hashable {
    public var hostName: String
    public var osVersion: String
    public var physicalMemory: Int64
    public var memoryUsed: Int64
    public var memoryFreePercent: Double
    /// 0 = relaxed, 1 = severe pressure.
    public var memoryPressure: Double
    public var swapUsed: Int64
    public var swapTotal: Int64
    public var cpuCount: Int
    public var loadAverages: [Double]
    public var uptime: TimeInterval
    public var diskTotal: Int64
    public var diskFree: Int64

    public init(
        hostName: String = "",
        osVersion: String = "",
        physicalMemory: Int64 = 0,
        memoryUsed: Int64 = 0,
        memoryFreePercent: Double = 0,
        memoryPressure: Double = 0,
        swapUsed: Int64 = 0,
        swapTotal: Int64 = 0,
        cpuCount: Int = 0,
        loadAverages: [Double] = [],
        uptime: TimeInterval = 0,
        diskTotal: Int64 = 0,
        diskFree: Int64 = 0
    ) {
        self.hostName = hostName
        self.osVersion = osVersion
        self.physicalMemory = physicalMemory
        self.memoryUsed = memoryUsed
        self.memoryFreePercent = memoryFreePercent
        self.memoryPressure = memoryPressure
        self.swapUsed = swapUsed
        self.swapTotal = swapTotal
        self.cpuCount = cpuCount
        self.loadAverages = loadAverages
        self.uptime = uptime
        self.diskTotal = diskTotal
        self.diskFree = diskFree
    }

    public static let empty = SystemSnapshot()

    public var loadAverage1: Double { loadAverages.first ?? 0 }
    public var loadAverage5: Double { loadAverages.count > 1 ? loadAverages[1] : 0 }
    public var loadAverage15: Double { loadAverages.count > 2 ? loadAverages[2] : 0 }

    public var memoryPressureLabel: String {
        switch memoryPressure {
        case ..<0.30: return "Relaxed"
        case ..<0.50: return "Moderate"
        case ..<0.70: return "Elevated"
        case ..<0.85: return "High"
        default: return "Severe"
        }
    }

    public var diskUsedFraction: Double {
        guard diskTotal > 0 else { return 0 }
        return Double(diskTotal - diskFree) / Double(diskTotal)
    }

    public var swapFraction: Double {
        guard swapTotal > 0 else { return 0 }
        return Double(swapUsed) / Double(swapTotal)
    }
}

// MARK: - Report

public struct ScanReport: Codable, Sendable, Hashable {
    public let startedAt: Date
    public let finishedAt: Date
    public let findings: [Finding]
    public let snapshot: SystemSnapshot

    public init(startedAt: Date, finishedAt: Date, findings: [Finding], snapshot: SystemSnapshot) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.findings = findings
        self.snapshot = snapshot
    }

    public static let empty = ScanReport(
        startedAt: .distantPast,
        finishedAt: .distantPast,
        findings: [],
        snapshot: .empty
    )

    public var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }

    public var totalReclaimableBytes: Int64 {
        findings.compactMap(\.reclaimableBytes).reduce(0, +)
    }

    public var sortedFindings: [Finding] {
        findings.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            let leftBytes = lhs.reclaimableBytes ?? 0
            let rightBytes = rhs.reclaimableBytes ?? 0
            if leftBytes != rightBytes { return leftBytes > rightBytes }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    public func findings(for category: ScanCategory) -> [Finding] {
        sortedFindings.filter { $0.category == category }
    }

    public func count(for category: ScanCategory) -> Int {
        findings.lazy.filter { $0.category == category }.count
    }

    public func reclaimableBytes(for category: ScanCategory) -> Int64 {
        findings.lazy
            .filter { $0.category == category }
            .compactMap(\.reclaimableBytes)
            .reduce(0, +)
    }

    public var healthScore: Int {
        // Average the three lens scores instead of summing every penalty. A
        // single pathological category should not erase the other two, and the
        // dashboard still exposes the per-category numbers.
        let scores = ScanCategory.allCases.map { score(for: $0) }
        guard !scores.isEmpty else { return 100 }
        return Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
    }

    public func score(for category: ScanCategory?) -> Int {
        let relevant = category.map { findings(for: $0) } ?? findings
        let penalty = relevant.reduce(0.0) { $0 + $1.severity.scorePenalty }
        return max(0, min(100, Int((100.0 - penalty).rounded())))
    }

    public func scoreLabel(for category: ScanCategory? = nil) -> String {
        let value = category.map { score(for: $0) } ?? healthScore
        switch value {
        case 90...: return "Excellent"
        case 75..<90: return "Good"
        case 55..<75: return "Needs attention"
        case 30..<55: return "Poor"
        default: return "Critical"
        }
    }
}

// MARK: - Markdown export

public extension ScanReport {
    /// A portable report the user can paste into a ticket, note, or chat.
    func markdown() -> String {
        let formatter = ISO8601DateFormatter()
        var lines: [String] = []
        lines.append("# Optimizr report")
        lines.append("")
        lines.append("- Generated: \(formatter.string(from: finishedAt))")
        lines.append("- Host: \(snapshot.hostName)")
        lines.append("- System: \(snapshot.osVersion)")
        lines.append("- Health score: \(healthScore)/100 (\(scoreLabel()))")
        lines.append("- Findings: \(findings.count)")
        if totalReclaimableBytes > 0 {
            lines.append("- Reclaimable: \(Format.bytes(totalReclaimableBytes))")
        }
        lines.append("")
        lines.append("## Summary")
        lines.append("")
        for category in ScanCategory.allCases {
            let count = count(for: category)
            let bytes = reclaimableBytes(for: category)
            var line = "- **\(category.title)** — \(count) finding\(count == 1 ? "" : "s"), score \(score(for: category))/100"
            if bytes > 0 { line += ", \(Format.bytes(bytes)) reclaimable" }
            lines.append(line)
        }
        lines.append("")

        for category in ScanCategory.allCases {
            let items = findings(for: category)
            guard !items.isEmpty else { continue }
            lines.append("## \(category.title)")
            lines.append("")
            for finding in items {
                lines.append("### \(finding.title) — \(finding.severity.title)")
                lines.append("")
                lines.append("- **Scope:** \(finding.scope.title) — \(finding.scope.detail)")
                lines.append("")
                lines.append(finding.summary)
                lines.append("")
                if !finding.metrics.isEmpty {
                    for metric in finding.metrics {
                        lines.append("- \(metric.label): \(metric.value)")
                    }
                    lines.append("")
                }
                if !finding.remediation.isEmpty {
                    lines.append("**How to fix**")
                    lines.append("")
                    for (index, step) in finding.remediation.enumerated() {
                        lines.append("\(index + 1). **\(step.title)** — \(step.detail)")
                        if let command = step.command {
                            lines.append("")
                            lines.append("   ```sh")
                            lines.append("   \(command)")
                            lines.append("   ```")
                        }
                    }
                    lines.append("")
                }
            }
        }
        lines.append("---")
        lines.append("")
        lines.append("Generated by Optimizr. Findings are read-only observations; nothing was changed on this Mac.")
        return lines.joined(separator: "\n")
    }
}
