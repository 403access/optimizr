---
title: Data model
sidebar_position: 3
---

# Data model

The model lives in `app/Sources/OptimizrCore/Models.swift`. Everything is `Codable` and `Sendable`, which keeps the CLI JSON export and future persistence straightforward.

## Core types

| Type | Purpose |
| --- | --- |
| `ScanCategory` | `memory`, `cpu`, `storage`; title, tagline, SF Symbol |
| `Severity` | `info`, `low`, `medium`, `high`, `critical`; ordered, with score penalty |
| `FindingScope` | `native`, `thirdParty`, `mixed`, `userData`; ownership of the condition |
| `Metric` | A labeled evidence value, optionally primary |
| `Reference` | A titled external URL |
| `RemediationStep` | A numbered action with detail, kind, and optional command |
| `Finding` | One optimization opportunity |
| `SystemSnapshot` | Dashboard-level measurements from the scan |
| `ScanReport` | Findings + snapshot + timestamps, with derived scoring and Markdown export |

## Finding

```swift
public struct Finding: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let category: ScanCategory
    public let title: String
    public let summary: String
    public let detail: String
    public let severity: Severity
    public let scope: FindingScope
    public let reclaimableBytes: Int64?
    public let metrics: [Metric]
    public let remediation: [RemediationStep]
    public let references: [Reference]
    public let paths: [String]
    public let tags: [String]
}
```

### Field contract

| Field | Rule |
| --- | --- |
| `id` | Stable `<category>.<slug>`; never derived from a PID or timestamp |
| `title` | Short, specific, often includes the number ("Only 25.8 GB free") |
| `summary` | One or two sentences explaining the consequence |
| `detail` | Deeper explanation: mechanism, trade-offs, when it matters |
| `severity` | Derived from documented thresholds; informational is allowed |
| `scope` | Who owns the condition: native, third-party, mixed, or user data |
| `reclaimableBytes` | Only for space findings; nil for memory/CPU and low-disk |
| `metrics` | Verifiable evidence; the detail view lays these out in a grid |
| `remediation` | Ordered; each step must be actionable on its own |
| `references` | Apple documentation or another stable authority |
| `paths` | Files/directories for Reveal in Finder |
| `tags` | Search and future filtering |

### Scope

`FindingScope` describes **where the condition lives**, not who runs the fix:

| Case | Meaning |
| --- | --- |
| `native` | A macOS/Apple-owned subsystem, setting, tool, or data store creates or manages the condition |
| `thirdParty` | The condition or artifact belongs to non-Apple software |
| `mixed` | Depends on which app the user runs, or a native location holding third-party data |
| `userData` | The user's own files rather than a vendor's software |

The UI shows a scope badge on every finding and offers a scope filter; the Markdown and JSON exports include the same value. A native finding can still require the user to quit an app or restart — the scope describes ownership of the mechanism, not the remedy.

### Stable IDs

| ID | Category |
| --- | --- |
| `memory.pressure` | Memory |
| `memory.swap` | Memory |
| `memory.top-process` | Memory |
| `memory.compressor` | Memory |
| `cpu.load` | CPU |
| `cpu.top-process` | CPU |
| `cpu.thermal` | CPU |
| `cpu.low-power-mode` | CPU |
| `cpu.launch-items` | CPU |
| `cpu.uptime` | CPU |
| `storage.disk-space` | Storage |
| `storage.app-caches` | Storage |
| `storage.homebrew` | Storage |
| `storage.xcode-derived-data` | Storage |
| `storage.xcode-device-support` | Storage |
| `storage.xcode-archives` | Storage |
| `storage.simulators` | Storage |
| `storage.ios-backups` | Storage |
| `storage.trash` | Storage |
| `storage.docker` | Storage |
| `storage.dev-node-modules` | Storage |
| `storage.dev-build-artifacts` | Storage |
| `storage.dev-package-caches` | Storage |
| `storage.large-files` | Storage |
| `storage.protected-apps` | Storage |
| `storage.local-snapshots` | Storage |

A finding's ID is not tied to its title or threshold. If a threshold changes, keep the ID; if the meaning changes fundamentally, add a new ID.

Developer findings are aggregates, not one finding per folder. `storage.dev-node-modules` covers all JavaScript dependency trees, `storage.dev-build-artifacts` covers rebuildable project output, and `storage.dev-package-caches` covers global package-manager caches. Their evidence is grouped by repository root by default; `ScanOptions.includeNestedDeveloperArtifacts` (the app's “Show nested dev folders” toggle and the CLI's `--deep-dev`) expands the evidence to individual nested projects. Matched artifact folders are pruned during discovery, so a `node_modules` inside another `node_modules` is never counted twice.

Alternative findings use a dynamic but stable pattern:

