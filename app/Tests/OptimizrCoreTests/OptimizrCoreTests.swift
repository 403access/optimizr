import XCTest
@testable import OptimizrCore

final class ParserTests: XCTestCase {
    // MARK: vm_stat

    func testParsesVMStatistics() {
        let output = """
        Mach Virtual Memory Statistics: (page size of 16384 bytes)
        Pages free:                                     4472.
        Pages active:                                 261645.
        Pages inactive:                               259790.
        Pages speculative:                              1242.
        Pages throttled:                                   0.
        Pages wired down:                             270973.
        Pages purgeable:                                   0.
        "Translation faults":                     4358937843.
        Pages copy-on-write:                       104101871.
        Pages zero filled:                         1458689618.
        Pages reactivated:                         809488106.
        Pages purged:                              191570207.
        File-backed pages:                            193876.
        Anonymous pages:                              328801.
        Pages stored in compressor:                  1529513.
        Pages occupied by compressor:                 725517.
        Decompressions:                           1160249670.
        Compressions:                             1242789334.
        Pageins:                                   189963571.
        Swapouts:                                    6210342.
        """

        let stats = VMStatistics.parse(output)
        XCTAssertNotNil(stats)
        XCTAssertEqual(stats?.pageSize, 16_384)
        XCTAssertEqual(stats?.freePages, 4_472)
        XCTAssertEqual(stats?.activePages, 261_645)
        XCTAssertEqual(stats?.wiredPages, 270_973)
        XCTAssertEqual(stats?.compressorPages, 725_517)
        XCTAssertEqual(stats?.compressedBytes, 725_517 * 16_384)
        XCTAssertEqual(stats?.freeBytes, 4_472 * 16_384)
    }

    func testRejectsUnrelatedOutput() {
        XCTAssertNil(VMStatistics.parse("not vm_stat output"))
    }

    // MARK: swap

    func testParsesSwapUsageInMegabytes() {
        let swap = SwapUsage.parse("total = 13312.00M  used = 12581.12M  free = 730.88M  (encrypted)")
        XCTAssertEqual(swap?.totalBytes, 13_312_000_000)
        XCTAssertEqual(swap?.usedBytes, 12_581_120_000)
        XCTAssertEqual(swap?.freeBytes, 730_880_000)
        XCTAssertEqual(swap?.usedFraction ?? 0, 0.945, accuracy: 0.001)
    }

    func testParsesSwapUsageInGigabytes() {
        let swap = SwapUsage.parse("total = 2.00G  used = 512.00M  free = 1.50G")
        XCTAssertEqual(swap?.totalBytes, 2_000_000_000)
        XCTAssertEqual(swap?.usedBytes, 512_000_000)
    }

    func testSwapParseFailsWithoutValues() {
        XCTAssertNil(SwapUsage.parse("swapusage unavailable"))
    }

    // MARK: memory pressure

    func testParsesMemoryPressure() {
        let output = """
        Page Q counts:
        Pages active: 259598
        System-wide memory free percentage: 34%
        """
        XCTAssertEqual(MemoryPressureParser.parseFreePercentage(output), 34)
    }

    func testClampsMemoryPressure() {
        XCTAssertEqual(MemoryPressureParser.parseFreePercentage("System-wide memory free percentage: 140%"), 100)
        XCTAssertNil(MemoryPressureParser.parseFreePercentage("nothing here"))
    }

    // MARK: ps

    func testParsesProcessSamples() {
        let output = """
            1  11616   0.7 /sbin/launchd
          549   9984   0.3 /usr/libexec/logd
         9341 2048000 125.5 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
        """
        let samples = ProcessSampleParser.parse(output)
        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(samples[0].pid, 1)
        XCTAssertEqual(samples[0].memoryBytes, 11_616 * 1_024)
        XCTAssertEqual(samples[2].cpuPercent, 125.5)
        XCTAssertEqual(samples[2].displayName, "Google Chrome.app")
    }

    func testSkipsMalformedProcessLines() {
        let samples = ProcessSampleParser.parse("garbage\n1 2 nope /bin/thing\n")
        XCTAssertTrue(samples.isEmpty)
    }

    // MARK: load

