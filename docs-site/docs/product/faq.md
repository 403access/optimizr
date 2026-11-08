---
title: FAQ
sidebar_position: 4
---

# FAQ

### Is Optimizr a cleaner?

No. It is a read-only auditor that recommends fixes. There is no "optimize everything" button, because deleting files or killing processes without context is how cleaners cause damage. You review each finding and run the command or change the setting yourself.

### Does it need Full Disk Access?

No. It runs with your normal permissions. Some protected folders may be unreadable and are skipped. Granting Full Disk Access would improve size accuracy for Desktop/Documents/Downloads in some configurations, but the app works without it.

### Why does Activity Monitor show low free memory while Optimizr says pressure is fine?

macOS intentionally uses available RAM for file caches. "Free" memory is not the goal; pressure and swap are. If pressure is low, the system is managing fine even when free memory looks small.

### Why is my health score lower than I expected?

The score is a prioritization aid: it deducts fixed penalties per finding and averages the three category scores. A few high-severity items can move it a lot. It is not a benchmark and is not comparable across machines with different workloads. The category scores and the findings themselves are more actionable than the number.

### Can Optimizr fix findings automatically?

Not today, by design. Remediation commands are copy-only. A future version may add narrowly scoped, per-action confirmations for reversible operations, but not a blanket auto-fix.

### Does it collect telemetry?

No. There is no networking code in the app and no analytics. The only outbound requests are the ones your browser makes when you read this documentation or the marketing site.

### Why do some storage sizes look approximate?

Directory sizes come from `du` and are an estimate of what is present. File systems, hard links, snapshots, and permissions all affect accounting. Reclaimable values are labeled "up to"; the real recovery depends on what you delete and whether the Trash is emptied.

### Why is there no reclaimable size for swap or memory findings?

Swap and memory are not disk files you should delete. The fix is to reduce pressure (quit apps, restart), so those findings carry no byte estimate.

### Why does my Mac show huge swap but low memory pressure?

Swap can remain allocated from an earlier peak even after pressure falls. If pressure is moderate and the machine feels fine, swap alone is not urgent. The finding's severity reflects both absolute swap and the fraction of the swap file in use.

### Does it work on Intel Macs?

The code targets macOS 14+ and uses no Apple-silicon-only APIs. It is currently developed and tested on Apple silicon. Thermal reporting via `pmset -g therm` is most useful on Intel and Apple-silicon laptops; desktops may report no data.

### Why does the app have no Dock icon preference or menu bar mode?

It is a conventional windowed app in the MVP. A menu-bar mode and scheduled scans are candidates on the [roadmap](../roadmap).

### The app is unsigned / Gatekeeper complains. What do I do?

Local builds are ad-hoc signed by `scripts/build-app.sh`, not notarized with an Apple Developer ID. On first launch, right-click the app and choose Open, or build and run it from source with `swift run`. Do not disable Gatekeeper globally.

### How do I uninstall it?

Quit the app and delete `Optimizr.app`. It does not install a helper, launch agent, or preference pane. If you exported reports, delete them separately.

### How can I contribute?

See [Contributing](../tech/contributing). Every change should include product/technical docs and a roadmap entry, and every commit should be self-contained and reviewable.
