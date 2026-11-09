import Foundation

/// A scanner owns one category and is safe to run alongside the others.
public protocol OptimizrScanner: Sendable {
    var category: ScanCategory { get }
    func scan() -> [Finding]
}

// MARK: - Memory

public struct MemoryScanner: OptimizrScanner {
    public let category: ScanCategory = .memory
    private let runner: any CommandRunning

    public init(runner: any CommandRunning = ShellCommandRunner()) {
        self.runner = runner
    }

    public func scan() -> [Finding] {
        var findings: [Finding] = []

        let vmOutput = runner.run("/usr/bin/vm_stat", arguments: [], timeout: 5)
        let vm = VMStatistics.parse(vmOutput.stdout)

        let swapOutput = runner.run("/usr/sbin/sysctl", arguments: ["-n", "vm.swapusage"], timeout: 3)
        let swap = SwapUsage.parse(swapOutput.stdout)

        let pressureOutput = runner.run("/usr/bin/memory_pressure", arguments: [], timeout: 5)
        let freePercent = MemoryPressureParser.parseFreePercentage(pressureOutput.stdout)

        let psOutput = runner.run("/bin/ps", arguments: ["-axo", "pid=,rss=,pcpu=,comm="], timeout: 8)
        let processes = ProcessSampleParser.parse(psOutput.stdout)
        let totalMemory = Int64(ProcessInfo.processInfo.physicalMemory)

        let usedFraction = min(1, max(0, 1 - (freePercent ?? 52) / 100))
        let swapFraction = swap?.usedFraction ?? 0
        let pressure = min(1, max(0, usedFraction * 0.55 + swapFraction * 0.45))

        findings.append(contentsOf: pressureFindings(
            pressure: pressure,
            freePercent: freePercent ?? (1 - usedFraction) * 100,
            vm: vm,
            swap: swap,
            totalMemory: totalMemory
        ))

        if let swap, swap.usedBytes > 536_870_912 {
            findings.append(swapFinding(swap: swap, totalMemory: totalMemory))
        }

        if let top = processes.max(by: { $0.memoryBytes < $1.memoryBytes }),
           let finding = topConsumerFinding(process: top, totalMemory: totalMemory, processes: processes) {
            findings.append(finding)
        }

        if let vm, totalMemory > 0 {
            let compressedFraction = Double(vm.compressedBytes) / Double(totalMemory)
            if compressedFraction > 0.15 {
                findings.append(compressionFinding(vm: vm, totalMemory: totalMemory, fraction: compressedFraction))
            }
        }

        return findings
    }

    private func pressureFindings(
        pressure: Double,
        freePercent: Double,
        vm: VMStatistics?,
        swap: SwapUsage?,
        totalMemory: Int64
    ) -> [Finding] {
        guard pressure >= 0.35 else { return [] }

        let severity: Severity
        switch pressure {
        case 0.85...: severity = .critical
        case 0.70..<0.85: severity = .high
        case 0.50..<0.70: severity = .medium
        default: severity = .low
        }

        var metrics: [Metric] = [
            Metric(label: "Pressure", value: String(format: "%.0f%%", pressure * 100), isPrimary: true),
            Metric(label: "Memory free", value: String(format: "%.0f%%", freePercent)),
            Metric(label: "Physical memory", value: Format.bytes(totalMemory))
        ]
        if let swap {
            metrics.append(Metric(label: "Swap used", value: Format.bytes(swap.usedBytes)))
        }
        if let vm {
            metrics.append(Metric(label: "Compressed", value: Format.bytes(vm.compressedBytes)))
        }

        var steps: [RemediationStep] = [
            RemediationStep(
                title: "Quit the heaviest apps",
                detail: "Close apps you are not actively using, starting with browsers, Electron apps, and virtual machines. On macOS, quitting an app releases its memory; closing its window usually does not.",
                kind: .manual
            ),
            RemediationStep(
                title: "Inspect memory in Activity Monitor",
                detail: "Open Activity Monitor, select the Memory tab, and sort by Memory. The top processes are the ones driving pressure.",
                command: "open -a 'Activity Monitor'",
                kind: .command
            ),
            RemediationStep(
                title: "Restart the Mac",
                detail: "A restart clears swap, compressed memory, and stale caches. This is the highest-leverage fix when pressure is elevated.",
                kind: .restart
            )
        ]

        if let swap, swap.usedFraction > 0.5 {
            steps.insert(
                RemediationStep(
                    title: "Close and reopen memory-heavy apps",
                    detail: "Apps that have been open for days often hold memory they no longer need. Quitting and reopening them is often enough to shrink swap.",
                    kind: .manual
                ),
                at: 1
            )
        }

        return [Finding(
            id: "memory.pressure",
            category: .memory,
            title: "Memory pressure is \(String(format: "%.0f%%", pressure * 100))",
            summary: "macOS is under \(pressureLabel(pressure).lowercased()) memory pressure. Apps are being compressed and pushed to swap, which makes switching apps and opening new windows feel slow.",
            detail: memoryPressureDetail(pressure: pressure, swap: swap, vm: vm),
            severity: severity,
            scope: .native,
            metrics: metrics,
            remediation: steps,
            references: [
                Reference(title: "Apple Support: If your Mac is using a lot of memory", url: "https://support.apple.com/guide/activity-monitor/check-if-your-mac-is-using-too-much-memory-actmntr1002/mac"),
                Reference(title: "Apple Support: Change your Mac's memory pressure", url: "https://support.apple.com/en-us/102619")
            ],
            tags: ["swap", "activity-monitor"]
        )]
    }

    private func pressureLabel(_ value: Double) -> String {
        switch value {
        case 0.85...: return "severe"
        case 0.70..<0.85: return "high"
        case 0.50..<0.70: return "elevated"
        default: return "moderate"
        }
    }

    private func memoryPressureDetail(pressure: Double, swap: SwapUsage?, vm: VMStatistics?) -> String {
        var parts: [String] = []
        parts.append("Memory pressure is a better signal than \"free memory\" alone. macOS deliberately uses available RAM for caches, so a Mac with little free memory can still be healthy — but when pressure rises, the system starts compressing pages and writing them to swap.")
        if let swap, swap.usedBytes > 0 {
            parts.append("Swap currently holds \(Format.bytes(swap.usedBytes)). Reading it back is orders of magnitude slower than reading RAM, so heavy swap use shows up as spinning cursors, slow app switching, and laggy menus.")
        }
        if let vm, vm.compressedBytes > 0 {
            parts.append("The compressor is holding \(Format.bytes(vm.compressedBytes)) of memory. Compression saves space but costs CPU time on every access.")
        }
        if pressure >= 0.85 {
            parts.append("This is severe. Quit large apps now and restart when you can; the system is spending significant time managing memory instead of running your work.")
        }
        return parts.joined(separator: "\n\n")
    }

