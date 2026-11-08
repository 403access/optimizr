---
title: Architecture
sidebar_position: 1
---

# Architecture

## Goals

- **A native, local macOS app** with no runtime dependencies and no privilege escalation.
- **Testable scanners.** Parsing and scoring are pure functions, separated from process execution.
- **Safe by construction.** No shell, no mutation, bounded command timeouts.
- **Docs and code in one repository**, deployed together.

## Layers

```
┌─────────────────────────────────────────────────────────────┐
│  Optimizr (SwiftUI executable)                              │
│  AppModel · ContentView · Sidebar · Overview · Category    │
│  FindingDetail · Components · Theme                         │
└──────────────────────────────┬──────────────────────────────┘
                               │ async ScanEngine.scan()
┌──────────────────────────────▼──────────────────────────────┐
│  OptimizrCore (library)                                     │
│                                                             │
│  ScanEngine ──► MemoryScanner ─┐                            │
│             ├─► CPUScanner     ├─► ShellCommandRunner        │
│             └─► StorageScanner ┘        │                    │
│                                         ▼                    │
│  SystemProfiler ──► SystemSnapshot    macOS utilities        │
│  Parsers: vm_stat, ps, sysctl, du, find, pmset, tmutil       │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│  OptimizrScan (CLI)  ── human summary / JSON / Markdown     │
└─────────────────────────────────────────────────────────────┘
```

SwiftUI depends on `OptimizrCore`. The core has no SwiftUI or AppKit imports, so it can be tested and used by the headless CLI. The CLI and app are thin shells over the same engine.

## Repository layout

```
app/
  Package.swift
  Sources/OptimizrCore/
    Models.swift           findings, severity, snapshot, report, Markdown
    Formatting.swift       byte/time formatting, size thresholds
    CommandRunner.swift    process execution, timeouts, paths
    SystemParsers.swift    vm_stat, swap, pressure, ps, load, therm, power
    SystemProfiler.swift   snapshot assembly, launch items, du/find parsers
    Scanners.swift         memory/CPU/storage scanners + ScanEngine
  Sources/Optimizr/
    OptimizrApp.swift      @main, window, menu commands
    AppModel.swift         observable state, navigation, export
    ContentView.swift      window shell, sidebar, overview
    CategoryView.swift     filters, finding list
    FindingDetailView.swift evidence, remediation, paths
    Components.swift       score ring, rows, metrics, command blocks
    Theme.swift            palette, background, surfaces
  Sources/OptimizrScan/
    ScanCLI.swift          --json / --markdown / summary
  Tests/OptimizrCoreTests/
  Resources/               Info.plist, icon source and .icns
docs-site/                 Docusaurus product, tech, roadmap
marketing/                 Static marketing site
scripts/                   build-app.sh, make-icon.py
.github/workflows/         CI, Pages deployment, release
```

## Scan flow

1. `AppModel.scan()` guards against concurrent scans and calls `ScanEngine.scan()`.
2. `ScanEngine` collects a `SystemSnapshot` on a detached user-initiated task:
   - `ProcessInfo` for RAM, cores, host, OS, uptime.
   - `vm_stat`, `memory_pressure`, `sysctl vm.swapusage`, `sysctl vm.loadavg`.
   - File-system attributes for disk capacity.
3. Scanners run concurrently in a task group, each on a detached task because they perform blocking process I/O.
4. Each scanner returns `[Finding]`. The engine deduplicates by stable ID, sorts by severity then reclaimable bytes, and packages a `ScanReport` with the snapshot.
5. Back on the main actor, `AppModel` publishes the report. SwiftUI re-renders; the overview, category lists, and detail view are all derived from the single report.

The UI never blocks on a subprocess: all process work is outside the main actor. A slow `du` or `find` is bounded by a per-command timeout, and the scan overlay communicates that work is in progress.

## Concurrency model

- `ScanEngine` is `Sendable`; scanners are `Sendable` value types.
- `ShellCommandRunner` is a stateless struct; each call creates its own `Process` and temporary files.
- The storage scanner measures directory sizes with `DispatchQueue.concurrentPerform` and protects the result dictionary with `NSLock`.
- `AppModel` is `@MainActor` and owns all UI state.

There are no shared mutable globals in the scanner path.

## Process execution

`ShellCommandRunner` is deliberately small and defensive:

| Concern | Approach |
| --- | --- |
| Shell injection | Never invokes `/bin/sh`; executable path + `[String]` arguments |
| Deadlock | stdout/stderr captured to temporary files, not pipes |
| Hangs | Poll until a deadline, send `SIGTERM`, then `SIGKILL` if needed |
| Environment | Fixed, explicit `PATH` including Homebrew; `LANG`/`LC_ALL` set |
| Cleanup | Capture files removed in a `defer` |
| Failure | Returns a `CommandResult`; scanners skip findings they cannot support |

A command failure is a data gap, not a crash. The UI simply shows fewer findings or omits a section.

## The app bundle

Swift Package Manager builds the executable. `scripts/build-app.sh` assembles:

```
Optimizr.app/
  Contents/
    Info.plist
    MacOS/Optimizr
    Resources/AppIcon.icns
```

The bundle is ad-hoc signed (`codesign --sign -`) for local distribution. Production notarization is on the [roadmap](../roadmap). The icon is generated deterministically by `scripts/make-icon.py` (Pillow), so it can be rebuilt without design tooling.

## Dependencies

| Layer | Dependency |
| --- | --- |
| App | SwiftUI, Foundation, AppKit, UniformTypeIdentifiers |
| Core | Foundation, Darwin (implicit via system APIs) |
| CLI | Foundation |
| Docs | Docusaurus 3.10, React 19, TypeScript |
| Marketing | Plain HTML/CSS/JS |
| Icon | Python 3 + Pillow |

There are no third-party Swift packages. The JavaScript dependencies are confined to the docs build.

## Design decisions

| Decision | Rationale |
| --- | --- |
| Read-only app, copy-only commands | Avoids a privileged helper and keeps destructive actions explicit |
| One shared core library | App and CLI stay in sync; parsers are unit-testable |
| Category scores averaged for overall health | A single bad lens does not erase the other two |
| Stable string finding IDs | Deduplication, roadmap references, future history |
| Per-command timeouts | Storage scans touch unbounded directory trees |
| No persistence in MVP | No schema/migration burden while the finding model evolves |
| Docusaurus deployed with marketing | One Pages artifact, one workflow, one URL namespace |

## Known architectural gaps

- Process sampling is a snapshot; there is no time series or history.
- `ps` CPU percentages are lifetime averages, not instantaneous.
- No sandboxed distribution or Mac App Store target.
- No localization yet; strings are inline English.
- Launch items are not attributed to running processes.
- Time Machine snapshots have count but no size.

These are intentionally visible in the [roadmap](../roadmap) rather than hidden.
