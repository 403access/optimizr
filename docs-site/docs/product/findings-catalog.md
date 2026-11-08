---
title: Findings catalog
sidebar_position: 2
---

# Findings catalog

This page is the contract between the scanners and the user. It documents every finding Optimizr can emit, the measurement that triggers it, the severity ladder, and the remediation shown in the app. Thresholds are constants in `app/Sources/OptimizrCore/Scanners.swift`; update this page when they change.

## Severity model

| Severity | Penalty | Meaning |
| --- | --- | --- |
| Critical | 18 | Immediate risk of degraded usability or data-creation failure |
| High | 11 | Clear, measurable drag; should be addressed soon |
| Medium | 6 | Worth fixing when convenient |
| Low | 2.5 | Housekeeping or a weak signal |
| Informational | 0 | A setting or state worth knowing about, not a defect |

Reclaimable bytes are estimates, displayed as "up to". They sum into the storage category total and the report total. Findings that are not about space carry no estimate.

## Memory

Memory pressure is computed as:

```
usedFraction  = 1 − (memory_pressure free percentage / 100)
swapFraction  = swap used / swap total
pressure      = clamp(usedFraction × 0.55 + swapFraction × 0.45, 0, 1)
```

Swap is weighted heavily because macOS only swaps under real pressure. A Mac can have little "free" memory and still be healthy thanks to caches; pressure is the better signal.

### `memory.pressure`

| | |
| --- | --- |
| Trigger | Computed pressure ≥ 0.35 |
| Severity | ≥ 0.85 critical · ≥ 0.70 high · ≥ 0.50 medium · otherwise low |
| Reclaimable | — |
| Evidence | Pressure %, memory free %, physical RAM, swap used, compressed bytes |

**Why it matters:** macOS compresses pages and writes them to swap when the working set exceeds RAM. Reading compressed or swapped pages is far slower than RAM, which shows up as spinning cursors, slow app switching, and laggy menus.

**Fixes:** quit the heaviest apps (browsers, Electron apps, VMs), inspect Activity Monitor's Memory tab, close and reopen long-running apps, and restart the Mac to clear swap and compressed memory.

### `memory.swap`

| | |
| --- | --- |
| Trigger | Swap used > 512 MiB |
| Severity | ≥ 8 GB or ≥ 80% critical · ≥ 4 GB or ≥ 55% high · ≥ 1 GB or ≥ 25% medium · otherwise low |
| Reclaimable | — |
| Evidence | Swap used, total, free, physical RAM |

**Why it matters:** sustained swap use means the working set is larger than physical memory. The fix is to reduce concurrent memory use, not to "clear" swap with a cleaner; macOS manages the swap file.

**Fixes:** find the largest memory owners, quit unused apps, restart to reset the working set, and keep fewer apps suspended indefinitely.

### `memory.top-process`

| | |
| --- | --- |
| Trigger | Largest RSS ≥ 10% of physical RAM **and** ≥ 1 GB |
| Severity | ≥ 40% critical · ≥ 25% high · ≥ 15% medium · otherwise low |
| Reclaimable | — |
| Evidence | Top five processes by RSS, with PID and memory; the leader is highlighted |

**Why it matters:** one process holding a large share of RAM can drive the whole system into compression and swap. RSS includes shared pages, so it is an upper-bound estimate.

**Fixes:** quit with ⌘Q (not just closing the window), restart the app if its footprint grows over time, and use force quit only when it is unresponsive. The detail view includes a `kill <pid>` command as a last resort; the app never runs it.

### `memory.compressor`

| | |
| --- | --- |
| Trigger | Compressed memory > 15% of physical RAM |
| Severity | ≥ 40% high · ≥ 25% medium · otherwise low |
| Reclaimable | — |
| Evidence | Compressed bytes, share of RAM, total RAM |

**Why it matters:** compression saves space but costs CPU time on every access. Large compressed memory means the system is working hard to fit the workload.

**Fixes:** reduce open apps, restart to reset the compressor.

## CPU

### `cpu.load`