    private func swapFinding(swap: SwapUsage, totalMemory: Int64) -> Finding {
        let used = swap.usedBytes
        let severity: Severity
        if used >= 8 * ByteMath.gigabyte || swap.usedFraction >= 0.80 {
            severity = .critical
        } else if used >= 4 * ByteMath.gigabyte || swap.usedFraction >= 0.55 {
            severity = .high
        } else if used >= 1 * ByteMath.gigabyte || swap.usedFraction >= 0.25 {
            severity = .medium
        } else {
            severity = .low
        }

        return Finding(
            id: "memory.swap",
            category: .memory,
            title: "Swap is holding \(Format.bytes(used))",
            summary: "\(Format.percent(swap.usedFraction)) of the swap file is in use. Memory that does not fit in RAM is being written to disk and read back on demand.",
            detail: "Swap is a safety valve, not a problem by itself — but sustained swap use means your working set is larger than physical memory. On a \(Format.bytes(totalMemory)) Mac, \(Format.bytes(used)) of swap indicates that apps are competing for RAM. The fix is to reduce concurrent memory use, not to \"clear\" swap with a cleaner utility; macOS manages the swap file itself.",
            severity: severity,
            scope: .native,
            reclaimableBytes: nil,
            metrics: [
                Metric(label: "Swap used", value: Format.bytes(swap.usedBytes), isPrimary: true),
                Metric(label: "Swap total", value: Format.bytes(swap.totalBytes)),
                Metric(label: "Swap free", value: Format.bytes(swap.freeBytes)),
                Metric(label: "RAM", value: Format.bytes(totalMemory))
            ],
            remediation: [
                RemediationStep(
                    title: "Find the apps that are swapping",
                    detail: "In Activity Monitor's Memory tab, sort by Memory and look for apps with a large memory footprint. Quit the ones you are not using.",
                    command: "open -a 'Activity Monitor'",
                    kind: .command
                ),
                RemediationStep(
                    title: "Restart to reset the working set",
                    detail: "A restart clears swap and compressed memory. It is the only reliable way to make macOS hand the swap file back.",
                    kind: .restart
                ),
                RemediationStep(
                    title: "Leave fewer apps running",
                    detail: "Browsers with many tabs and Electron apps are common culprits. Suspend or quit them instead of leaving them open for days.",
                    kind: .manual
                )
            ],
            references: [
                Reference(title: "Apple Support: About memory pressure", url: "https://support.apple.com/en-us/102619")
            ],
            tags: ["swap"]
        )
    }

    private func topConsumerFinding(process: ProcessSample, totalMemory: Int64, processes: [ProcessSample]) -> Finding? {
        guard totalMemory > 0 else { return nil }
        let fraction = Double(process.memoryBytes) / Double(totalMemory)
        guard fraction >= 0.10, process.memoryBytes >= 1 * ByteMath.gigabyte else { return nil }

        let severity: Severity
        switch fraction {
        case 0.40...: severity = .critical
        case 0.25..<0.40: severity = .high
        case 0.15..<0.25: severity = .medium
        default: severity = .low
        }

        let top = processes
            .sorted { $0.memoryBytes > $1.memoryBytes }
            .prefix(5)

        return Finding(
            id: "memory.top-process",
            category: .memory,
            title: "\(process.displayName) is using \(Format.bytes(process.memoryBytes))",
            summary: "The largest memory consumer on this Mac holds \(Format.percent(fraction)) of physical RAM. Its footprint is large enough to affect overall memory pressure.",
            detail: "Process \(process.pid) reports a resident set size of \(Format.bytes(process.memoryBytes)). RSS includes memory shared with other processes, so it is an upper-bound estimate, but a footprint this large still makes the app a good candidate to restart or quit when not in use.",
            severity: severity,
            scope: .mixed,
            metrics: top.map { sample in
                Metric(
                    label: "\(sample.displayName) · PID \(sample.pid)",
                    value: Format.bytes(sample.memoryBytes),
                    isPrimary: sample.pid == process.pid
                )
            },
            remediation: [
                RemediationStep(
                    title: "Quit the app when not in use",
                    detail: "Use the app's own Quit command (⌘Q) rather than closing its window. Many apps keep running in the background.",
                    kind: .manual
                ),
                RemediationStep(
                    title: "Restart the app",
                    detail: "If the footprint grows over time, quit and reopen it. That releases its heap and any leaked memory.",
                    kind: .manual
                ),
                RemediationStep(
                    title: "Force quit as a last resort",
                    detail: "If the app is unresponsive and will not quit normally, force quit it from the Apple menu (⌥⌘⎋). Unsaved work may be lost.",
                    command: "kill \(process.pid)",
                    kind: .command
                )
            ],
            tags: ["process", "rss"]
        )
    }

    private func compressionFinding(vm: VMStatistics, totalMemory: Int64, fraction: Double) -> Finding {
        let severity: Severity = fraction >= 0.40 ? .high : (fraction >= 0.25 ? .medium : .low)
        return Finding(
            id: "memory.compressor",
            category: .memory,
            title: "Compressed memory is \(Format.bytes(vm.compressedBytes))",
            summary: "\(Format.percent(fraction)) of physical RAM is occupied by compressed pages. Every access to those pages costs CPU time to decompress.",
            detail: "The memory compressor is doing its job: it is squeezing inactive pages instead of swapping them to disk. When compressed memory grows this large, though, the CPU overhead of decompression becomes noticeable. Reducing the number of open apps is the most direct fix.",
            severity: severity,
            scope: .native,
            metrics: [
                Metric(label: "Compressed", value: Format.bytes(vm.compressedBytes), isPrimary: true),
                Metric(label: "Share of RAM", value: Format.percent(fraction)),
                Metric(label: "RAM", value: Format.bytes(totalMemory))
            ],
            remediation: [
                RemediationStep(
                    title: "Reduce open apps",
                    detail: "Quit apps you are not using. The compressor will release pages as pressure falls.",
                    kind: .manual
                ),
                RemediationStep(
                    title: "Restart to reset compression",
                    detail: "A restart clears the compressor and swap, returning the Mac to a clean baseline.",
                    kind: .restart
                )
            ],
            tags: ["compressor"]
        )
    }
}

// MARK: - CPU

public struct CPUScanner: OptimizrScanner {
    public let category: ScanCategory = .cpu
    private let runner: any CommandRunning

    public init(runner: any CommandRunning = ShellCommandRunner()) {
        self.runner = runner
    }

