---
title: Safety & privacy
sidebar_position: 3
---

# Safety & privacy

Optimizr asks for less trust than a typical cleaner, and it tries to earn that with a narrow design.

## The read-only guarantee

| Optimizr does | Optimizr does not |
| --- | --- |
| Read system counters (`vm_stat`, `memory_pressure`, `sysctl`) | Delete, move, or modify files |
| Read process metadata with `ps` | Terminate, suspend, or signal processes |
| Read launch-agent plists | Load, unload, enable, or disable services |
| Measure directory sizes with `du` | Empty the Trash or caches |
| List Time Machine snapshots | Delete or thin snapshots |
| Write a report only when you export it | Upload anything, anywhere |

There is no "optimize" button because there is no mutation path. The only file the app writes is the Markdown report you explicitly save.

## Network

The app has **no networking code**. There is no analytics SDK, no crash reporter, no update checker, and no account. You can verify this by searching the source for `URLSession`, `Network`, or `NWConnection`; none are used.

The documentation and marketing sites are static pages. Reading them is a normal web request to GitHub Pages; the app itself never contacts them.

## How commands are executed during a scan

The scanner needs data from a small set of Apple utilities. It invokes them **directly, without a shell**, with a fixed executable path and an argument array:

```swift
runner.run("/usr/bin/vm_stat", arguments: [], timeout: 5)
runner.run("/usr/bin/du", arguments: ["-sk", url.path], timeout: 12)
```

`ShellCommandRunner` captures stdout and stderr through temporary files (so a chatty process cannot deadlock a pipe), enforces a timeout, terminates the child if necessary, and deletes the capture files. User-controlled paths are passed as arguments, never interpolated into a shell string.

### Commands shown in remediation

The commands in finding details are **display-only**. They are selected for transparency and reproducibility. The app copies them to the clipboard; you decide whether to run them.

Some are destructive or require administrator rights, and are presented with that context:

- `rm -rf ~/Library/Caches/*` — caches are rebuildable, but quit apps first.
- `rm -rf ~/.Trash/*` — permanent deletion.
- `rm -rf .../Xcode/iOS DeviceSupport/*` — Xcode regenerates support files for connected devices.
- `docker system prune -a --volumes` — removes unused images and volumes.
- `sudo tmutil thinlocalsnapshots ...` — requires an admin password.
- `sudo pmset -a lowpowermode 0` — requires an admin password.

> **Review before running.** Optimizr cannot know whether an archive, backup, or Docker volume matters to you. The app surfaces the location and the trade-off; the decision remains yours.

## Permissions and privacy

### What Optimizr can see

Optimizr runs as your user, outside the App Sandbox, with ordinary user permissions. It can read:

- System-wide memory and CPU counters.
- Process names, PIDs, RSS, and CPU percentages for your user's processes and other readable processes.
- Your home directory paths and the sizes of directories you can read.
- Launch agent and daemon plists that are world-readable.

### What it cannot see

- Files inside folders protected by TCC (Desktop, Documents, Downloads, removable volumes) may be partially or fully inaccessible until you grant access. The scanner skips what it cannot read rather than estimating.
- Other users' home directories and protected system paths.
- Contents of encrypted volumes that are not mounted.

Optimizr does **not** request Full Disk Access, Accessibility, Automation, or Screen Recording. If a folder is unreadable, the corresponding size may be incomplete; the report does not pretend otherwise.

### Data handling

- Scan results live in memory in the running app.
- Exported Markdown and JSON contain host name, OS version, process names, and file paths. Treat an exported report as potentially sensitive; it is a snapshot of your machine.
- There is no background collection between scans.
- There is no persistence beyond the current app session (the app does not currently store scan history).

## Threat model

| Risk | Mitigation |
| --- | --- |
| Command injection through a file path | No shell; fixed executables; argument arrays |
| A scanner hanging the UI | Scanners run off the main actor, each command has a timeout |
| A malicious plist | Read with `PropertyListSerialization`; only the `Label` string is used |
| Oversized command output | Captured to temporary files, removed after the call |
| Accidental destructive action | The app has no execute path for remediation commands |
| Leaking scan data | No network access, no telemetry, no implicit export |

## A note on "cleaner" advice

Some widely repeated Mac advice is not supported by how macOS works:

- **"Free RAM is good RAM."** Unused RAM is wasted RAM. macOS uses it for caches. Pressure and swap are the signals that matter.
- **"You must clear swap manually."** macOS manages the swap file. A restart is the supported way to reset it.
- **"Delete system caches to speed up boot."** macOS rebuilds them; deleting protected caches can cause instability and is not recommended.
- **"Disable SIP / run a root cleaner."** Optimizr deliberately has no privileged helper and does not ask you to weaken system protections.

## Reporting a security issue

Please do not open a public issue for a vulnerability. Contact the maintainer through the GitHub profile linked in the repository, or open a minimal issue asking for a private channel. Include the app version, macOS version, and reproduction steps.
