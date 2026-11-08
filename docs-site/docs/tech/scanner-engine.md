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

Each scanner returns findings only. Cross-cutting state such as the system snapshot is collected once by `SystemProfiler`, and the engine owns ordering and deduplication.

```swift
public struct ScanEngine: Sendable {
    public init(
        scanners: [any OptimizrScanner] = [
            MemoryScanner(), CPUScanner(), StorageScanner()
        ],
        runner: any CommandRunning = ShellCommandRunner()
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

The CLI and the app both call this method, so there is no second implementation to drift.

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

The measurement code uses `DispatchQueue.concurrentPerform` and guards the result dictionary with `NSLock`. Targets that do not exist are skipped before any process is launched.

### Large files

```text
/usr/bin/find <Downloads> <Desktop> <Documents> <Movies> \
  -type f -size +1G \
  -not -path "*/.git/*" -not -path "*/Library/*" \
  -exec /usr/bin/stat -f "%z|%N" {} +
```

Output is parsed as `size|path` and sorted. The finding reports the total, the count, and up to eight files. The scan is bounded by a 12-second timeout. A file named with a newline is an accepted edge case; the parser skips malformed lines.

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
| `DuParser` | `du -sk` | Bytes |
| `LargeFileParser` | `find`/`stat` output | Path and bytes |

Parsers return `nil` or an empty array when the output is not recognizable. They do not throw and do not assert.

## Adding a finding

1. Choose a stable ID: `<category>.<slug>` (for example `storage.npm-cache`).
2. Add a scanner block that gathers evidence. Reuse `runner.run`; do not spawn a shell.
3. Set severity from a documented threshold. Prefer a small helper over nesting ternaries.
4. Provide at least one remediation step. Use `.command` only when the command is genuinely useful and safe to present; include a warning in `detail` for anything destructive.
5. Set `reclaimableBytes` only when the finding is about space, and avoid double counting with existing targets.
6. Add evidence metrics that let a skeptical user verify the claim.
7. Add paths for Reveal in Finder when applicable.
8. Update the [findings catalog](../product/findings-catalog) and [roadmap](../roadmap).
9. Add a parser or scoring test if new parsing or math was introduced.
10. Run:

```bash
cd app
swift test
swift run optimizr-scan
```

## Performance budget

- Target: full scan under ~15 seconds on an SSD for a typical home directory.
- Each command is capped: most at 3–8 seconds, storage commands at 12 seconds.
- Scanners run in parallel; one slow storage folder does not serialize memory and CPU analysis.
- The UI remains responsive throughout; a blocking scan is a bug.

If a target becomes slow (for example, a giant `~/Downloads`), prefer narrowing the search or lowering the timeout over removing the finding.

## Safety review checklist for a new scanner

- [ ] Does it mutate anything? It must not.
- [ ] Does it invoke a shell? It must not; use argument arrays.
- [ ] Does it read files it does not need? Minimize access.
- [ ] Can it hang? Every command needs a timeout.
- [ ] Does it expose user data? Process names and paths are already sensitive; do not add more.
- [ ] Is the remediation reversible or clearly labeled?
- [ ] Does the finding explain *why* the measurement matters?
- [ ] Is there a way for the user to verify the evidence?