    public func scan() -> [Finding] {
        var findings: [Finding] = []

        let loadOutput = runner.run("/usr/sbin/sysctl", arguments: ["-n", "vm.loadavg"], timeout: 3)
        let loads = LoadAverageParser.parse(loadOutput.stdout)
        let cores = max(1, ProcessInfo.processInfo.processorCount)
        let uptime = ProcessInfo.processInfo.systemUptime

        let psOutput = runner.run("/bin/ps", arguments: ["-axo", "pid=,rss=,pcpu=,comm="], timeout: 8)
        let processes = ProcessSampleParser.parse(psOutput.stdout)

        let thermalOutput = runner.run("/usr/bin/pmset", arguments: ["-g", "therm"], timeout: 3)
        let thermal = ThermalState.parse(thermalOutput.stdout)

        let powerOutput = runner.run("/usr/bin/pmset", arguments: ["-g"], timeout: 3)

        findings.append(contentsOf: loadFindings(loads: loads, cores: cores, processes: processes))
        findings.append(contentsOf: processFindings(processes: processes))
        if thermal.isThrottled {
            findings.append(thermalFinding(thermal))
        }
        if PowerSettingsParser.lowPowerModeEnabled(powerOutput.stdout) {
            findings.append(lowPowerModeFinding())
        }

        let launchItems = LaunchItemInventory.scan()
        if launchItems.count >= 6 {
            findings.append(launchItemsFinding(items: launchItems))
        }

        if uptime > 14 * 86_400 {
            findings.append(longUptimeFinding(uptime: uptime))
        }

        return findings
    }

    private func loadFindings(loads: [Double], cores: Int, processes: [ProcessSample]) -> [Finding] {
        guard let load1 = loads.first else { return [] }
        let perCore = load1 / Double(cores)
        guard perCore >= 0.70 else { return [] }

        let severity: Severity
        switch perCore {
        case 2.0...: severity = .critical
        case 1.3..<2.0: severity = .high
        case 0.9..<1.3: severity = .medium
        default: severity = .low
        }

        let metrics: [Metric] = [
            Metric(label: "Load (1 min)", value: Format.decimal(load1), isPrimary: true),
            Metric(label: "Per core", value: Format.decimal(perCore)),
            Metric(label: "Cores", value: "\(cores)"),
            Metric(label: "Load (5 min)", value: Format.decimal(loads.count > 1 ? loads[1] : 0)),
            Metric(label: "Load (15 min)", value: Format.decimal(loads.count > 2 ? loads[2] : 0))
        ]

        var steps: [RemediationStep] = [
            RemediationStep(
                title: "Find the busiest processes",
                detail: "Open Activity Monitor, sort the CPU tab by % CPU. Sustained values above 100% mean a process is using more than one core.",
                command: "open -a 'Activity Monitor'",
                kind: .command
            ),
            RemediationStep(
                title: "Quit or pause background work",
                detail: "Exports, builds, indexers, backups, and browser tabs with heavy scripts are common causes. Pause them if they are not urgent.",
                kind: .manual
            ),
            RemediationStep(
                title: "Check login items",
                detail: "Background agents can wake up and consume CPU without a visible window. Review System Settings → General → Login Items & Extensions.",
                kind: .settings
            )
        ]
        if perCore >= 1.3 {
            steps.append(RemediationStep(
                title: "Give the Mac a moment",
                detail: "If a single task is legitimately using all cores, letting it finish is usually better than killing it. A restart is the fallback if load does not fall.",
                kind: .restart
            ))
        }

        return [Finding(
            id: "cpu.load",
            category: .cpu,
            title: "System load is \(Format.decimal(perCore))× per core",
            summary: "The 1-minute load average is \(Format.decimal(load1)) across \(cores) cores. Processes are waiting for CPU time, so the Mac will feel less responsive.",
            detail: "Load average counts runnable and uninterruptible processes. A value near the number of cores means the CPU is fully booked; values above it mean work is queueing. The top CPU consumers are listed in the evidence, and prolonged high load can also raise temperatures and trigger throttling.",
            severity: severity,
            scope: .native,
            metrics: metrics,
            remediation: steps,
            references: [
                Reference(title: "Apple Support: Activity Monitor CPU", url: "https://support.apple.com/guide/activity-monitor/view-cpu-activity-actmntr1002/mac")
            ],
            tags: ["load-average"]
        )]
    }

    private func processFindings(processes: [ProcessSample]) -> [Finding] {
        let top = processes
            .filter { $0.cpuPercent >= 40 && $0.name != "ps" }
            .sorted { $0.cpuPercent > $1.cpuPercent }
        guard let leader = top.first else { return [] }

        let severity: Severity
        switch leader.cpuPercent {
        case 250...: severity = .high
        case 120..<250: severity = .medium
        default: severity = .low
        }

        let metrics = top.prefix(5).map { sample in
            Metric(
                label: "\(sample.displayName) · PID \(sample.pid)",
                value: String(format: "%.1f%%", sample.cpuPercent),
                isPrimary: sample.pid == leader.pid
            )
        }

        return [Finding(
            id: "cpu.top-process",
            category: .cpu,
            title: "\(leader.displayName) is using \(String(format: "%.0f%%", leader.cpuPercent)) CPU",
            summary: "One process is consuming a large share of the available CPU. Values above 100% mean it is using more than one core.",
            detail: "CPU percentages from `ps` are sampled over the process lifetime, not an instant, so treat them as a strong hint rather than a precise reading. If this process has been busy for a while, quitting or restarting it will usually return the CPU to idle.",
            severity: severity,
            scope: .mixed,
            metrics: Array(metrics),
            remediation: [
                RemediationStep(
                    title: "Quit the app if it is not needed",
                    detail: "Use the app's Quit command. If the process is a helper, quit the parent app instead.",
                    kind: .manual
                ),
                RemediationStep(
                    title: "Restart the process",
                    detail: "Some helpers keep working after their parent app is closed. Restart the app or the Mac to clear them.",
                    kind: .restart
                ),
                RemediationStep(
                    title: "Inspect open files and connections",
                    detail: "To see what a process is doing, use Activity Monitor's Open Files and Ports panel (gear menu → Sample Process for a stack sample).",
                    command: "open -a 'Activity Monitor'",
                    kind: .command
                )
            ],
            tags: ["process", "cpu"]
        )]
    }

    private func thermalFinding(_ thermal: ThermalState) -> Finding {
        let limit = thermal.speedLimit ?? 100
        let severity: Severity = limit < 70 ? .high : .medium
        var metrics = [Metric(
            label: "CPU speed limit",
            value: "\(limit)%",
            isPrimary: true
        )]
        if let warning = thermal.thermalWarningLevel {
            metrics.append(Metric(label: "Thermal warning", value: "\(warning)"))
        }

        return Finding(
            id: "cpu.thermal",
            category: .cpu,
            title: "The CPU is thermally throttled to \(limit)%",
            summary: "macOS is limiting CPU speed to keep the chip within a safe temperature range. Sustained throttling means less performance for the same workload.",
            detail: "Throttling is normal during short bursts, but sustained limits below 100% usually mean the cooling system is struggling. Common causes are a heavy workload in a warm room, blocked vents, or dust build-up on an older Mac.",
            severity: severity,
            scope: .native,
            metrics: metrics,
            remediation: [
                RemediationStep(
                    title: "Let the Mac cool down",
                    detail: "Stop heavy exports or builds temporarily and give the fans a chance to catch up.",
                    kind: .manual
                ),
                RemediationStep(
                    title: "Improve airflow",
                    detail: "Use the Mac on a hard surface, keep vents unobstructed, and avoid direct sunlight or soft bedding.",
                    kind: .manual
                ),
                RemediationStep(
                    title: "Inspect thermal history",
                    detail: "Review the thermal log to see whether the throttling is sustained or just a short spike.",
                    command: "pmset -g thermlog",
                    kind: .command
                )
            ],
            references: [
                Reference(title: "Apple Support: Keep your Mac laptop within acceptable operating temperatures", url: "https://support.apple.com/en-us/102295")
            ],
            tags: ["thermal", "throttling"]
        )
    }