    func testParsesLoadAverage() {
        XCTAssertEqual(LoadAverageParser.parse("{ 6.30 9.45 10.29 }"), [6.30, 9.45, 10.29])
        XCTAssertEqual(LoadAverageParser.parse("{ 0.00 0.01 0.05 }"), [0, 0.01, 0.05])
        XCTAssertTrue(LoadAverageParser.parse("").isEmpty)
    }

    // MARK: thermal / power

    func testParsesThermalState() {
        let output = """
        Note: No thermal warning level has been recorded
        Note: No performance warning level has been recorded
        CPU_Speed_Limit = 78
        """
        let state = ThermalState.parse(output)
        XCTAssertEqual(state.speedLimit, 78)
        XCTAssertTrue(state.isThrottled)
    }

    func testHealthyThermalState() {
        let state = ThermalState.parse("CPU_Speed_Limit = 100")
        XCTAssertFalse(state.isThrottled)
    }

    func testParsesLowPowerMode() {
        XCTAssertTrue(PowerSettingsParser.lowPowerModeEnabled(" lowpowermode         1"))
        XCTAssertFalse(PowerSettingsParser.lowPowerModeEnabled(" lowpowermode         0"))
        XCTAssertFalse(PowerSettingsParser.lowPowerModeEnabled("no settings"))
    }

    // MARK: storage helpers

    func testParsesDuOutput() {
        XCTAssertEqual(DuParser.bytes("11431216\t/Users/example/Library/Caches"), 11_431_216 * 1_024)
        XCTAssertNil(DuParser.bytes("garbage"))
    }

    func testParsesMultiPathDuOutput() {
        let output = """
        1024\t/Applications/Example.app
        2048\t/System/Applications/Mail.app
        """
        let sizes = DuListingParser.sizes(output)
        XCTAssertEqual(sizes["/Applications/Example.app"], 1_024 * 1_024)
        XCTAssertEqual(sizes["/System/Applications/Mail.app"], 2_048 * 1_024)
    }

    func testClassifiesProtectedAppBundles() {
        XCTAssertEqual(AppInventory.protection(forPath: "/System/Applications/Mail.app", restricted: false), .system)
        XCTAssertEqual(AppInventory.protection(forPath: "/Applications/Safari.app", restricted: true), .restricted)
        XCTAssertNil(AppInventory.protection(forPath: "/Applications/Figma.app", restricted: false))
    }

    func testParsesLargeFiles() {
        let moviePath = Paths.home.appendingPathComponent("Movies/Export.mov").path
        let output = """
        2147483648|/Users/example/Downloads/Installer.dmg
        3221225472|\(moviePath)
        invalid
        """
        let files = LargeFileParser.parse(output)
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].bytes, 2_147_483_648)
        XCTAssertEqual(files[1].displayPath, "~/Movies/Export.mov")
    }
}

final class ModelTests: XCTestCase {
    private func finding(
        id: String,
        category: ScanCategory,
        severity: Severity,
        bytes: Int64? = nil
    ) -> Finding {
        Finding(
            id: id,
            category: category,
            title: "Title \(id)",
            summary: "Summary",
            detail: "Detail",
            severity: severity,
            scope: .native,
            reclaimableBytes: bytes
        )
    }

    func testReportSortsBySeverityThenSize() {
        let report = ScanReport(
            startedAt: Date(),
            finishedAt: Date(),
            findings: [
                finding(id: "a", category: .memory, severity: .low, bytes: 10),
                finding(id: "b", category: .storage, severity: .critical, bytes: 1),
                finding(id: "c", category: .storage, severity: .critical, bytes: 5)
            ],
            snapshot: .empty
        )
        XCTAssertEqual(report.sortedFindings.map(\.id), ["c", "b", "a"])
    }

    func testReclaimableTotalsAreGroupedByCategory() {
        let report = ScanReport(
            startedAt: Date(),
            finishedAt: Date(),
            findings: [
                finding(id: "a", category: .storage, severity: .high, bytes: 1_000),
                finding(id: "b", category: .storage, severity: .low, bytes: 2_000),
                finding(id: "c", category: .memory, severity: .medium, bytes: 500)
            ],
            snapshot: .empty
        )
        XCTAssertEqual(report.totalReclaimableBytes, 3_500)
        XCTAssertEqual(report.reclaimableBytes(for: .storage), 3_000)
        XCTAssertEqual(report.reclaimableBytes(for: .cpu), 0)
    }