| | |
| --- | --- |
| Trigger | 1-minute load average / core count ≥ 0.70 |
| Severity | ≥ 2.0× critical · ≥ 1.3× high · ≥ 0.9× medium · otherwise low |
| Evidence | 1/5/15-minute load, cores, per-core figure |
| Reclaimable | — |

**Why it matters:** load average counts runnable and uninterruptible processes. Near the core count means the CPU is fully booked; above it means work is queueing.

**Fixes:** inspect Activity Monitor's CPU tab, pause exports/builds/backups, review login items, and restart if load does not fall.

### `cpu.top-process`

| | |
| --- | --- |
| Trigger | Any process reports ≥ 40% CPU in `ps` |
| Severity | Leader ≥ 250% high · ≥ 120% medium · otherwise low |
| Evidence | Top five CPU processes with PID and percentage |
| Reclaimable | — |

**Why it matters:** values above 100% mean the process is using more than one core. `ps` percentages are lifetime averages, so they are a strong hint rather than an instantaneous reading.

**Fixes:** quit the app or its parent, restart the helper, and use Activity Monitor's sample function to see what it is doing.

### `cpu.thermal`

| | |
| --- | --- |
| Trigger | `pmset -g therm` reports CPU speed limit < 100% or a thermal warning level > 0 |
| Severity | Speed limit < 70% high · otherwise medium |
| Evidence | Speed limit, thermal warning level |
| Reclaimable | — |

**Why it matters:** sustained throttling means less performance for the same workload, usually due to cooling constraints, blocked vents, or a heavy sustained task.

**Fixes:** let the Mac cool, improve airflow, and inspect `pmset -g thermlog`. Short throttling bursts are normal.

### `cpu.low-power-mode`

| | |
| --- | --- |
| Trigger | `pmset -g` reports `lowpowermode 1` |
| Severity | Informational |
| Evidence | Mode |
| Reclaimable | — |

Low Power Mode intentionally reduces background activity and peak performance. Reported so that "why is it slower on battery?" has a visible answer. Disable in System Settings → Battery or with `sudo pmset -a lowpowermode 0`.

### `cpu.launch-items`

| | |
| --- | --- |
| Trigger | ≥ 6 third-party launch agents/daemons across `~/Library/LaunchAgents`, `/Library/LaunchAgents`, `/Library/LaunchDaemons` |
| Severity | ≥ 20 high · ≥ 10 medium · otherwise low |
| Evidence | Total count, counts by scope, up to eight labels and vendors |
| Reclaimable | — |

**Why it matters:** each agent is cheap alone, but collectively they wake the Mac, consume CPU, and prevent idle. Apple's own `com.apple.*` services are excluded.

**Fixes:** review System Settings → General → Login Items & Extensions, reveal the plists before changing anything, and prefer the app's own uninstaller. Use `launchctl` to inspect, not blindly delete.

### `cpu.uptime`

| | |
| --- | --- |
| Trigger | Uptime > 14 days |
| Severity | ≥ 30 days medium · otherwise low |
| Evidence | Uptime, days |
| Reclaimable | — |

**Why it matters:** long uptimes let apps leak memory, accumulate stale helpers, and postpone security updates. A restart resolves several findings at once.

**Fixes:** install pending updates, then restart with "Reopen windows" unchecked for a clean baseline.

## Storage

Disk usage is read from `attributesOfFileSystem` for `/`. Directory sizes use `du -sk`; large files use `find` + `stat`. Commands run with timeouts so a slow folder cannot hang the scan.

### `storage.disk-space`

| | |
| --- | --- |
| Trigger | Free space < 15% of the startup volume |
| Severity | < 5% critical · < 10% high · otherwise medium |
| Reclaimable | — (the individual storage findings carry estimates) |
| Evidence | Free, used, total, free share |

**Why it matters:** APFS needs free space to write, snapshot, and update files; a full disk also starves swap and can slow the whole system.

**Fixes:** clear the largest safe storage findings, empty the Trash, and open System Settings → General → Storage.

### Directory findings