    private func lowPowerModeFinding() -> Finding {
        Finding(
            id: "cpu.low-power-mode",
            category: .cpu,
            title: "Low Power Mode is enabled",
            summary: "macOS is reducing background activity and peak performance to save battery. That is a feature — but it is also why some tasks feel slower.",
            detail: "Low Power Mode reduces display brightness, background refreshes, and CPU boost. On a laptop running on battery it is often the right trade-off. If you are plugged in and want maximum performance, turn it off.",
            severity: .info,
            scope: .native,
            metrics: [Metric(label: "Mode", value: "Low Power", isPrimary: true)],
            remediation: [
                RemediationStep(
                    title: "Turn it off in Battery settings",
                    detail: "Open System Settings → Battery and set \"Low Power Mode\" to Never, or use Control Center.",
                    kind: .settings
                ),
                RemediationStep(
                    title: "Or disable it from the command line",
                    detail: "Requires an administrator password.",
                    command: "sudo pmset -a lowpowermode 0",
                    kind: .command
                )
            ],
            tags: ["power", "battery"]
        )
    }

    private func launchItemsFinding(items: [LaunchItem]) -> Finding {
        let severity: Severity
        switch items.count {
        case 20...: severity = .high
        case 10..<20: severity = .medium
        default: severity = .low
        }

        let byScope = Dictionary(grouping: items, by: \.scope)
        var metrics: [Metric] = [
            Metric(label: "Third-party items", value: "\(items.count)", isPrimary: true)
        ]
        for scope in LaunchItemScope.allCases {
            let count = byScope[scope]?.count ?? 0
            if count > 0 {
                metrics.append(Metric(label: scope.title + "s", value: "\(count)"))
            }
        }
        for item in items.prefix(8) {
            metrics.append(Metric(label: item.vendor, value: item.label))
        }

        return Finding(
            id: "cpu.launch-items",
            category: .cpu,
            title: "\(items.count) third-party background items are installed",
            summary: "Login agents and daemons launch automatically and can wake up to consume CPU, memory, and battery even when you are not using the app.",
            detail: "Each launch agent is a small service with its own schedule. Individually they are cheap; collectively they cause background CPU spikes and prevent the Mac from idling. Review the list and disable updaters or helpers for apps you no longer use. Do not remove Apple's own services.",
            severity: severity,
            scope: .thirdParty,
            metrics: metrics,
            remediation: [
                RemediationStep(
                    title: "Review login items in System Settings",
                    detail: "Open System Settings → General → Login Items & Extensions. Disable or remove items you do not recognize or no longer need.",
                    kind: .settings
                ),
                RemediationStep(
                    title: "Inspect the third-party agents on disk",
                    detail: "The finding's relevant locations list every plist Optimizr found. Reveal them in Finder before making changes.",
                    command: "ls -1 ~/Library/LaunchAgents /Library/LaunchAgents /Library/LaunchDaemons",
                    kind: .command
                ),
                RemediationStep(
                    title: "Unload instead of deleting",
                    detail: "If you need to disable an agent temporarily, unload it with launchctl. Prefer the app's own uninstaller for permanent removal.",
                    command: "launchctl print gui/$(id -u)",
                    kind: .command
                )
            ],
            references: [
                Reference(title: "Apple Support: Manage login items", url: "https://support.apple.com/guide/mac-help/control-accessibility-features-mh35828/mac")
            ],
            paths: items.map(\.path),
            tags: ["launchd", "background"]
        )
    }

    private func longUptimeFinding(uptime: TimeInterval) -> Finding {
        let days = Int(uptime / 86_400)
        let severity: Severity = days >= 30 ? .medium : .low
        return Finding(
            id: "cpu.uptime",
            category: .cpu,
            title: "This Mac has not restarted in \(days) days",
            summary: "Long uptimes let memory grow, stale background services accumulate, and pending system updates wait. A restart is the simplest tune-up.",
            detail: "macOS is stable enough to run for weeks, but apps and helpers leak memory over time. Pending security updates also require a restart to take effect. Restarting is quick and resolves several findings at once.",
            severity: severity,
            scope: .native,
            metrics: [
                Metric(label: "Uptime", value: Format.uptime(uptime), isPrimary: true),
                Metric(label: "Days", value: "\(days)")
            ],
            remediation: [
                RemediationStep(
                    title: "Save your work and restart",
                    detail: "Use the Apple menu → Restart. Uncheck \"Reopen windows when logging back in\" for a cleaner baseline.",
                    kind: .restart
                ),
                RemediationStep(
                    title: "Check for pending updates",
                    detail: "Install software updates before restarting so the reboot does double duty.",
                    command: "softwareupdate -l",
                    kind: .command
                )
            ],
            tags: ["uptime", "restart"]
        )
    }
}

// MARK: - Storage

public struct StorageScanner: OptimizrScanner {
    public let category: ScanCategory = .storage
    private let runner: any CommandRunning

    public init(runner: any CommandRunning = ShellCommandRunner()) {
        self.runner = runner
    }

    public func scan() -> [Finding] {
        var findings: [Finding] = []

        let total = diskCapacity().total
        let free = diskCapacity().free
        if total > 0 {
            let freeFraction = Double(free) / Double(total)
            if freeFraction < 0.15 {
                findings.append(lowDiskSpaceFinding(total: total, free: free))
            }
        }

        findings.append(contentsOf: directoryFindings())
        findings.append(contentsOf: largeFileFindings())
        if let protectedApps = protectedAppsFinding() {
            findings.append(protectedApps)
        }
        if let snapshotFinding = localSnapshotsFinding() {
            findings.append(snapshotFinding)
        }

        return findings
    }

