---
title: Scanner engine
sidebar_position: 2
---

# Scanner engine

The scanner engine is the heart of Optimizr. It is small, synchronous per scanner, and intentionally boring: run a fixed utility, parse its text, compare against a threshold, emit a finding with evidence and remediation.

## Protocol

```swift
public protocol OptimizrScanner: Sendable {
    var category: ScanCategory { get }
    func scan() -> [Finding]
}
```

Each scanner returns findings only. Every finding carries a `FindingScope` (native, third-party, mixed, or user data) in addition to its category and severity; the app, Markdown export, and CLI expose it. Cross-cutting state such as the system snapshot is collected once by `SystemProfiler`, and the engine owns ordering and deduplication.

```swift
public struct ScanEngine: Sendable {
    public init(
        scanners: [any OptimizrScanner]? = nil,
        runner: any CommandRunning = ShellCommandRunner(),
        options: ScanOptions = .standard
    )

    public func scan() async -> ScanReport
}
```

`ScanEngine.scan()`:

1. Builds a `SystemSnapshot` on a detached task.
2. Runs every scanner concurrently in a task group.
3. Deduplicates findings by `Finding.id`.
4. Sorts by severity (descending), then by reclaimable bytes (descending).
5. Returns a `ScanReport` with start/finish timestamps.

The default scanners are `MemoryScanner`, `CPUScanner`, `StorageScanner`, `DevArtifactScanner`, and `AlternativesScanner`. `ScanOptions.includeNestedDeveloperArtifacts` controls how developer evidence is expanded; the app exposes it as “Show nested dev folders” and the CLI as `--deep-dev`. The CLI and the app both call this method, so there is no second implementation to drift.

## Command runner

Every scanner receives an injected `CommandRunning`:

```swift
public protocol CommandRunning: Sendable {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult
}
```

`ShellCommandRunner` is the production implementation. Tests can inject a fake runner to exercise a scanner without touching the machine, although the current test suite focuses on the pure parsers.

Key properties:

- **No shell.** `Process.executableURL` plus `arguments`.
- **File-backed capture.** stdout and stderr go to temporary files; the parent reads them after exit. This avoids pipe-buffer deadlocks.
- **Bounded runtime.** The deadline is enforced with a polling loop; `SIGTERM` then `SIGKILL`.
- **Fixed environment.** Includes `/opt/homebrew/bin` for tools such as `brew`, and sets a UTF-8 locale.
- **No throwing API.** A failed command produces a `CommandResult` with a non-zero status and empty output. Scanners treat that as "no evidence" and move on.

## Snapshot collection

`SystemProfiler.snapshot(runner:)` populates:

| Field | Source |
| --- | --- |
| Host, OS, RAM, cores, uptime | `ProcessInfo` |
| Memory used / free % | `vm_stat`, `memory_pressure` |
| Memory pressure | Derived from free fraction and swap fraction |
| Swap | `sysctl -n vm.swapusage` |
| Load average | `sysctl -n vm.loadavg` |
| Disk total / free | `FileManager.attributesOfFileSystem("/")` |

If a utility is unavailable, the field falls back to a safe default. A missing `memory_pressure` uses the `vm_stat` free-page fraction. A missing `vm_stat` leaves memory at zero rather than inventing data.

## Memory scanner

Commands:

```text
/usr/bin/vm_stat
/usr/sbin/sysctl -n vm.swapusage
/usr/bin/memory_pressure
/bin/ps -axo pid=,rss=,pcpu=,comm=
```

Findings:

| ID | Signal | Threshold |
| --- | --- | --- |
| `memory.pressure` | Weighted free/swap pressure | ≥ 0.35 |
| `memory.swap` | Swap used | > 512 MiB |
| `memory.top-process` | Largest RSS | ≥ 10% RAM and ≥ 1 GB |
| `memory.compressor` | Compressor share | > 15% RAM |