| ID | Location | Reports at | High | Critical | Fix |
| --- | --- | --- | --- | --- | --- |
| `storage.app-caches` | `~/Library/Caches` minus Homebrew | 1 GB | 5 GB | 15 GB | Review, quit apps, remove app cache folders |
| `storage.homebrew` | `~/Library/Caches/Homebrew` | 500 MB | 2 GB | 5 GB | `brew cleanup --prune=all` |
| `storage.xcode-derived-data` | `~/Library/Developer/Xcode/DerivedData` | 1 GB | 5 GB | 15 GB | Quit Xcode, remove build products; Xcode rebuilds |
| `storage.xcode-device-support` | `~/Library/Developer/Xcode/iOS DeviceSupport` | 2 GB | 10 GB | 20 GB | Remove OS versions you no longer debug |
| `storage.xcode-archives` | `~/Library/Developer/Xcode/Archives` | 1 GB | 5 GB | 15 GB | Delete old archives in Xcode Organizer |
| `storage.simulators` | `~/Library/Developer/CoreSimulator/Devices` | 3 GB | 10 GB | 25 GB | `xcrun simctl delete unavailable`, erase old devices |
| `storage.ios-backups` | `~/Library/Application Support/MobileSync/Backup` | 2 GB | 10 GB | 30 GB | Manage backups in Finder |
| `storage.trash` | `~/.Trash` | 200 MB | 2 GB | 10 GB | Review, then empty |
| `storage.docker` | `~/Library/Containers/com.docker.docker` | 5 GB | 20 GB | 50 GB | `docker system prune -a --volumes` |

Severity for directory findings is **medium** at the report threshold, **high** at the high threshold, and **critical** at the critical threshold. The Homebrew size is subtracted from the general cache estimate so the two findings do not double count.

**Safety notes shown in the app:** caches are disposable but rebuilding them makes the next launch slower; Xcode rebuilds DerivedData automatically; archives and backups may be needed for symbolication or restore; Docker pruning can remove volumes.

### `storage.large-files`

| | |
| --- | --- |
| Trigger | Files ≥ 1 GB under Downloads, Desktop, Documents, or Movies, with a total ≥ 2 GB (or a single file ≥ 2 GB) |
| Severity | Total ≥ 50 GB critical · ≥ 15 GB high · ≥ 5 GB medium · otherwise low |
| Reclaimable | Sum of matched files |
| Evidence | Total, count, up to eight files with sizes and paths |

**Why it matters:** old installers, disk images, video exports, and extracted archives are the fastest way to recover a large chunk of space.

**Fixes:** review each file, move what you want to keep to external storage, delete the rest, and empty the Trash.

### `storage.local-snapshots`

| | |
| --- | --- |
| Trigger | `tmutil listlocalsnapshots /` returns one or more local snapshots |
| Severity | ≥ 5 medium · otherwise low |
| Reclaimable | — (not reliably sizeable) |
| Evidence | Count, latest timestamp |

**Why it matters:** APFS local snapshots hold onto deleted data between Time Machine backups and may consume significant space.

**Fixes:** list them, then ask macOS to thin them with `sudo tmutil thinlocalsnapshots / 20000000000 4`. Run a Time Machine backup first if the last one is old; snapshots are part of the safety net.

## What is intentionally not reported

- **"RAM in use" without pressure context.** Cached memory is healthy; reporting it as a problem would be misleading.
- **Every process above a trivial CPU threshold.** The finding is capped to a leader and a top-five list.
- **Filesystem noise.** `/System`, `/private`, and other protected or volatile locations are not suggested for deletion.
- **Apple system services.** `com.apple.*` launch items are excluded.
- **Third-party cleaner categories** such as "junk files" without a specific, reviewable location.

## Changing a threshold

1. Update the constant in `Scanners.swift`.
2. Update the table on this page and, if behavior changed, the roadmap entry.
3. Add or update a unit test for the parser or scoring helper if the change is mechanical.
4. Run `./scripts/optimizr test` and `./scripts/optimizr scan` before committing.