    private func diskCapacity() -> (total: Int64, free: Int64) {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: "/") else {
            return (0, 0)
        }
        let total = (attributes[.systemSize] as? NSNumber)?.int64Value ?? 0
        let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        return (total, free)
    }

    private func lowDiskSpaceFinding(total: Int64, free: Int64) -> Finding {
        let freeFraction = Double(free) / Double(max(1, total))
        let severity: Severity
        switch freeFraction {
        case ..<0.05: severity = .critical
        case ..<0.10: severity = .high
        default: severity = .medium
        }

        return Finding(
            id: "storage.disk-space",
            category: .storage,
            title: "Only \(Format.bytes(free)) of \(Format.bytes(total)) is free",
            summary: "The startup disk is \(Format.percent(1 - freeFraction)) full. Below roughly 10% free, macOS has less room for swap, updates, and temporary files.",
            detail: "APFS needs free space to write, snapshot, and update files. A nearly full disk can slow the whole system — including memory pressure, because swap needs room. The storage findings below show where the space went. Clear the largest safe items first, then empty the Trash so the space is actually released.",
            severity: severity,
            scope: .native,
            metrics: [
                Metric(label: "Free", value: Format.bytes(free), isPrimary: true),
                Metric(label: "Used", value: Format.bytes(total - free)),
                Metric(label: "Total", value: Format.bytes(total)),
                Metric(label: "Free share", value: Format.percent(freeFraction, decimals: 1))
            ],
            remediation: [
                RemediationStep(
                    title: "Review the storage findings below",
                    detail: "Start with caches, Xcode build products, old simulators, and large files. Each finding lists a safe command and the relevant folder.",
                    kind: .manual
                ),
                RemediationStep(
                    title: "Empty the Trash",
                    detail: "Deleting files does not free space until the Trash is emptied.",
                    command: "rm -rf ~/.Trash/*",
                    kind: .command
                ),
                RemediationStep(
                    title: "Open Storage settings",
                    detail: "System Settings → General → Storage offers Apple's recommendations and a breakdown by category.",
                    command: "open 'x-apple.systempreferences:com.apple.settings.Storage'",
                    kind: .settings
                )
            ],
            references: [
                Reference(title: "Apple Support: Free up storage space", url: "https://support.apple.com/en-us/102624")
            ],
            tags: ["disk", "capacity"]
        )
    }

    // MARK: Directory targets

    private struct DirectoryTarget {
        let id: String
        let title: String
        let summary: String
        let detail: String
        let scope: FindingScope
        let url: URL
        let reportThreshold: Int64
        let highThreshold: Int64
        let criticalThreshold: Int64
        let remediation: [RemediationStep]
        let references: [Reference]
        let tags: [String]
    }

    private func directoryFindings() -> [Finding] {
        let caches = Paths.home("Library/Caches")
        let homebrew = Paths.home("Library/Caches/Homebrew")
        let derivedData = Paths.home("Library/Developer/Xcode/DerivedData")
        let deviceSupport = Paths.home("Library/Developer/Xcode/iOS DeviceSupport")
        let archives = Paths.home("Library/Developer/Xcode/Archives")
        let simulators = Paths.home("Library/Developer/CoreSimulator/Devices")
        let backups = Paths.home("Library/Application Support/MobileSync/Backup")
        let trash = Paths.home(".Trash")
        let docker = Paths.home("Library/Containers/com.docker.docker")

        let targets: [DirectoryTarget] = [
            DirectoryTarget(
                id: "storage.app-caches",
                title: "App caches",
                summary: "Apps store replayable data in ~/Library/Caches so they can start faster. It is safe to clear, though apps rebuild it.",
                detail: "Caches are designed to be disposable. macOS and individual apps recreate them on demand. Quit open apps before clearing caches to avoid a half-written state, and expect the first launch afterward to feel slower.",
                scope: .mixed,
                url: caches,
                reportThreshold: 1 * ByteMath.gigabyte,
                highThreshold: 5 * ByteMath.gigabyte,
                criticalThreshold: 15 * ByteMath.gigabyte,
                remediation: [
                    RemediationStep(
                        title: "Reveal the cache folder",
                        detail: "Inspect the contents first. You can delete individual app folders instead of everything at once.",
                        command: "open ~/Library/Caches",
                        kind: .command
                    ),
                    RemediationStep(
                        title: "Clear caches",
                        detail: "Quit apps first. macOS recreates cache data as needed; the first launch after clearing may be slower.",
                        command: "rm -rf ~/Library/Caches/*",
                        kind: .command
                    )
                ],
                references: [],
                tags: ["caches"]
            ),
            DirectoryTarget(
                id: "storage.homebrew",
                title: "Homebrew download cache",
                summary: "Homebrew keeps downloaded bottles and source archives so reinstalls are fast. They are not needed after installation.",
                detail: "The Homebrew cache can grow to many gigabytes and is never used by installed packages. `brew cleanup` removes old versions and the download cache; it is reversible by downloading again.",
                scope: .thirdParty,
                url: homebrew,
                reportThreshold: 500 * ByteMath.megabyte,
                highThreshold: 2 * ByteMath.gigabyte,
                criticalThreshold: 5 * ByteMath.gigabyte,
                remediation: [
                    RemediationStep(
                        title: "Prune Homebrew",
                        detail: "Removes stale downloads and old versions of installed formulae.",
                        command: "brew cleanup --prune=all",
                        kind: .command
                    ),
                    RemediationStep(
                        title: "Inspect the cache",
                        detail: "Review what is cached before deleting it manually.",
                        command: "open ~/Library/Caches/Homebrew",
                        kind: .command
                    )
                ],
                references: [],
                tags: ["homebrew", "developer"]
            ),
            DirectoryTarget(
                id: "storage.xcode-derived-data",
                title: "Xcode DerivedData",
                summary: "Intermediate build products and indexes. Xcode recreates them the next time you build.",
                detail: "DerivedData is one of the safest large developer caches to remove. Xcode rebuilds it automatically. The first build after clearing will take longer because indexes and object files are missing.",
                scope: .native,
                url: derivedData,
                reportThreshold: 1 * ByteMath.gigabyte,
                highThreshold: 5 * ByteMath.gigabyte,
                criticalThreshold: 15 * ByteMath.gigabyte,
                remediation: [
                    RemediationStep(
                        title: "Clear DerivedData",
                        detail: "Quit Xcode first, then remove the build products. Xcode will recreate them.",
                        command: "rm -rf ~/Library/Developer/Xcode/DerivedData/*",
                        kind: .command
                    )
                ],
                references: [],
                tags: ["xcode", "developer"]
            ),
            DirectoryTarget(
                id: "storage.xcode-device-support",
                title: "iOS DeviceSupport files",
                summary: "Debug symbols and support files for every iOS version you have connected. Old versions are usually safe to remove.",
                detail: "Each iOS release adds a DeviceSupport folder. Once you no longer debug on that OS version, the folder is dead weight. Keep the versions of devices you still test with.",
                scope: .native,
                url: deviceSupport,
                reportThreshold: 2 * ByteMath.gigabyte,
                highThreshold: 10 * ByteMath.gigabyte,
                criticalThreshold: 20 * ByteMath.gigabyte,
                remediation: [
                    RemediationStep(
                        title: "Inspect versions",
                        detail: "Folders are named by iOS version. Remove the ones for devices and OS versions you no longer use.",
                        command: "ls -lh ~/Library/Developer/Xcode/iOS\\ DeviceSupport",
                        kind: .command
                    ),
                    RemediationStep(
                        title: "Remove old versions",
                        detail: "Connect a device and Xcode will regenerate the folder for its current iOS version.",
                        command: "rm -rf ~/Library/Developer/Xcode/iOS\\ DeviceSupport/*",
                        kind: .command
                    )
                ],
                references: [],
                tags: ["xcode", "developer", "ios"]
            ),
            DirectoryTarget(
                id: "storage.xcode-archives",
                title: "Xcode archives",
                summary: "Archived builds kept for App Store submission and symbolication. Old archives are often the largest Xcode artifact.",
                detail: "Archives contain the app binary and dSYMs for a shipped build. Keep archives you may still need for crash symbolication or resubmission. Delete ones for apps or versions you no longer support.",
                scope: .native,
                url: archives,
                reportThreshold: 1 * ByteMath.gigabyte,
                highThreshold: 5 * ByteMath.gigabyte,
                criticalThreshold: 15 * ByteMath.gigabyte,
                remediation: [
                    RemediationStep(
                        title: "Open Xcode Organizer",
                        detail: "Xcode → Window → Organizer → Archives lets you review and delete archives safely.",
                        kind: .settings
                    ),
                    RemediationStep(
                        title: "Reveal the archive folder",
                        detail: "Inspect the archive dates before deleting from Finder.",
                        command: "open ~/Library/Developer/Xcode/Archives",
                        kind: .command
                    )
                ],
                references: [],
                tags: ["xcode", "developer"]
            ),
            DirectoryTarget(
                id: "storage.simulators",
                title: "Simulator devices",
                summary: "Every iOS and watchOS simulator you have created keeps its own data, apps, and screenshots.",
                detail: "Simulators are useful, but old or unavailable devices pile up. `xcrun simctl delete unavailable` removes devices whose runtime is no longer installed. You can also erase individual simulators in Xcode's Devices window.",
                scope: .native,
                url: simulators,
                reportThreshold: 3 * ByteMath.gigabyte,
                highThreshold: 10 * ByteMath.gigabyte,
                criticalThreshold: 25 * ByteMath.gigabyte,
                remediation: [
                    RemediationStep(
                        title: "Delete unavailable simulators",
                        detail: "Removes devices whose runtime has been uninstalled.",
                        command: "xcrun simctl delete unavailable",
                        kind: .command
                    ),
                    RemediationStep(
                        title: "Review devices in Xcode",
                        detail: "Xcode → Window → Devices and Simulators. Erase or delete simulators you no longer use.",
                        kind: .settings
                    )
                ],
                references: [],
                tags: ["xcode", "simulator", "developer"]
            ),
            DirectoryTarget(
                id: "storage.ios-backups",
                title: "iPhone and iPad backups",
                summary: "Local device backups in ~/Library/Application Support/MobileSync/Backup.",
                detail: "iTunes and Finder backups can be many gigabytes each, and older backups of replaced devices are easy to forget. Review them in Finder's device management window before deleting.",
                scope: .native,
                url: backups,
                reportThreshold: 2 * ByteMath.gigabyte,
                highThreshold: 10 * ByteMath.gigabyte,
                criticalThreshold: 30 * ByteMath.gigabyte,
                remediation: [
                    RemediationStep(
                        title: "Manage backups in Finder",
                        detail: "Connect the device, open Finder, select the device, and choose Manage Backups to review dates and sizes.",
                        kind: .settings
                    )
                ],
                references: [
                    Reference(title: "Apple Support: Back up iPhone", url: "https://support.apple.com/en-us/108366")
                ],
                tags: ["ios", "backup"]
            ),
            DirectoryTarget(
                id: "storage.trash",
                title: "Trash",
                summary: "Files in the Trash still occupy disk space until the Trash is emptied.",
                detail: "Emptying the Trash is permanent. Check the contents first, especially if you recently deleted a project or a large download.",
                scope: .native,
                url: trash,
                reportThreshold: 200 * ByteMath.megabyte,
                highThreshold: 2 * ByteMath.gigabyte,
                criticalThreshold: 10 * ByteMath.gigabyte,
                remediation: [
                    RemediationStep(
                        title: "Review the Trash",
                        detail: "Open the Trash and restore anything you still need.",
                        command: "open ~/.Trash",
                        kind: .command
                    ),
                    RemediationStep(
                        title: "Empty it",
                        detail: "This permanently deletes the contents. Emptying from Finder is equivalent and gives you a confirmation dialog.",
                        command: "rm -rf ~/.Trash/*",
                        kind: .command
                    )
                ],
                references: [],
                tags: ["trash"]
            ),
            DirectoryTarget(
                id: "storage.docker",
                title: "Docker data",
                summary: "Images, containers, and build caches stored in Docker's disk image.",
                detail: "Docker's virtual disk grows but does not shrink automatically when you delete containers. `docker system prune` removes unused data. If you no longer use Docker, uninstalling it is the bigger win.",
                scope: .thirdParty,
                url: docker,
                reportThreshold: 5 * ByteMath.gigabyte,
                highThreshold: 20 * ByteMath.gigabyte,
                criticalThreshold: 50 * ByteMath.gigabyte,
                remediation: [
                    RemediationStep(
                        title: "Prune Docker",
                        detail: "Removes stopped containers, unused networks, dangling images, and build cache. Add --volumes only if you are sure no data volumes are needed.",
                        command: "docker system prune -a --volumes",
                        kind: .command
                    ),
                    RemediationStep(
                        title: "Check disk usage",
                        detail: "See what Docker is holding before pruning.",
                        command: "docker system df",
                        kind: .command
                    )
                ],
                references: [],
                tags: ["docker", "developer"]
            )
        ]

        let devCacheEntries = DevCacheCatalog.entries.filter {
            FileManager.default.fileExists(atPath: $0.url.path)
        }
        let measurements = targets.map { MeasurementTarget(id: $0.id, url: $0.url, timeout: 12) }
            + devCacheEntries.map { MeasurementTarget(id: $0.id, url: $0.url, timeout: 90) }
        let sizes = measureDirectories(measurements)

        let homebrewTarget = targets.first { $0.id == "storage.homebrew" }
        let homebrewBytes = sizes["storage.homebrew"] ?? 0
        let homebrewReported = homebrewTarget.map {
            ByteMath.severity(
                for: homebrewBytes,
                reportThreshold: $0.reportThreshold,
                highThreshold: $0.highThreshold,
                criticalThreshold: $0.criticalThreshold
            ) != nil
        } ?? false

        let devCacheTotal = devCacheEntries.reduce(Int64(0)) { $0 + (sizes[$1.id] ?? 0) }
        let devCachesUnderAppCaches = devCacheEntries
            .filter { $0.url.path.hasPrefix(caches.path + "/") }
            .reduce(Int64(0)) { $0 + (sizes[$1.id] ?? 0) }
        let devCachesReported = devCacheTotal >= DevCacheCatalog.reportThreshold

        var findings: [Finding] = []

        for target in targets {
            guard var bytes = sizes[target.id] else { continue }

            // App caches overlap Homebrew and the developer caches that live in
            // ~/Library/Caches. Subtract only caches that are reported by their
            // own finding, so space never vanishes from the report.
            if target.id == "storage.app-caches" {
                let overlap = (homebrewReported ? homebrewBytes : 0)
                    + (devCachesReported ? devCachesUnderAppCaches : 0)
                bytes = max(0, bytes - overlap)
            }

            guard let severity = ByteMath.severity(
                for: bytes,
                reportThreshold: target.reportThreshold,
                highThreshold: target.highThreshold,
                criticalThreshold: target.criticalThreshold
            ) else { continue }

            findings.append(Finding(
                id: target.id,
                category: .storage,
                title: "\(target.title): \(Format.bytes(bytes))",
                summary: target.summary,
                detail: target.detail,
                severity: severity,
                scope: target.scope,
                reclaimableBytes: bytes,
                metrics: [
                    Metric(label: "Reclaimable", value: Format.bytes(bytes), isPrimary: true),
                    Metric(label: "Location", value: Paths.display(target.url))
                ],
                remediation: target.remediation,
                references: target.references,
                paths: [target.url.path],
                tags: target.tags
            ))
        }

        if let cacheFinding = DevCacheFindingBuilder.finding(sizes: sizes) {
            findings.append(cacheFinding)
        }

        return findings
    }

    private struct MeasurementTarget: Sendable {
        let id: String
        let url: URL
        let timeout: TimeInterval
    }

    private func measureDirectories(_ targets: [MeasurementTarget]) -> [String: Int64] {
        let fileManager = FileManager.default
        let existing = targets.filter { fileManager.fileExists(atPath: $0.url.path) }
        guard !existing.isEmpty else { return [:] }

        let lock = NSLock()
        var sizes: [String: Int64] = [:]
        let runner = self.runner

        // Measuring large developer caches is metadata-heavy. Running every
        // target at once thrashes the disk and makes timeouts more likely, so
        // process a small batch at a time.
        let batchSize = 4
        var index = 0
        while index < existing.count {
            let end = min(index + batchSize, existing.count)
            let batch = Array(existing[index..<end])
            DispatchQueue.concurrentPerform(iterations: batch.count) { offset in
                let target = batch[offset]
                let result = runner.run(
                    "/usr/bin/du",
                    arguments: ["-sk", target.url.path],
                    timeout: target.timeout
                )
                guard let bytes = DuParser.bytes(result.stdout) else { return }
                lock.lock()
                sizes[target.id] = bytes
                lock.unlock()
            }
            index = end
        }

        return sizes
    }

    // MARK: Large files

    private func largeFileFindings() -> [Finding] {
        let fileManager = FileManager.default
        let candidates = [
            Paths.home("Downloads"),
            Paths.home("Desktop"),
            Paths.home("Documents"),
            Paths.home("Movies")
        ].filter { fileManager.fileExists(atPath: $0.path) }

        guard !candidates.isEmpty else { return [] }

        var arguments: [String] = []
        for path in candidates { arguments.append(path.path) }
        arguments.append(contentsOf: [
            "-type", "f",
            "-size", "+1G",
            "-not", "-path", "*/.git/*",
            "-not", "-path", "*/Library/*",
            "-not", "-path", "*/node_modules/*",
            "-not", "-path", "*/.venv/*",
            "-not", "-path", "*/Pods/*",
            "-not", "-path", "*/.next/*",
            "-not", "-path", "*/.nuxt/*",
            "-not", "-path", "*/.svelte-kit/*",
            "-not", "-path", "*/.turbo/*",
            "-not", "-path", "*/.parcel-cache/*",
            "-not", "-path", "*/.build/*",
            "-not", "-path", "*/build/*",
            "-not", "-path", "*/target/*",
            "-not", "-path", "*/.dart_tool/*",
            "-not", "-path", "*/.expo/*",
            "-not", "-path", "*/vendor/*",
            "-not", "-path", "*/_build/*",
            "-not", "-path", "*/deps/*",
            "-not", "-path", "*/.zig-cache/*",
            "-not", "-path", "*/zig-out/*",
            "-not", "-path", "*/.stack-work/*",
            "-exec", "/usr/bin/stat", "-f", "%z|%N", "{}", "+"
        ])

        let result = runner.run("/usr/bin/find", arguments: arguments, timeout: 12)
        guard result.succeeded else { return [] }

        let files = LargeFileParser.parse(result.stdout)
            .filter { $0.bytes >= 1 * ByteMath.gigabyte }
            .sorted { $0.bytes > $1.bytes }

        guard !files.isEmpty else { return [] }

        let total = files.reduce(Int64(0)) { $0 + $1.bytes }
        guard total >= 2 * ByteMath.gigabyte || (files.first?.bytes ?? 0) >= 2 * ByteMath.gigabyte else {
            return []
        }

        let severity: Severity
        if total >= 50 * ByteMath.gigabyte {
            severity = .critical
        } else if total >= 15 * ByteMath.gigabyte {
            severity = .high
        } else if total >= 5 * ByteMath.gigabyte {
            severity = .medium
        } else {
            severity = .low
        }

        var metrics: [Metric] = [
            Metric(label: "Large files", value: Format.bytes(total), isPrimary: true),
            Metric(label: "Count", value: "\(files.count)")
        ]
        for file in files.prefix(8) {
            metrics.append(Metric(label: Format.bytes(file.bytes), value: file.displayPath))
        }

        return [Finding(
            id: "storage.large-files",
            category: .storage,
            title: "\(files.count) large file\(files.count == 1 ? "" : "s") totaling \(Format.bytes(total))",
            summary: "Optimizr found files larger than 1 GB in Downloads, Desktop, Documents, or Movies. They are the fastest place to recover a big chunk of space.",
            detail: "Large files are often old installers, disk images, video exports, or extracted archives. Review them in Finder and delete or move the ones you no longer need. Optimizr does not delete anything for you; open the containing folder and decide case by case.",
            severity: severity,
            scope: .userData,
            reclaimableBytes: total,
            metrics: metrics,
            remediation: [
                RemediationStep(
                    title: "Review the folders",
                    detail: "Find the files listed in the evidence and open their containing folders.",
                    command: "open ~/Downloads",
                    kind: .command
                ),
                RemediationStep(
                    title: "Move large archives to external storage",
                    detail: "If you want to keep the files but not the disk usage, move them to an external drive or cloud storage.",
                    kind: .manual
                ),
                RemediationStep(
                    title: "Empty the Trash afterward",
                    detail: "Deleted files do not release space until the Trash is emptied.",
                    command: "rm -rf ~/.Trash/*",
                    kind: .command
                )
            ],
            paths: Array(files.prefix(8).map(\.path)),
            tags: ["downloads", "large-files"]
        )]
    }

    // MARK: Protected apps

    /// Lists app bundles that System Integrity Protection or the `restricted`
    /// file flag prevents the user from removing. These are informational: the
    /// space is real, but uninstalling is not a supported way to reclaim it.
    private func protectedAppsFinding() -> Finding? {
        let apps = AppInventory.protectedApps(runner: runner)
        guard !apps.isEmpty else { return nil }

        let total = apps.reduce(Int64(0)) { $0 + $1.bytes }
        guard total >= 500 * ByteMath.megabyte || (apps.first?.bytes ?? 0) >= 250 * ByteMath.megabyte else {
            return nil
        }

        var metrics: [Metric] = [
            Metric(label: "Protected apps", value: "\(apps.count)", isPrimary: true),
            Metric(label: "Total size", value: Format.bytes(total)),
            Metric(label: "Largest", value: apps.first?.name ?? "None")
        ]
        for app in apps.prefix(8) {
            metrics.append(Metric(
                label: "\(app.name) · \(app.protection.shortTitle)",
                value: Format.bytes(app.bytes)
            ))
        }

        let top = apps.prefix(8)
        return Finding(
            id: "storage.protected-apps",
            category: .storage,
            title: "\(apps.count) protected apps use \(Format.bytes(total))",
            summary: "These app bundles are owned by macOS or carry the restricted flag. System Integrity Protection prevents removing or modifying them, so their disk usage is not recoverable by uninstalling.",
            detail: "Optimizr found protected bundles in /System/Applications or under /Applications with the restricted flag. SIP stops even an administrator from deleting or changing them, and macOS may restart required system apps and agents automatically. The space they occupy is therefore not a normal optimization target: do not disable SIP, and do not try to delete these bundles. Their user data can still be reviewed separately, but the app itself stays.",
            severity: .info,
            scope: .native,
            metrics: metrics,
            remediation: [
                RemediationStep(
                    title: "Leave the bundles in place",
                    detail: "Do not delete or modify apps under /System or bundles carrying the restricted flag. Disabling System Integrity Protection to remove them is not a supported optimization and weakens the Mac's security.",
                    kind: .manual
                ),
                RemediationStep(
                    title: "Review the app's data instead",
                    detail: "User data lives outside the bundle in ~/Library/Containers, ~/Library/Group Containers, and ~/Library/Application Support. Use the app's own settings to clear downloads or caches.",
                    kind: .manual
                ),
                RemediationStep(
                    title: "Open Storage settings",
                    detail: "System Settings → General → Storage shows Apple's own breakdown and recommendations for system data.",
                    command: "open 'x-apple.systempreferences:com.apple.settings.Storage'",
                    kind: .settings
                )
            ],
            references: [
                Reference(title: "Apple Support: System Integrity Protection", url: "https://support.apple.com/guide/security/system-integrity-protection-secb7ea06b49/web")
            ],
            paths: top.map(\.path),
            tags: ["protected", "sip", "system", "apps"]
        )
    }

    // MARK: Time Machine local snapshots

    private func localSnapshotsFinding() -> Finding? {
        let result = runner.run("/usr/bin/tmutil", arguments: ["listlocalsnapshots", "/"], timeout: 8)
        guard result.succeeded else { return nil }

        let snapshots = result.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.contains("com.apple.TimeMachine") }

        guard !snapshots.isEmpty else { return nil }

        let severity: Severity = snapshots.count >= 5 ? .medium : .low
        var metrics: [Metric] = [
            Metric(label: "Snapshots", value: "\(snapshots.count)", isPrimary: true)
        ]
        if let latest = snapshots.last {
            metrics.append(Metric(label: "Latest", value: latest.replacingOccurrences(of: "com.apple.TimeMachine.", with: "")))
        }

        return Finding(
            id: "storage.local-snapshots",
            category: .storage,
            title: "\(snapshots.count) Time Machine local snapshot\(snapshots.count == 1 ? "" : "s")",
            summary: "APFS keeps local snapshots on the startup disk between Time Machine backups. They consume space that macOS may reclaim only under pressure.",
            detail: "Local snapshots are useful for quick restores, but they can hold onto deleted files and occupy tens of gigabytes. macOS thins them automatically, and `tmutil thinlocalsnapshots` asks it to reclaim space sooner. Do not delete snapshots if Time Machine has not completed a recent backup.",
            severity: severity,
            scope: .native,
            metrics: metrics,
            remediation: [
                RemediationStep(
                    title: "List snapshots",
                    detail: "Review the snapshot dates before thinning.",
                    command: "tmutil listlocalsnapshots /",
                    kind: .command
                ),
                RemediationStep(
                    title: "Thin old snapshots",
                    detail: "Asks macOS to reduce local snapshots to roughly 20 GB. Requires an administrator password.",
                    command: "sudo tmutil thinlocalsnapshots / 20000000000 4",
                    kind: .command
                ),
                RemediationStep(
                    title: "Check Time Machine",
                    detail: "Run a backup first if the last successful backup is old; local snapshots are part of your safety net.",
                    command: "tmutil latestbackup",
                    kind: .command
                )
            ],
            references: [
                Reference(title: "Apple Support: Time Machine local snapshots", url: "https://support.apple.com/en-us/102619")
            ],
            tags: ["time-machine", "apfs", "snapshots"]
        )
    }
}