The pressure formula is documented in the [findings catalog](../product/findings-catalog#memory). Memory findings never claim reclaimable bytes; swapping is not a file to delete.

## CPU scanner

Commands:

```text
/usr/sbin/sysctl -n vm.loadavg
/bin/ps -axo pid=,rss=,pcpu=,comm=
/usr/bin/pmset -g therm
/usr/bin/pmset -g
```

Plus a direct filesystem inventory of:

```text
~/Library/LaunchAgents
/Library/LaunchAgents
/Library/LaunchDaemons
```

Findings: `cpu.load`, `cpu.top-process`, `cpu.thermal`, `cpu.low-power-mode`, `cpu.launch-items`, `cpu.uptime`.

Notes:

- `ps` CPU percentages are lifetime averages. A high value is a hint, not a live sample. The UI states this in the detail text.
- `pmset -g therm` often reports only notes on Apple silicon. The scanner simply skips thermal findings when no speed limit is present.
- Launch items are parsed with `PropertyListSerialization`; only `Label` is read. Apple's `com.apple.*` labels are excluded.
- `cpu.launch-items` is emitted at ≥ 6 third-party items, with severity escalating at 10 and 20.

## Storage scanner

Storage is the only scanner that touches unbounded directory trees. It is also the slowest, so it gets extra care.

### Disk capacity

Read from `attributesOfFileSystem(forPath: "/")`. The low-disk finding fires below 15% free, with critical below 5% and high below 10%.

### Directory measurement

Targets are measured concurrently with `du -sk <path>`, timeout 12 seconds each. The app caches nothing; every scan re-measures a small, fixed list:

- `~/Library/Caches` (Homebrew subtracted)
- `~/Library/Caches/Homebrew`
- `~/Library/Developer/Xcode/DerivedData`
- `~/Library/Developer/Xcode/iOS DeviceSupport`
- `~/Library/Developer/Xcode/Archives`
- `~/Library/Developer/CoreSimulator/Devices`
- `~/Library/Application Support/MobileSync/Backup`
- `~/.Trash`
- `~/Library/Containers/com.docker.docker`
- Global developer caches from `DevCacheCatalog`: npm, Bun, pnpm, Yarn, pip, uv, Cargo, Go, Gradle, Maven, CocoaPods, SwiftPM, JetBrains, Composer, Conda, Terraform, Dart/Flutter, NuGet, Playwright, Cypress, Puppeteer, Electron, Deno, Hugging Face, PyTorch, and sbt/Ivy

The measurement code processes small batches with `DispatchQueue.concurrentPerform` and guards the result dictionary with `NSLock`. Running every target at once thrashes the disk on machines with multi-gigabyte caches, so the batch size is capped at four. Fixed targets get a 12-second timeout; developer caches get 90 seconds because their file counts can be very high. Targets that do not exist are skipped before any process is launched.

Developer caches that live under `~/Library/Caches` are subtracted from `storage.app-caches`, but only when their own aggregate finding is above its reporting threshold. A cache below the threshold stays inside the app-cache total, so space never disappears from the report.

### Large files

```text
/usr/bin/find <Downloads> <Desktop> <Documents> <Movies> \
  -type f -size +1G \
  -not -path "*/.git/*" -not -path "*/Library/*" \
  -not -path "*/node_modules/*" -not -path "*/.venv/*" -not -path "*/Pods/*" \
  -not -path "*/build/*" -not -path "*/target/*" -not -path "*/vendor/*" \
  -exec /usr/bin/stat -f "%z|%N" {} +
```

Output is parsed as `size|path` and sorted. The finding reports the total, the count, and up to eight files. The scan is bounded by a 12-second timeout. A file named with a newline is an accepted edge case; the parser skips malformed lines. Developer artifact folders are excluded so a large dependency file is not counted both as a large file and as developer storage.

### Developer artifacts

`DevArtifactScanner` discovers rebuildable project folders under a fixed set of common developer roots (`~/Developer`, `~/Projects`, `~/Code`, `~/src`, `~/repos`, `~/workspace`, `~/Documents/GitHub`, `~/Documents/Projects`, and `~/Desktop`). It never walks the whole home directory.

```text
/usr/bin/find <roots> -maxdepth 5 \
  \( -name .git -o -name .hg -o -name .svn \) -prune -o \
  \( -type d \( <artifact names> \) -prune -print \)
```

- `-prune` on both metadata and artifact folders prevents a `node_modules` inside another `node_modules` from being counted twice.
- The default depth is 5; the opt-in deep mode raises it to 8 and expands evidence to nested project rows.
- Ambiguous names (`target`, `build`, `vendor`) are validated against project markers before they are accepted.
- Discovery is capped at 500 folders. Measurement is batched with `DispatchQueue.concurrentPerform` (six at a time) and a 20-second `du -sk` timeout per folder, so one giant tree cannot block the rest.
- Evidence is grouped by the nearest repository root (`.git`/`.hg`) or the artifact's parent when the project is not a repository.

`DevCacheFindingBuilder` aggregates global package-manager caches by manager. It emits one finding instead of one per cache, and the cleanup steps de-duplicate identical commands (for example, pnpm store paths share `pnpm store prune`).

### App and service alternatives

`AlternativesScanner` runs its own `ps` snapshot and groups processes with `RunningApplicationInventory`:

- A process whose command contains `.app/` is grouped under its outer app bundle.
- `Contents/Info.plist` supplies the bundle identifier and display name.
- Processes without a bundle are grouped by executable name as services.

`AlternativeEvaluator` is pure and testable. It matches apps/services against `AlternativeCatalog.entries`, applies conservative savings ranges to the measured footprint, and emits findings only above the documented threshold. The estimate is never presented as a benchmark, and `reclaimableBytes` stays nil because the gain is memory/CPU, not disk.

The catalog is data: add an `AlternativeEntry` and a test rather than changing the evaluator. Full product rules are in [App & service alternatives](../product/alternatives).

### Protected apps

`AppInventory.protectedApps(runner:)` lists bundles that the user cannot remove:

```text
/System/Applications/*.app
/System/Applications/Utilities/*.app
/Applications/*.app with the restricted flag
```

System paths are protected by construction. For `/Applications`, Optimizr resolves symlinks (Safari points into `/System/Cryptexes`) and runs one `ls -ldO` over the directory to find the `restricted` flag. Sizes come from a single multi-path `du -sk` over only the protected bundles, so the check stays cheap even on a Mac with many apps.

The finding fires at ≥ 500 MB total, is informational, and carries no reclaimable bytes. The point is to make non-removable space visible, not to suggest deleting it.

### Time Machine

`tmutil listlocalsnapshots /` is parsed for `com.apple.TimeMachine` entries. The finding reports the count and the latest snapshot. No size is claimed, because public tooling does not expose a reliable per-snapshot size.

## Parsers

All parsers are pure static functions, which is why the test suite can run without special permissions:

| Parser | Input | Output |
| --- | --- | --- |
| `VMStatistics.parse` | `vm_stat` text | Page counts, page size, derived bytes |
| `SwapUsage.parse` | `sysctl vm.swapusage` | total/used/free bytes |
| `MemoryPressureParser` | `memory_pressure` | Free percentage |
| `ProcessSampleParser` | `ps` output | PID, RSS bytes, CPU %, name |
| `LoadAverageParser` | `sysctl vm.loadavg` | 1/5/15 minute loads |
| `ThermalState.parse` | `pmset -g therm` | Speed limit, warning level |
| `PowerSettingsParser` | `pmset -g` | Low Power Mode flag |
| `DuParser` | single-path `du -sk` | Bytes |
| `DuListingParser` | multi-path `du -sk` | Path-to-bytes map |
| `LargeFileParser` | `find`/`stat` output | Path and bytes |
| `DevArtifactInventory.parse` | `find` output plus file-system markers | Validated artifact paths, kinds, and repository roots |
| `DevArtifactInventory.summarize` | Measured artifacts | Total, project rows, nested count |

Parsers return `nil` or an empty array when the output is not recognizable. They do not throw and do not assert.

## Adding a finding

1. Choose a stable ID: `<category>.<slug>` (for example `storage.mail-downloads`).
2. Add a scanner block that gathers evidence. Reuse `runner.run`; do not spawn a shell.
3. Set severity from a documented threshold. Prefer a small helper over nesting ternaries.
4. Provide at least one remediation step. Use `.command` only when the command is genuinely useful and safe to present; include a warning in `detail` for anything destructive.
5. Set `reclaimableBytes` only when the finding is about space, and avoid double counting with existing targets.
6. Set `scope` to where the condition lives, not to who runs the fix.
7. Add evidence metrics that let a skeptical user verify the claim.
8. Add paths for Reveal in Finder when applicable.
9. Update the [findings catalog](../product/findings-catalog) and [roadmap](../roadmap).
10. Add a parser or scoring test if new parsing or math was introduced.
11. Run:

```bash
./scripts/optimizr test
./scripts/optimizr scan
```

## Performance budget

- Target: full scan under ~15 seconds on an SSD for a typical home directory.
- Each command is capped: most at 3–8 seconds, fixed storage targets at 12 seconds, developer caches at 90 seconds, and developer artifact folders at 20 seconds.
- Scanners run in parallel; one slow storage folder does not serialize memory and CPU analysis.
- Storage targets are measured in batches of four, and developer artifacts in batches of six, to avoid disk thrashing.
- The UI remains responsive throughout; a blocking scan is a bug.

Developer caches can contain hundreds of thousands of files (Bun and npm caches are common examples), so a developer-heavy Mac can take longer than the 15-second target on the first scan. The work is bounded by per-cache timeouts and a 500-folder artifact cap. If a target becomes slow (for example, a giant `~/Downloads`), prefer narrowing the search or lowering the timeout over removing the finding.

The app's **Show nested dev folders** toggle and the CLI's `--deep-dev` flag change only evidence detail and discovery depth. They do not change which cache paths are measured.

## Safety review checklist for a new scanner

- [ ] Does it mutate anything? It must not.
- [ ] Does it invoke a shell? It must not; use argument arrays.
- [ ] Does it read files it does not need? Minimize access.
- [ ] Can it hang? Every command needs a timeout.
- [ ] Does it expose user data? Process names and paths are already sensitive; do not add more.
- [ ] Is the remediation reversible or clearly labeled?
- [ ] Does the finding explain *why* the measurement matters?
- [ ] Is there a way for the user to verify the evidence?
