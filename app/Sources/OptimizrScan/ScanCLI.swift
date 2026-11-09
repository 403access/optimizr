import Foundation
import OptimizrCore

/// Headless scanner used for verification, scripting, and CI smoke tests.
///
/// Usage:
///   optimizr-scan             Human-readable summary
///   optimizr-scan --json      Full report as JSON
///   optimizr-scan --markdown  Report as Markdown
///   optimizr-scan --deep-dev  List nested developer project artifacts
@main
struct OptimizrScanCommand {
    static func main() async {
        let arguments = Set(CommandLine.arguments.dropFirst())
        let options = ScanOptions(
            includeNestedDeveloperArtifacts: arguments.contains("--deep-dev")
        )
        let report = await ScanEngine(options: options).scan()

        if arguments.contains("--json") {
            printJSON(report)
        } else if arguments.contains("--markdown") {
            print(report.markdown())
        } else {
            printSummary(report)
        }
    }

    private static func printJSON(_ report: ScanReport) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(report),
              let text = String(data: data, encoding: .utf8) else {
            FileHandle.standardError.write(Data("Failed to encode report\n".utf8))
            return
        }
        print(text)
    }

    private static func printSummary(_ report: ScanReport) {
        let snapshot = report.snapshot
        print("Optimizr scan — \(snapshot.hostName)")
        print("\(snapshot.osVersion)")
        print("Health score: \(report.healthScore)/100 (\(report.scoreLabel()))")
        print("Findings: \(report.findings.count)")
        if report.totalReclaimableBytes > 0 {
            print("Reclaimable: \(Format.bytes(report.totalReclaimableBytes))")
        }
        print("")
        print("Memory  \(report.count(for: .memory)) findings · score \(report.score(for: .memory))/100")
        print("CPU     \(report.count(for: .cpu)) findings · score \(report.score(for: .cpu))/100")
        print("Storage \(report.count(for: .storage)) findings · score \(report.score(for: .storage))/100")
        print("")

        for category in ScanCategory.allCases {
            let findings = report.findings(for: category)
            guard !findings.isEmpty else { continue }
            print("== \(category.title) ==")
            for finding in findings {
                var line = "[\(finding.severity.title.uppercased()) · \(finding.scope.title)] \(finding.title)"
                if let bytes = finding.reclaimableBytes, bytes > 0 {
                    line += "  (up to \(Format.bytes(bytes)))"
                }
                print(line)
                print("  \(finding.summary)")
                for step in finding.remediation {
                    print("  → \(step.title)")
                    if let command = step.command {
                        print("    $ \(command)")
                    }
                }
                print("")
            }
        }

        print("Read-only scan completed in \(String(format: "%.1f", report.duration))s. Nothing was changed.")
    }
}
