---
title: Product overview
sidebar_position: 1
---

# Product overview

## The problem

A Mac slows down for reasons that are invisible in normal use. Swap fills up after days of suspended apps. A background updater wakes every few minutes. Xcode quietly accumulates tens of gigabytes of derived data. The Finder says the disk is full, but it does not say what is safe to remove.

Most "cleaner" apps answer this with a scary number and a large button. That trades understanding for convenience, and it asks users to trust an opaque process with destructive access.

Optimizr takes the opposite approach: **audit broadly, explain precisely, and let the user execute**.

## What Optimizr does

Optimizr runs a read-only audit in three categories:

| Lens | Questions it answers | Example findings |
| --- | --- | --- |
| **Memory** | Is macOS compressing or swapping? Which apps own the working set? | Severe memory pressure, heavy swap use, a process holding 40% of RAM |
| **CPU** | Is work queueing? Is the chip throttling? What starts itself? | Load above core count, a runaway helper, thermal limit, 36 launch agents |
| **Storage** | Where did the space go, and what is safe to reclaim? | 97% full disk, 11 GB of caches, old simulators, multi-gigabyte installers |

Each finding carries:

- A **stable ID** so the same issue can be tracked across scans.
- A **severity** derived from thresholds documented in the [findings catalog](./findings-catalog).
- **Evidence** — the measurements that triggered the finding.
- An **estimated reclaimable size** when the finding is about disk space.
- A **resolution path** with numbered steps, Settings guidance, and copy-ready shell commands where appropriate.
- **References** to Apple documentation where behavior is system-defined.

## Report anatomy

The app has three surfaces:

1. **Overview** — host, OS, health score, live vitals, per-category scores, and the five highest-priority opportunities.
2. **Category browser** — a filterable list of findings for memory, CPU, or storage, with a detail pane.
3. **Finding detail** — evidence grid, explanation, step-by-step remediation, relevant paths with Reveal in Finder, and references.

Reports can be exported as Markdown from the app or printed as JSON by the CLI. Export is explicit; nothing is uploaded.

## Health score

The health score is a 0–100 summary. It is intentionally simple and transparent:

1. Every finding deducts points by severity: critical 18, high 11, medium 6, low 2.5, informational 0.
2. Each category score is `max(0, 100 − sum of penalties in that category)`.
3. The overall score is the rounded average of the three category scores.

Averaging keeps one pathological category from erasing two healthy ones. The category scores remain visible so the user can see where the problem is. The score is a prioritization aid, not a clinical measurement; it is not comparable between machines with different workloads.

| Score | Label |
| --- | --- |
| 90–100 | Excellent |
| 75–89 | Good |
| 55–74 | Needs attention |
| 30–54 | Poor |
| 0–29 | Critical |

## Who it is for

- **Developers** whose Macs accumulate Xcode, simulator, Docker, and Homebrew artifacts.
- **Power users** who keep dozens of tabs and apps open and want to know whether the machine is actually under pressure.
- **Support and IT folks** who need a portable, explainable audit to send to someone else.
- **Anyone** who wants to understand a slow Mac without handing a black box destructive access.

## Non-goals

Optimizr is explicitly **not**:

- A one-click cleaner. There is no "optimize now" button that deletes or kills things.
- An antivirus, firewall, or privacy auditor.
- A benchmark. It reads current state; it does not measure peak performance.
- A cloud service. There is no backend, account, or telemetry.
- A root-level system tuner. It runs as the current user and never installs a privileged helper.

## Design principles

### Read-only is a feature

The app's only mutation is the report it keeps in memory and the Markdown file the user explicitly exports. This makes the trust model simple: a scanner can be tried without risking data.

### Findings over metrics

A dashboard of charts is not advice. Each metric exists to support a finding with a recommended action. If a number is healthy, it appears as a vital, not as a fabricated problem.

### Honest estimates

Reclaimable sizes are estimates from `du` and `find` and are labeled "up to" in the UI. They describe what is present, not a guarantee of what a safe deletion will recover. Overlapping directories are subtracted where possible (for example, Homebrew is excluded from the general app-cache estimate).

### The user runs the commands

Commands are displayed in copy-only blocks. This avoids a permission-hungry privileged helper and keeps every destructive action an explicit, reviewable decision.

## Current limitations

- macOS 14 or newer. The code targets macOS 14 APIs and is tested on macOS 27 / Apple silicon.
- Some folders and processes are inaccessible without Full Disk Access; their sizes and names are skipped rather than guessed.
- Process CPU percentages come from `ps` and represent lifetime averages, not instantaneous samples. The UI says so.
- Local Time Machine snapshots cannot be sized reliably through public tooling; the finding reports count and asks macOS to thin them.
- Launch-item detection lists third-party plists but does not attribute them to a running process.

See the [roadmap](../roadmap) for planned work.