```text
memory.alternative.<entry-id>.<app-or-bundle-slug>
cpu.alternative.<entry-id>.<app-or-bundle-slug>
```

The entry ID comes from the catalog and the app slug from the bundle identifier or service name. No PID or timestamp is included, and the finding is always `scope: mixed`.

## Remediation

```swift
public enum RemediationKind: String, Codable, Sendable {
    case command   // copy-ready shell command
    case settings  // System Settings or app UI
    case manual    // human action
    case restart   // restart/sign-out
}
```

Commands are display strings. The app copies them; it never executes them. When a command is destructive or needs `sudo`, the surrounding `detail` says so.

## Severity and scoring

Penalties are fixed per severity, not per category:

```swift
critical 18 · high 11 · medium 6 · low 2.5 · info 0
```

Category score:

```swift
max(0, 100 - sum(penalties for that category))
```

Overall score:

```swift
round(average(memoryScore, cpuScore, storageScore))
```

This means a machine with 12 critical CPU findings still has a plausible overall score if memory and storage are clean, while the CPU card reads 0. The detail is more useful than a single collapsed number. See the [product overview](../product/overview#health-score).

Sorting is deterministic:

1. Severity descending.
2. Reclaimable bytes descending.
3. Title ascending (`localizedStandardCompare`).

## Snapshot

`SystemSnapshot` carries the vitals shown on the overview:

```swift
public struct SystemSnapshot: Codable, Sendable, Hashable {
    public var hostName: String
    public var osVersion: String
    public var physicalMemory: Int64
    public var memoryUsed: Int64
    public var memoryFreePercent: Double
    public var memoryPressure: Double        // 0...1
    public var swapUsed: Int64
    public var swapTotal: Int64
    public var cpuCount: Int
    public var loadAverages: [Double]
    public var uptime: TimeInterval
    public var diskTotal: Int64
    public var diskFree: Int64
}
```

Derived helpers:

- `memoryPressureLabel` — Relaxed / Moderate / Elevated / High / Severe.
- `diskUsedFraction`, `swapFraction`.
- `loadAverage1/5/15`.

The snapshot is a point-in-time sample, not a time series. It is deliberately not persisted in the MVP, so there are no migration concerns while fields evolve.

## Report

```swift
public struct ScanReport: Codable, Sendable, Hashable {
    public let startedAt: Date
    public let finishedAt: Date
    public let findings: [Finding]
    public let snapshot: SystemSnapshot
}
```

Derived API used by the UI and CLI:

```swift
report.totalReclaimableBytes
report.sortedFindings
report.findings(for: .storage)
report.count(for: .memory)
report.reclaimableBytes(for: .storage)
report.healthScore
report.score(for: .cpu)
report.scoreLabel()
report.markdown()
```

## Markdown export

`ScanReport.markdown()` produces a self-contained report with:

- Generated timestamp, host, OS, health score, and total reclaimable.
- A per-category summary.
- Every finding with severity, scope, summary, evidence metrics, numbered remediation, and fenced commands.
- A read-only footer.

The export is intentionally plain: it can be pasted into an issue, a note, or a support ticket without images or proprietary formatting.

## JSON export

`optimizr-scan --json` encodes a `ScanReport` with ISO-8601 dates and sorted keys. Example shape:

```json
{
  "findings": [
    {
      "id": "storage.app-caches",
      "category": "storage",
      "title": "App caches: 10.8 GB",
      "severity": "high",
      "scope": "mixed",
      "reclaimableBytes": 10830000000,
      "metrics": [
        { "label": "Reclaimable", "value": "10.8 GB", "isPrimary": true }
      ],
      "remediation": [
        {
          "title": "Clear caches",
          "detail": "Quit apps first…",
          "command": "rm -rf ~/Library/Caches/*",
          "kind": "command"
        }
      ],
      "tags": ["caches"]
    }
  ],
  "snapshot": { "hostName": "…", "osVersion": "…" },
  "startedAt": "2026-11-08T11:00:00Z",
  "finishedAt": "2026-11-08T11:00:09Z"
}
```

The actual output includes UUIDs for metric and step IDs. Consumers should key on `Finding.id`, not on array position.

## Evolution policy

- Adding an optional field is non-breaking for Codable consumers.
- Renaming or removing a field is a breaking change; update the docs and roadmap in the same commit.
- Adding a finding ID is additive.
- Changing a threshold does not require a schema change, but must be documented in the [findings catalog](../product/findings-catalog).
- No persistence means no on-disk migration is required in the MVP.

## Formatting helpers

`Format.bytes`, `Format.percent`, `Format.decimal`, `Format.uptime`, and `Format.relativeTime` centralize user-facing formatting. `ByteMath` provides binary-ish decimal constants and compact-unit parsing for `sysctl` swap values. Tests pin the tricky cases.
