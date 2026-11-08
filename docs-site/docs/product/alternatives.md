---
title: App & service alternatives
sidebar_position: 4
---

# App & service alternatives

Optimizr is a read-only auditor, but cleanup is not the only way to recover resources. When a running app or background service uses a meaningful amount of memory or CPU, and a well-established more efficient option exists, Optimizr emits an **alternative finding**.

The finding names the running app, the alternative, and the estimated resource gain. It never installs, removes, or switches anything.

## How a candidate is chosen

1. **Group processes.** Processes inside an app bundle are summed into one app. Processes without a bundle are grouped by executable name as services.
2. **Match the catalog.** The app's bundle identifier or the service's executable name is matched against a small, conservative catalog.
3. **Estimate the gain.** The measured memory and CPU footprint is multiplied by a typical savings range for that replacement.
4. **Apply a meaningful-gain threshold.** A finding is emitted only when the estimated gain is at least:
   - **Memory:** the larger of 250 MB or 2% of physical RAM.
   - **CPU:** 15 percentage points.
5. **Set a conservative severity.** Alternative findings are `low`, or `medium` when the estimated memory gain is at least 1.5 GB or the CPU gain is at least 80 points. They are never `high` or `critical`, because switching apps is optional.

## Catalog

The catalog is deliberately small. It includes only replacements where the efficiency difference is well established and the trade-offs are easy to explain.

| Running app or service | Alternative | Memory range | CPU range | Confidence |
| --- | --- | --- | --- | --- |
| Chrome, Chromium, Brave, Edge, Arc, Vivaldi, Opera | Safari | 25–45% | 15–35% | Typical |
| Firefox | Safari | 15–30% | 10–25% | Typical |
| Visual Studio Code, Cursor | Zed | 30–50% | 15–30% | Typical |
| Docker Desktop | OrbStack | 30–50% | 20–40% | Typical |
| VirtualBox | UTM | 10–25% | 20–40% | Workload-dependent |
| Google Drive, Dropbox, OneDrive | iCloud Drive | 20–40% | 10–25% | Workload-dependent |

The catalog is data, not logic. It lives in `AlternativeCatalog.entries` in `app/Sources/OptimizrCore/Alternatives.swift`, so new entries do not require changes to the evaluator.

## What the estimate means

The percentages describe a typical difference between the two options, not a benchmark of your machine. Optimizr applies the range to the footprint it measured:

```text
estimated memory gain = measured app memory × memory range
estimated CPU gain    = measured app CPU    × CPU range
```

For example, a Chromium browser using 2.8 GB would show an estimated memory gain of roughly 0.7–1.3 GB against Safari.

Three limits are intentional:

- **`ps` CPU is a lifetime average**, not an instantaneous sample, so CPU estimates are rougher than memory estimates.
- **Ranges, not guarantees.** Tabs, extensions, project size, containers, and file counts can move the result outside the range.
- **No reclaimable bytes.** Memory gains are not disk space and are not added to the storage total.

## What the finding shows

- Current memory and CPU across all processes in the app or service.
- The proposed alternative.
- Estimated memory and CPU gain ranges.
- Process count and confidence.
- A rationale, a caveat, and migration steps.
- A "compare under the same workload" step using Activity Monitor.

The finding never removes the current app. The migration steps explicitly tell you to keep it until the alternative covers your extensions, files, and collaboration needs.

## What it will not do

- Install or uninstall an app.
- Declare a universal winner. Alternatives are optional and workload-dependent.
- Suggest switching away from security software, system components, or an app your organization manages.
- Generate a generic "Electron is inefficient" warning. Only apps with a known, better-documented option are matched.

## Adding a catalog entry

1. Add an `AlternativeEntry` to `AlternativeCatalog.entries`.
2. Include bundle identifiers and/or executable names.
3. Set conservative memory and CPU ranges as fractions (`0.25...0.45`).
4. Explain the mechanism in `rationale` and the trade-off in `caveat`.
5. Provide migration steps for a safe trial.
6. Set `confidence` to `typical` or `workloadDependent`.
7. Add a matching/evaluation test.

## Limitations

- Only known alternatives are reported; the catalog is not exhaustive.
- Services without an app bundle are matched by executable name, which can miss renamed helpers.
- MDM-managed apps and system extensions are not classified.
- The ranges are heuristics. Treat them as a reason to measure, not as a promise.