    func testHealthScoreDropsWithSeverity() {
        let healthy = ScanReport(
            startedAt: Date(), finishedAt: Date(), findings: [], snapshot: .empty
        )
        XCTAssertEqual(healthy.healthScore, 100)

        let degraded = ScanReport(
            startedAt: Date(),
            finishedAt: Date(),
            findings: [
                finding(id: "a", category: .memory, severity: .critical),
                finding(id: "b", category: .storage, severity: .medium)
            ],
            snapshot: .empty
        )
        XCTAssertEqual(degraded.score(for: .memory), 82)
        XCTAssertEqual(degraded.score(for: .storage), 94)
        XCTAssertEqual(degraded.healthScore, 92)
    }

    func testHealthScoreAveragesCategoriesAndFloorsEachAtZero() {
        let findings = (0..<12).map { index in
            finding(id: "f\(index)", category: .cpu, severity: .critical)
        }
        let report = ScanReport(
            startedAt: Date(), finishedAt: Date(), findings: findings, snapshot: .empty
        )
        XCTAssertEqual(report.score(for: .cpu), 0)
        XCTAssertEqual(report.healthScore, 67)
    }

    func testMarkdownExportIncludesEvidenceAndCommands() {
        var item = finding(
            id: "storage.cache",
            category: .storage,
            severity: .high,
            bytes: 4_000_000_000
        )
        item = Finding(
            id: item.id,
            category: item.category,
            title: "App caches: 4 GB",
            summary: item.summary,
            detail: item.detail,
            severity: item.severity,
            scope: .thirdParty,
            reclaimableBytes: item.reclaimableBytes,
            metrics: [Metric(label: "Reclaimable", value: "4 GB", isPrimary: true)],
            remediation: [RemediationStep(title: "Clear it", detail: "Safely", command: "rm -rf ~/Library/Caches/*", kind: .command)]
        )
        let report = ScanReport(
            startedAt: Date(),
            finishedAt: Date(),
            findings: [item],
            snapshot: .empty
        )
        let markdown = report.markdown()
        XCTAssertTrue(markdown.contains("# Optimizr report"))
        XCTAssertTrue(markdown.contains("App caches: 4 GB"))
        XCTAssertTrue(markdown.contains("rm -rf ~/Library/Caches/*"))
        XCTAssertTrue(markdown.contains("Health score"))
        XCTAssertTrue(markdown.contains("**Scope:** Third-party"))
    }

    func testSnapshotDerivedValues() {
        let snapshot = SystemSnapshot(
            physicalMemory: 16_000_000_000,
            memoryUsed: 10_000_000_000,
            memoryFreePercent: 37.5,
            memoryPressure: 0.82,
            swapUsed: 8_000_000_000,
            swapTotal: 10_000_000_000,
            cpuCount: 8,
            loadAverages: [4, 3, 2],
            uptime: 90_000,
            diskTotal: 500_000_000_000,
            diskFree: 50_000_000_000
        )
        XCTAssertEqual(snapshot.memoryPressureLabel, "High")
        XCTAssertEqual(snapshot.diskUsedFraction, 0.9, accuracy: 0.001)
        XCTAssertEqual(snapshot.swapFraction, 0.8, accuracy: 0.001)
        XCTAssertEqual(snapshot.loadAverage15, 2)
    }

    func testSeverityThresholds() {
        let gigabyte = ByteMath.gigabyte
        XCTAssertNil(ByteMath.severity(for: 100, reportThreshold: gigabyte, highThreshold: 5 * gigabyte, criticalThreshold: 10 * gigabyte))
        XCTAssertEqual(ByteMath.severity(for: 2 * gigabyte, reportThreshold: gigabyte, highThreshold: 5 * gigabyte, criticalThreshold: 10 * gigabyte), .medium)
        XCTAssertEqual(ByteMath.severity(for: 6 * gigabyte, reportThreshold: gigabyte, highThreshold: 5 * gigabyte, criticalThreshold: 10 * gigabyte), .high)
        XCTAssertEqual(ByteMath.severity(for: 11 * gigabyte, reportThreshold: gigabyte, highThreshold: 5 * gigabyte, criticalThreshold: 10 * gigabyte), .critical)
    }

    func testUptimeFormatting() {
        XCTAssertEqual(Format.uptime(0), "0s")
        XCTAssertEqual(Format.uptime(3_600), "1h 0m")
        XCTAssertEqual(Format.uptime(90_000), "1d 1h")
    }
}
