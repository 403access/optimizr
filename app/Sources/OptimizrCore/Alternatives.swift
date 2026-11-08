import Foundation

// MARK: - Running applications

/// A running app bundle or background service, aggregated across its processes.
public struct RunningApplication: Identifiable, Sendable, Hashable {
    public let name: String
    public let bundleIdentifier: String?
    public let path: String?
    public let memoryBytes: Int64
    public let cpuPercent: Double
    public let processCount: Int

    public var id: String { bundleIdentifier ?? path ?? name }

    public init(
        name: String,
        bundleIdentifier: String?,
        path: String?,
        memoryBytes: Int64,
        cpuPercent: Double,
        processCount: Int
    ) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.path = path
        self.memoryBytes = memoryBytes
        self.cpuPercent = cpuPercent
        self.processCount = processCount
    }
}

public enum RunningApplicationInventory {
    /// Groups process samples into app bundles where possible and into
    /// executable-named services otherwise.
    public static func runningApplications(from samples: [ProcessSample]) -> [RunningApplication] {
        var accumulated: [String: Accumulator] = [:]

        for sample in samples {
            if let bundlePath = appBundlePath(from: sample.name) {
                let key = "app:" + bundlePath
                var accumulator = accumulated[key] ?? {
                    let info = bundleInfo(at: bundlePath)
                    let fallback = ((bundlePath as NSString).lastPathComponent as NSString).deletingPathExtension
                    return Accumulator(
                        name: info.name ?? fallback,
                        bundleIdentifier: info.identifier,
                        path: bundlePath
                    )
                }()
                accumulator.add(sample)
                accumulated[key] = accumulator
            } else {
                let name = (sample.name as NSString).lastPathComponent
                guard !name.isEmpty else { continue }
                let key = "service:" + name
                var accumulator = accumulated[key] ?? Accumulator(
                    name: name,
                    bundleIdentifier: nil,
                    path: nil
                )
                accumulator.add(sample)
                accumulated[key] = accumulator
            }
        }

        return accumulated.values
            .map(\.application)
            .sorted {
                if $0.memoryBytes != $1.memoryBytes { return $0.memoryBytes > $1.memoryBytes }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    /// Returns the `.app` bundle prefix of a process command path.
    public static func appBundlePath(from command: String) -> String? {
        guard let range = command.range(of: ".app/") else { return nil }
        let end = command.index(range.lowerBound, offsetBy: 4)
        let path = String(command[..<end])
        guard path.hasPrefix("/") else { return nil }
        return path
    }

    private static func bundleInfo(at path: String) -> (identifier: String?, name: String?) {
        let infoURL = URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = object as? [String: Any] else {
            return (nil, nil)
        }
        return (
            dictionary["CFBundleIdentifier"] as? String,
            (dictionary["CFBundleDisplayName"] as? String) ?? (dictionary["CFBundleName"] as? String)
        )
    }

    private struct Accumulator {
        let name: String
        let bundleIdentifier: String?
        let path: String?
        var memoryBytes: Int64 = 0
        var cpuPercent: Double = 0
        var processCount = 0

        mutating func add(_ sample: ProcessSample) {
            memoryBytes += sample.memoryBytes
            cpuPercent += sample.cpuPercent
            processCount += 1
        }

        var application: RunningApplication {
            RunningApplication(
                name: name,
                bundleIdentifier: bundleIdentifier,
                path: path,
                memoryBytes: memoryBytes,
                cpuPercent: cpuPercent,
                processCount: processCount
            )
        }
    }
}

// MARK: - Catalog

public enum AlternativeConfidence: String, Codable, Sendable, CaseIterable, Hashable {
    case typical
    case workloadDependent

    public var title: String {
        switch self {
        case .typical: return "Typical"
        case .workloadDependent: return "Workload-dependent"
        }
    }
}

/// A known, conservative replacement for an app or service, with the resource
/// difference as a fraction of the measured footprint.
public struct AlternativeEntry: Identifiable, Sendable, Hashable {
    public let id: String
    public let bundleIdentifiers: [String]
    public let executableNames: [String]
    public let alternative: String
    public let memorySavingRange: ClosedRange<Double>?
    public let cpuSavingRange: ClosedRange<Double>?
    public let rationale: String
    public let caveat: String
    public let migration: [RemediationStep]
    public let references: [Reference]
    public let confidence: AlternativeConfidence
    public let tags: [String]

    public init(
        id: String,
        bundleIdentifiers: [String],
        executableNames: [String],
        alternative: String,
        memorySavingRange: ClosedRange<Double>?,
        cpuSavingRange: ClosedRange<Double>?,
        rationale: String,
        caveat: String,
        migration: [RemediationStep],
        references: [Reference],
        confidence: AlternativeConfidence,
        tags: [String]
    ) {
        self.id = id
        self.bundleIdentifiers = bundleIdentifiers
        self.executableNames = executableNames
        self.alternative = alternative
        self.memorySavingRange = memorySavingRange
        self.cpuSavingRange = cpuSavingRange
        self.rationale = rationale
        self.caveat = caveat
        self.migration = migration
        self.references = references
        self.confidence = confidence
        self.tags = tags
    }

    public func matches(_ app: RunningApplication) -> Bool {
        if let bundleIdentifier = app.bundleIdentifier,
           bundleIdentifiers.contains(where: { $0.caseInsensitiveCompare(bundleIdentifier) == .orderedSame }) {
            return true
        }
        return executableNames.contains { $0.caseInsensitiveCompare(app.name) == .orderedSame }
    }
}

public enum AlternativeCatalog {
    /// The initial catalog is deliberately small: only replacements with a
    /// well-established efficiency difference are included. It is data, not
    /// logic, so it can grow without changing the evaluator.
    public static let entries: [AlternativeEntry] = [
        AlternativeEntry(
            id: "safari-instead-of-chromium",
            bundleIdentifiers: [
                "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
                "org.chromium.Chromium", "com.brave.Browser", "com.brave.Browser.beta",
                "com.microsoft.edgemac", "com.microsoft.edgemac.Beta",
                "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera"
            ],
            executableNames: [
                "Google Chrome", "Chromium", "Brave Browser", "Microsoft Edge", "Arc", "Vivaldi", "Opera"
            ],
            alternative: "Safari",
            memorySavingRange: 0.25...0.45,
            cpuSavingRange: 0.15...0.35,
            rationale: "Chromium browsers ship their own rendering engine, multi-process helpers, updater, and crash reporter. Safari uses WebKit tuned for macOS and Apple silicon, and integrates with the system's power management.",
            caveat: "Safari does not support every Chrome extension, profile, or enterprise policy. Internal sites may be certified only for Chromium, so test your daily tabs before switching.",
            migration: [
                RemediationStep(
                    title: "Export bookmarks",
                    detail: "In the Chromium browser, open the bookmark manager and export an HTML file. Safari can import it.",
                    kind: .manual
                ),
                RemediationStep(
                    title: "Test your daily tabs",
                    detail: "Run both browsers for a day. Keep the Chromium browser for sites or extensions Safari cannot handle.",
                    kind: .manual
                )
            ],
            references: [
                Reference(title: "Apple Support: Safari User Guide", url: "https://support.apple.com/guide/safari/welcome/mac")
            ],
            confidence: .typical,
            tags: ["browser"]
        ),
        AlternativeEntry(
            id: "safari-instead-of-firefox",
            bundleIdentifiers: ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition"],
            executableNames: ["firefox", "Firefox"],
            alternative: "Safari",
            memorySavingRange: 0.15...0.30,
            cpuSavingRange: 0.10...0.25,
            rationale: "Firefox carries its own multi-process engine and updater stack. Safari uses the system WebKit build and is tuned for macOS energy use.",
            caveat: "Some extensions and container workflows are Firefox-only. Check that Safari covers the sites and add-ons you depend on.",
            migration: [
                RemediationStep(
                    title: "Export bookmarks",
                    detail: "Firefox → Bookmarks → Manage Bookmarks → Import and Backup → Export Bookmarks to HTML. Safari can import the file.",
                    kind: .manual
                ),
                RemediationStep(
                    title: "Run both for a day",
                    detail: "Compare the same tabs in Safari and Firefox, then keep the one that fits your workflow.",
                    kind: .manual
                )
            ],
            references: [
                Reference(title: "Apple Support: Safari User Guide", url: "https://support.apple.com/guide/safari/welcome/mac")
            ],
            confidence: .typical,
            tags: ["browser"]
        ),
        AlternativeEntry(
            id: "zed-instead-of-electron-editor",
            bundleIdentifiers: [
                "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders",
                "com.todesktop.230313mzl4w4u92"
            ],
            executableNames: [],
            alternative: "Zed",
            memorySavingRange: 0.30...0.50,
            cpuSavingRange: 0.15...0.30,
            rationale: "Electron editors bundle a Chromium runtime and Node.js with every window. A native editor avoids that per-window runtime overhead.",
            caveat: "Extension ecosystems, debuggers, and language tooling differ. Zed or Xcode may not cover every language or workflow, so keep the current editor until the alternative does.",
            migration: [
                RemediationStep(
                    title: "Try one real project",
                    detail: "Open the same repository in Zed and check language support, formatting, search, and debugging.",
                    kind: .manual
                ),
                RemediationStep(
                    title: "List the extensions you rely on",
                    detail: "If a critical extension is not available, keep the current editor. The goal is a measurable improvement, not a forced switch.",
                    kind: .manual
                )
            ],
            references: [
                Reference(title: "Zed editor", url: "https://zed.dev")
            ],
            confidence: .typical,
            tags: ["editor", "developer"]
        ),
        AlternativeEntry(
            id: "orbstack-instead-of-docker-desktop",
            bundleIdentifiers: ["com.docker.docker"],
            executableNames: ["com.docker.backend", "Docker Desktop", "docker"],
            alternative: "OrbStack",
            memorySavingRange: 0.30...0.50,
            cpuSavingRange: 0.20...0.40,
            rationale: "Docker Desktop runs a Linux VM plus a stack of helper processes. OrbStack uses a lighter VM and native macOS integrations, which usually lowers idle memory and CPU.",
            caveat: "Kubernetes, some volume drivers, and team-specific tooling may require Docker Desktop. Test your Compose files and volumes before removing it.",
            migration: [
                RemediationStep(
                    title: "Install OrbStack",
                    detail: "Run the same containers and Compose files. Keep Docker Desktop installed during the comparison.",
                    kind: .manual
                ),
                RemediationStep(
                    title: "Compare idle footprint",
                    detail: "With no containers running, compare the Docker and OrbStack process groups in Activity Monitor.",
                    command: "open -a 'Activity Monitor'",
                    kind: .command
                ),
                RemediationStep(
                    title: "Keep Docker for unsupported features",
                    detail: "If you rely on a Docker Desktop-only feature, keep it. The finding is a candidate, not a requirement.",
                    kind: .manual
                )
            ],
            references: [
                Reference(title: "OrbStack", url: "https://orbstack.dev")
            ],
            confidence: .typical,
            tags: ["containers", "developer"]
        ),
        AlternativeEntry(
            id: "utm-instead-of-virtualbox",
            bundleIdentifiers: ["org.virtualbox.app.VirtualBox"],
            executableNames: ["VirtualBox", "VBoxHeadless", "VirtualBoxVM"],
            alternative: "UTM",
            memorySavingRange: 0.10...0.25,
            cpuSavingRange: 0.20...0.40,
            rationale: "VirtualBox uses its own virtualization stack and device emulation. UTM can use Apple's Virtualization framework, which is generally lighter for ARM guests on Apple silicon.",
            caveat: "x86 guests need emulation on Apple silicon, and USB or 3D acceleration support differs. Measure the same guest workload before switching.",
            migration: [
                RemediationStep(
                    title: "Check the guest architecture",
                    detail: "ARM guests use the fast virtualization path. Intel guests need emulation and may not be faster in UTM.",
                    kind: .manual
                ),
                RemediationStep(
                    title: "Recreate or import the VM",
                    detail: "Test disk performance, networking, and USB passthrough with the same workload before removing VirtualBox.",
                    kind: .manual
                )
            ],
            references: [
                Reference(title: "UTM virtual machines for Mac", url: "https://mac.getutm.app")
            ],
            confidence: .workloadDependent,
            tags: ["virtualization", "developer"]
        ),
        AlternativeEntry(
            id: "icloud-drive-instead-of-cloud-sync",
            bundleIdentifiers: [
                "com.google.drivefs", "com.getdropbox.dropbox", "com.microsoft.OneDrive"
            ],
            executableNames: ["Google Drive", "GoogleDriveFileStream", "Dropbox", "OneDrive"],
            alternative: "iCloud Drive",
            memorySavingRange: 0.20...0.40,
            cpuSavingRange: 0.10...0.25,
            rationale: "Third-party sync clients run their own indexer, file watcher, and network helpers. iCloud Drive is built into macOS and shares the system's file-provider infrastructure.",
            caveat: "Shared links, selective sync, team folders, and version history differ by provider. iCloud may not replace the collaboration features you actually use.",
            migration: [
                RemediationStep(
                    title: "Enable iCloud Drive",
                    detail: "System Settings → Apple ID → iCloud → iCloud Drive, then move the folders you need.",
                    kind: .settings
                ),
                RemediationStep(
                    title: "Run both during the transition",
                    detail: "Keep the current client until the files are confirmed in iCloud and your collaborators can still reach them.",
                    kind: .manual
                )
            ],
            references: [
                Reference(title: "Apple Support: iCloud User Guide", url: "https://support.apple.com/guide/icloud/welcome/icloud")
            ],
            confidence: .workloadDependent,
            tags: ["sync", "cloud"]
        )
    ]
}

// MARK: - Evaluation

public enum AlternativeEvaluator {
    /// Turns running apps and services into optional, evidence-backed
    /// suggestions. The savings are estimated from the measured footprint and
    /// a conservative fraction, never presented as a benchmark.
    public static func findings(
        applications: [RunningApplication],
        totalMemory: Int64,
        catalog: [AlternativeEntry] = AlternativeCatalog.entries
    ) -> [Finding] {
        let runningBundleIDs = Set(applications.compactMap(\.bundleIdentifier))
        var results: [Finding] = []

        for app in applications {
            guard let entry = catalog.first(where: { $0.matches(app) }) else { continue }

            // If a bundle app already covers this vendor, do not also emit a
            // finding for its standalone helper service.
            if app.bundleIdentifier == nil,
               !Set(entry.bundleIdentifiers).isDisjoint(with: runningBundleIDs) {
                continue
            }

            if let finding = finding(for: app, entry: entry, totalMemory: totalMemory) {
                results.append(finding)
            }
        }

        return results
    }

    private static func finding(
        for app: RunningApplication,
        entry: AlternativeEntry,
        totalMemory: Int64
    ) -> Finding? {
        let memoryGain = entry.memorySavingRange.map { range in
            (low: Int64(Double(app.memoryBytes) * range.lowerBound),
             high: Int64(Double(app.memoryBytes) * range.upperBound))
        }
        let cpuGain = entry.cpuSavingRange.map { range in
            (low: app.cpuPercent * range.lowerBound,
             high: app.cpuPercent * range.upperBound)
        }

        let memoryLow = memoryGain?.low ?? 0
        let cpuLow = cpuGain?.low ?? 0
        let memoryThreshold = max(250 * ByteMath.megabyte, Int64(Double(totalMemory) * 0.02))
        guard memoryLow >= memoryThreshold || cpuLow >= 15 else { return nil }

        let category: ScanCategory = memoryLow >= memoryThreshold ? .memory : .cpu
        let severity: Severity
        if memoryLow >= 1_500 * ByteMath.megabyte || cpuLow >= 80 {
            severity = .medium
        } else {
            severity = .low
        }

        let primaryIsMemory = memoryLow >= memoryThreshold
        var metrics: [Metric] = []
        metrics.append(Metric(
            label: primaryIsMemory ? "Current memory" : "Current CPU",
            value: primaryIsMemory ? Format.bytes(app.memoryBytes) : percent(app.cpuPercent),
            isPrimary: true
        ))
        metrics.append(Metric(label: "Alternative", value: entry.alternative))
        if let memoryGain {
            metrics.append(Metric(label: "Potential memory gain", value: bytesRange(memoryGain)))
        }
        if let cpuGain {
            metrics.append(Metric(label: "Potential CPU gain", value: percentRange(cpuGain)))
        }
        if primaryIsMemory {
            metrics.append(Metric(label: "Current CPU", value: percent(app.cpuPercent)))
        } else {
            metrics.append(Metric(label: "Current memory", value: Format.bytes(app.memoryBytes)))
        }
        metrics.append(Metric(label: "Processes", value: "\(app.processCount)"))
        metrics.append(Metric(label: "Confidence", value: entry.confidence.title))

        let title: String
        if let memoryGain, memoryLow >= memoryThreshold {
            title = "\(app.name) could free \(bytesRange(memoryGain)) with \(entry.alternative)"
        } else if let cpuGain {
            title = "\(app.name) could use \(percentRange(cpuGain)) less CPU with \(entry.alternative)"
        } else {
            return nil
        }

        let summary = "\(app.name) is using \(Format.bytes(app.memoryBytes)) and \(percent(app.cpuPercent)) CPU across \(app.processCount) process\(app.processCount == 1 ? "" : "es"). \(entry.alternative) is typically more efficient on macOS."

        var detail = [entry.rationale]
        detail.append("The gain is an estimate, not a benchmark. Optimizr applies a typical difference to the footprint it measured; your tabs, extensions, project size, and workload can move the result outside this range.")
        if let range = entry.memorySavingRange {
            detail.append("The memory estimate assumes \(percentRange((low: range.lowerBound * 100, high: range.upperBound * 100))) of the current footprint.")
        }
        if let range = entry.cpuSavingRange {
            detail.append("The CPU estimate assumes \(percentRange((low: range.lowerBound * 100, high: range.upperBound * 100))) of the current CPU use.")
        }
        detail.append(entry.caveat)

        var steps = entry.migration
        steps.append(RemediationStep(
            title: "Compare under the same workload",
            detail: "Run both options with the same tabs, project, containers, or files. Compare memory and CPU in Activity Monitor before deciding.",
            command: "open -a 'Activity Monitor'",
            kind: .command
        ))
        steps.append(RemediationStep(
            title: "Keep the old app until the alternative covers you",
            detail: "Do not remove the current app until your extensions, files, and collaboration needs work in the alternative.",
            kind: .manual
        ))

        let id = "\(category.rawValue).alternative.\(entry.id).\(slug(app.bundleIdentifier ?? app.name))"

        return Finding(
            id: id,
            category: category,
            title: title,
            summary: summary,
            detail: detail.joined(separator: "\n\n"),
            severity: severity,
            scope: .mixed,
            reclaimableBytes: nil,
            metrics: metrics,
            remediation: steps,
            references: entry.references,
            paths: app.path.map { [$0] } ?? [],
            tags: ["alternative", "efficiency"] + entry.tags
        )
    }

    private static func bytesRange(_ range: (low: Int64, high: Int64)) -> String {
        "\(Format.bytes(range.low))–\(Format.bytes(range.high))"
    }

    private static func percentRange(_ range: (low: Double, high: Double)) -> String {
        "\(Int(range.low.rounded()))–\(Int(range.high.rounded()))%"
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    private static func slug(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