// MARK: - Alternatives

/// Suggests more efficient replacements for running apps and services when a
/// known alternative exists and the measured footprint makes the gain
/// meaningful. Estimates are deliberately conservative and optional.
public struct AlternativesScanner: OptimizrScanner {
    public let category: ScanCategory = .memory
    private let runner: any CommandRunning

    public init(runner: any CommandRunning = ShellCommandRunner()) {
        self.runner = runner
    }

    public func scan() -> [Finding] {
        let psOutput = runner.run("/bin/ps", arguments: ["-axo", "pid=,rss=,pcpu=,comm="], timeout: 8)
        let samples = ProcessSampleParser.parse(psOutput.stdout)
        guard !samples.isEmpty else { return [] }

        let applications = RunningApplicationInventory.runningApplications(from: samples)
        return AlternativeEvaluator.findings(
            applications: applications,
            totalMemory: Int64(ProcessInfo.processInfo.physicalMemory)
        )
    }
}

// MARK: - Engine

public struct ScanEngine: Sendable {
    private let scanners: [any OptimizrScanner]
    private let runner: any CommandRunning

    public init(
        scanners: [any OptimizrScanner]? = nil,
        runner: any CommandRunning = ShellCommandRunner(),
        options: ScanOptions = .standard
    ) {
        self.scanners = scanners ?? [
            MemoryScanner(runner: runner),
            CPUScanner(runner: runner),
            StorageScanner(runner: runner),
            DevArtifactScanner(runner: runner, options: options),
            AlternativesScanner(runner: runner)
        ]
        self.runner = runner
    }

    public func scan() async -> ScanReport {
        let startedAt = Date()

        let snapshot = await Task.detached(priority: .userInitiated) { [runner] in
            SystemProfiler.snapshot(runner: runner)
        }.value

        let findings = await withTaskGroup(of: [Finding].self) { group in
            for scanner in scanners {
                group.addTask {
                    await Task.detached(priority: .userInitiated) {
                        scanner.scan()
                    }.value
                }
            }
            var collected: [Finding] = []
            for await result in group {
                collected.append(contentsOf: result)
            }
            return collected
        }

        var seen = Set<String>()
        let unique = findings.filter { seen.insert($0.id).inserted }
        let sorted = unique.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return (lhs.reclaimableBytes ?? 0) > (rhs.reclaimableBytes ?? 0)
        }

        return ScanReport(
            startedAt: startedAt,
            finishedAt: Date(),
            findings: sorted,
            snapshot: snapshot
        )
    }
}
