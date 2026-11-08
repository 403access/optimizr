---
title: Optimization guide
sidebar_position: 3
---

# Optimization guide

Every finding Optimizr emits is an optimization opportunity. The [findings catalog](./findings-catalog) defines the trigger and severity; this page explains each optimization in three layers:

- **What** the scanner actually measures.
- **Why** that measurement slows the Mac down.
- **How** to resolve it, including the trade-off and who owns the fix.

It also draws a deliberate line between **native** problems — state owned by macOS, Apple tooling, or Apple hardware — and **third-party** problems caused by non-Apple software. That distinction matters because the right fix is different: native issues are resolved with macOS controls or by reducing the workload, while third-party issues should be resolved with the vendor's own tooling or uninstaller.

## Native vs third-party: the dividing line

Two questions have different answers, so we track them separately:

1. **Who owns the condition?** macOS/Apple software, a third-party vendor, or your own workload and files.
2. **Who owns the fix?** A macOS control, the vendor's own tooling, or your judgment about apps and data.

The class below is based on the **condition**, not the fix. A native finding can still require you to quit an app or restart; macOS still owns the mechanism that is under pressure.

| Class | What it means | Typical fix owner | Findings |
| --- | --- | --- | --- |
| **Native** | A macOS/Apple-owned subsystem, setting, tool, or data store creates or manages the condition | macOS control, restart, or Apple tooling | `memory.pressure`, `memory.swap`, `memory.compressor`, `cpu.load`, `cpu.thermal`, `cpu.low-power-mode`, `cpu.uptime`, `storage.disk-space`, `storage.xcode-*`, `storage.simulators`, `storage.ios-backups`, `storage.trash`, `storage.protected-apps`, `storage.local-snapshots` |
| **Third-party** | The condition or artifact belongs to non-Apple software | The vendor's tooling or uninstaller | `cpu.launch-items`, `storage.homebrew`, `storage.docker` |
| **Mixed** | The condition depends on which app you run, or a native location holds third-party data | Your decision, then the app's own controls | `memory.top-process`, `cpu.top-process`, `storage.app-caches` |
| **User data** | The condition is your own files rather than a vendor's software | Your judgment | `storage.large-files` |

`cpu.load` is native: macOS owns the scheduler and the load accounting, even though your workload creates the number. It is listed with the native findings because the mechanism and the fix (reduce work or restart) are system-level.

### At a glance

| Finding | Created by | Fixed with | Class |
| --- | --- | --- | --- |
| `memory.pressure` | macOS memory manager + your workload | Quit apps, restart | Native |
| `memory.swap` | macOS swap + your workload | Reduce working set, restart | Native |
| `memory.top-process` | One app's footprint | Quit or restart that app | Mixed (app-dependent) |
| `memory.compressor` | macOS compressor | Reduce open apps, restart | Native |
| `cpu.load` | Your workload, measured by macOS | Pause/quit work | Native |
| `cpu.top-process` | One process | Quit or restart it | Mixed (app-dependent) |
| `cpu.thermal` | Hardware, cooling, firmware | Cool down, improve airflow | Native |
| `cpu.low-power-mode` | macOS battery setting | System Settings → Battery | Native |
| `cpu.launch-items` | Third-party login agents/daemons | Vendor uninstaller, Login Items | Third-party |
| `cpu.uptime` | Time since boot | Restart | Native |
| `storage.disk-space` | APFS free-space pressure | Clear storage findings | Native |
| `storage.app-caches` | Mostly third-party app caches | Quit apps, clear caches | Mixed |
| `storage.homebrew` | Homebrew downloads | `brew cleanup` | Third-party |
| `storage.xcode-*` | Xcode build artifacts | Xcode tools or `rm` | Native (Apple tooling) |
| `storage.simulators` | CoreSimulator devices | `simctl`, Xcode | Native (Apple tooling) |
| `storage.ios-backups` | Finder/iTunes device backups | Finder device management | Native (Apple data) |
| `storage.trash` | Your deleted files | Empty the Trash | Native (user data) |
| `storage.docker` | Docker images and volumes | `docker system prune` | Third-party |
| `storage.large-files` | Your downloads, exports, archives | Review and delete/move | User data |
| `storage.protected-apps` | SIP-protected app bundles | Leave in place; review their data | Native |
| `storage.local-snapshots` | APFS/Time Machine | `tmutil thinlocalsnapshots` | Native |

## Memory

Memory findings describe **native macOS behavior** responding to the apps you run. The system is not "broken"; it is compressing and swapping because the working set exceeds RAM. The fix is almost always to reduce concurrent memory use, not to run a "memory cleaner."

### `memory.pressure` — Memory pressure is elevated

**Class:** Native (macOS memory manager) · **Fix owner:** You · **Reclaimable:** none

**What.** Optimizr derives a 0–1 pressure score from the free-memory percentage and the share of swap in use:

```text
usedFraction = 1 − (memory_pressure free % / 100)
swapFraction = swap used / swap total
pressure     = clamp(usedFraction × 0.55 + swapFraction × 0.45, 0, 1)
```

This is a transparent proxy, not Apple's internal pressure level. It fires at ≥ 0.35 and escalates at 0.50, 0.70, and 0.85.

**Why.** When the working set exceeds physical RAM, macOS compresses pages and writes them to swap. Reading a compressed or swapped page back costs orders of magnitude more than reading RAM. That is the spinning cursor, the slow app switch, and the laggy menu.

**How.**
1. Quit apps you are not using, starting with browsers, Electron apps, and virtual machines.
2. Inspect Activity Monitor → Memory, sorted by Memory, to confirm the leaders.
3. If pressure stays high, restart. A restart clears swap and compressed memory and is the highest-leverage fix.

**Boundary.** The pressure *mechanism* is native, but the *cause* is your workload. A native app and a third-party app are treated the same: the one holding the most memory is the one to close.

### `memory.swap` — Swap is in use

**Class:** Native (macOS swap; workload cause) · **Fix owner:** You · **Reclaimable:** none

**What.** Swap used is read from `sysctl vm.swapusage`. The finding fires above 512 MiB and escalates by both absolute size (1, 4, 8 GB) and fraction of the swap file in use (25%, 55%, 80%).

**Why.** Swap is a safety valve, not a defect. Sustained swap means the working set is larger than RAM. macOS manages the swap file; deleting it or "clearing" it with a cleaner is not supported and does not fix the underlying pressure.

**How.**
1. Find the largest memory owners in Activity Monitor.
2. Quit or suspend apps you are not actively using.
3. Restart to reset the working set and let macOS release swap.

**Boundary.** Native mechanism, workload cause. Swap can remain allocated after an earlier peak even when pressure has fallen; severity therefore considers both absolute use and the fraction in use.

### `memory.top-process` — One app owns a large share of RAM

**Class:** Mixed (app-dependent) · **Fix owner:** The app's user · **Reclaimable:** none

**What.** Optimizr takes the process with the largest resident set size (RSS) from `ps`. It fires when that process holds at least 10% of physical RAM **and** at least 1 GB. RSS is an upper bound because it includes shared pages.

**Why.** One process holding a large share of RAM can push the whole system into compression and swap, even if every other app is small. The evidence lists the top five consumers so the leader has context.

**How.**
1. Quit the app with ⌘Q, not by closing its window.
2. Restart the app if its footprint grows over time.
3. Use Force Quit or `kill <pid>` only when the app is unresponsive; unsaved work may be lost.

**Boundary.** This finding is intentionally app-agnostic. The leader may be a native app or a third-party app. Optimizr names the process and PID; it does not assume the vendor.

### `memory.compressor` — Compressed memory is large

**Class:** Native · **Fix owner:** You · **Reclaimable:** none

**What.** Compressed bytes from `vm_stat`, compared with physical RAM. The finding fires above 15% of RAM and escalates at 25% and 40%.

**Why.** The compressor squeezes inactive pages instead of swapping them. That saves space but costs CPU time on every access. Large compressed memory means the machine is working hard to fit the workload into RAM.

**How.**
1. Reduce the number of open apps.
2. Restart to reset the compressor and swap.

**Boundary.** Entirely native behavior. There is no safe "decompress now" command; the only fixes are reducing demand or restarting.

## CPU

CPU findings separate **native system state** (thermals, power mode, uptime, load accounting) from **third-party background software** (launch agents and daemons).

### `cpu.load` — Work is queueing

**Class:** Native (macOS scheduler; workload cause) · **Fix owner:** You · **Reclaimable:** none

**What.** The 1-minute load average from `sysctl vm.loadavg`, divided by the core count. It fires at ≥ 0.70 per core and escalates at 0.90, 1.3, and 2.0.

**Why.** Load average counts runnable and uninterruptible processes. Near the core count means the CPU is fully booked; above it means work is waiting. Prolonged load also raises temperature and can trigger throttling.

**How.**
1. Open Activity Monitor → CPU and sort by % CPU.
2. Pause exports, builds, indexers, backups, or browser tabs running heavy scripts.
3. Review login items if load does not fall.
4. Let a legitimate long task finish rather than killing it; restart only as a fallback.

**Boundary.** macOS owns the measurement, but the load comes from whichever apps you run. The finding deliberately lists the top processes rather than blaming the system.

### `cpu.top-process` — One process is consuming CPU

**Class:** Mixed (app-dependent) · **Fix owner:** The app's user · **Reclaimable:** none

**What.** Any process reporting ≥ 40% CPU in `ps` becomes a candidate; the leader determines severity (≥ 250% high, ≥ 120% medium, otherwise low). Values above 100% mean more than one core.

**Why.** A busy process can starve the rest of the system, keep fans running, and prevent idle. `ps` percentages are lifetime averages, so they are a strong hint rather than an instantaneous sample.

**How.**
1. Quit the app if it is not needed; for a helper, quit the parent app.
2. Restart the app or the Mac if helpers persist.
3. Use Activity Monitor → gear menu → Sample Process to see what it is doing.

**Boundary.** App-dependent. A native indexer and a third-party sync client are diagnosed the same way. The finding reports the PID so you can verify the owner before acting.

### `cpu.thermal` — The CPU is throttled

**Class:** Native (hardware/firmware) · **Fix owner:** Environment and workload · **Reclaimable:** none

**What.** `pmset -g therm` reports the CPU speed limit and thermal warning level. The finding fires when the speed limit drops below 100% or a warning level is above 0; below 70% is high severity.

**Why.** Throttling protects the chip. Short bursts are normal, but sustained limits mean the cooling system is struggling: a heavy workload in a warm room, blocked vents, or dust on an older Mac. The result is less performance for the same work.

**How.**
1. Stop heavy exports or builds temporarily and let the fans catch up.
2. Use the Mac on a hard surface and keep vents unobstructed.
3. Inspect `pmset -g thermlog` to see whether throttling is sustained or a spike.

**Boundary.** Native. No third-party app causes throttling directly; it can only contribute workload or block airflow.

### `cpu.low-power-mode` — Low Power Mode is on

**Class:** Native setting · **Fix owner:** You · **Reclaimable:** none

**What.** `pmset -g` reports `lowpowermode 1`. Severity is informational, because this is a deliberate trade-off rather than a defect.

**Why.** Low Power Mode reduces background activity, display brightness, and CPU boost to save battery. On battery it is often the right choice; plugged in, it explains why some tasks feel slower.

**How.**
1. Open System Settings → Battery and set Low Power Mode to Never, or use Control Center.
2. Or run `sudo pmset -a lowpowermode 0` (administrator password required).

**Boundary.** Purely native. The finding exists so "why is it slower on battery?" has a visible answer.

### `cpu.launch-items` — Third-party background items are installed

**Class:** Third-party · **Fix owner:** The vendor or you · **Reclaimable:** none

**What.** Optimizr inventories plists in `~/Library/LaunchAgents`, `/Library/LaunchAgents`, and `/Library/LaunchDaemons`. It reads only the `Label`, excludes everything under `com.apple.*`, and reports at ≥ 6 items with severity escalating at 10 and 20. It lists up to eight labels and vendors.

**Why.** Each agent is cheap alone, but collectively they wake the Mac, consume CPU, and prevent idle. They are also easy to forget after an app is uninstalled.

**How.**
1. Review System Settings → General → Login Items & Extensions.
2. Reveal the plists in Finder before changing anything.
3. Prefer the app's own uninstaller for permanent removal.
4. Use `launchctl` to inspect, not blindly delete.

**Boundary.** The cleanest third-party finding in the product. Apple's own services are excluded by label, so every item listed is non-Apple software.

### `cpu.uptime` — The Mac has not restarted recently

**Class:** Native · **Fix owner:** You · **Reclaimable:** none

**What.** Uptime from `ProcessInfo.systemUptime`. It fires above 14 days; 30 days or more is medium severity.

**Why.** Long uptimes let apps leak memory, accumulate stale helpers, and postpone security updates. A restart resolves several findings at once.

**How.**
1. Install pending updates with `softwareupdate -l` (and then install them).
2. Restart with "Reopen windows when logging back in" unchecked for a clean baseline.

**Boundary.** Native. It is a proxy for accumulated drift, not a defect in macOS itself.

## Storage

Storage findings are where the native/third-party line matters most. Optimizr separates **Apple tooling and Apple data** from **third-party caches**, and both from **your own files**.

### `storage.disk-space` — The startup disk is nearly full

**Class:** Native (APFS; mixed causes) · **Fix owner:** You · **Reclaimable:** none directly

**What.** Free space from `attributesOfFileSystem(forPath: "/")`. The finding fires below 15% free, with high below 10% and critical below 5%.

**Why.** APFS needs free space to write, snapshot, and update files. A full disk also starves swap and slows the whole system. The individual storage findings carry the byte estimates; this finding is the umbrella warning.

**How.**
1. Clear the largest safe storage findings below.
2. Empty the Trash so deletion actually releases space.
3. Check System Settings → General → Storage for Apple's breakdown.

**Boundary.** Native filesystem pressure with mixed causes: third-party caches, Apple build artifacts, and your own large files all contribute.

### `storage.app-caches` — App caches

**Class:** Mixed (native location, mostly third-party data) · **Fix owner:** You · **Reclaimable:** measured

**What.** `du -sk ~/Library/Caches`, minus the Homebrew cache (reported separately to avoid double counting). Reports at 1 GB, high at 5 GB, critical at 15 GB.

**Why.** Apps store replayable data here so they start faster. It is designed to be disposable, but clearing it makes the next launch slower while caches rebuild.

**How.**
1. Quit apps first to avoid deleting a half-written cache.
2. Review `~/Library/Caches` and delete individual app folders if you want to be selective.
3. Or clear the whole folder with `rm -rf ~/Library/Caches/*`.

**Boundary.** The location is native macOS, but the contents are overwhelmingly third-party app data. This is not a place to delete Apple system caches; those are protected and not targeted.

### `storage.homebrew` — Homebrew download cache

**Class:** Third-party · **Fix owner:** Homebrew · **Reclaimable:** measured

**What.** `du -sk ~/Library/Caches/Homebrew`. Reports at 500 MB, high at 2 GB, critical at 5 GB.

**Why.** Homebrew keeps downloaded bottles and source archives so reinstalls are fast. Installed packages do not need them, and the cache can grow to many gigabytes.

**How.**
1. Run `brew cleanup --prune=all` to remove stale downloads and old versions.
2. Inspect `~/Library/Caches/Homebrew` if you want to review before deleting.

**Boundary.** Entirely third-party. If Homebrew is not installed, the finding never appears.

### `storage.xcode-derived-data` — Xcode DerivedData

**Class:** Native Apple tooling (developer-owned) · **Fix owner:** Xcode · **Reclaimable:** measured

**What.** `du -sk ~/Library/Developer/Xcode/DerivedData`. Reports at 1 GB, high at 5 GB, critical at 15 GB.

**Why.** DerivedData holds intermediate build products and indexes. Xcode recreates it on the next build, so it is one of the safest large caches to remove — at the cost of a slower first build.

**How.**
1. Quit Xcode.
2. Remove build products with `rm -rf ~/Library/Developer/Xcode/DerivedData/*`.
3. Rebuild; Xcode regenerates indexes and object files.

**Boundary.** Apple tooling, but not macOS system state. It is "native" in the sense that Apple owns the tool and the format; the data belongs to your projects.

### `storage.xcode-device-support` — iOS DeviceSupport files

**Class:** Native Apple tooling (developer-owned) · **Fix owner:** Xcode · **Reclaimable:** measured

**What.** `du -sk ~/Library/Developer/Xcode/iOS DeviceSupport`. Reports at 2 GB, high at 10 GB, critical at 20 GB.

**Why.** Each iOS release adds debug symbols and support files. Once you no longer debug on that OS version, the folder is dead weight.

**How.**
1. List folders with `ls -lh ~/Library/Developer/Xcode/iOS\ DeviceSupport`.
2. Remove versions for devices and OS releases you no longer test.
3. Xcode regenerates the folder for a connected device when needed.

**Boundary.** Apple tooling and Apple platform data. Keep the versions of devices you still test with.

### `storage.xcode-archives` — Xcode archives

**Class:** Native Apple tooling (developer-owned) · **Fix owner:** Xcode · **Reclaimable:** measured

**What.** `du -sk ~/Library/Developer/Xcode/Archives`. Reports at 1 GB, high at 5 GB, critical at 15 GB.

**Why.** Archives contain the app binary and dSYMs for a shipped build. They are needed for App Store resubmission and crash symbolication, so they are the least disposable Xcode artifact.

**How.**
1. Open Xcode → Window → Organizer → Archives to review dates and versions.
2. Delete archives for apps or versions you no longer support.
3. Reveal the folder in Finder if you prefer to inspect before deleting.

**Boundary.** Apple tooling. Unlike DerivedData, deleting an archive can remove your only copy of a shipped build's symbols; treat it as user data.

### `storage.simulators` — Simulator devices

**Class:** Native Apple tooling (developer-owned) · **Fix owner:** `simctl` / Xcode · **Reclaimable:** measured

**What.** `du -sk ~/Library/Developer/CoreSimulator/Devices`. Reports at 3 GB, high at 10 GB, critical at 25 GB.

**Why.** Every simulator keeps its own data, installed apps, and screenshots. Devices whose runtime has been uninstalled are pure dead weight.

**How.**
1. Run `xcrun simctl delete unavailable` to remove devices with missing runtimes.
2. Review remaining devices in Xcode → Window → Devices and Simulators.
3. Erase or delete simulators you no longer use.

**Boundary.** Apple developer tooling. Simulator data is regenerable, but app state inside a simulator may not be.

### `storage.ios-backups` — iPhone and iPad backups

**Class:** Native Apple data (user-owned) · **Fix owner:** You · **Reclaimable:** measured

**What.** `du -sk ~/Library/Application Support/MobileSync/Backup`. Reports at 2 GB, high at 10 GB, critical at 30 GB.

**Why.** Local Finder/iTunes backups can be many gigabytes each, and backups of replaced devices are easy to forget.

**How.**
1. Connect the device and open Finder.
2. Select the device → Manage Backups.
3. Review dates and delete backups you no longer need.

**Boundary.** Apple data, not Apple system bloat. Deleting the only backup of a device is irreversible; check dates first.

### `storage.trash` — The Trash still holds files

**Class:** Native (macOS Trash; user data) · **Fix owner:** You · **Reclaimable:** measured

**What.** `du -sk ~/.Trash`. Reports at 200 MB, high at 2 GB, critical at 10 GB.

**Why.** Files in the Trash still occupy disk space until the Trash is emptied. This is the most common reason "I deleted things but free space did not change."

**How.**
1. Open the Trash and restore anything you still need.
2. Empty it from Finder (`rm -rf ~/.Trash/*` is equivalent).
3. Remember that emptying is permanent.

**Boundary.** A native macOS mechanism holding your own files. Not third-party, and not safe to automate blindly.

### `storage.docker` — Docker data

**Class:** Third-party · **Fix owner:** Docker · **Reclaimable:** measured

**What.** `du -sk ~/Library/Containers/com.docker.docker`. Reports at 5 GB, high at 20 GB, critical at 50 GB.

**Why.** Docker's virtual disk holds images, containers, build caches, and volumes. It grows but does not shrink automatically when you delete containers.

**How.**
1. Inspect usage with `docker system df`.
2. Run `docker system prune -a --volumes` to remove unused images, containers, networks, and volumes.
3. Add `--volumes` only if you are sure no data volumes are needed; otherwise omit it.
4. If you no longer use Docker, uninstalling it is the bigger win.

**Boundary.** Entirely third-party. Pruning volumes can destroy database state; this is the highest-risk storage command in the product.

### `storage.large-files` — Large personal files

**Class:** User data (vendor-neutral) · **Fix owner:** You · **Reclaimable:** measured

**What.** `find` under Downloads, Desktop, Documents, and Movies for files ≥ 1 GB, excluding `.git` and `Library`. Reports when the total is ≥ 2 GB or a single file is ≥ 2 GB.

**Why.** Old installers, disk images, video exports, and extracted archives are the fastest way to recover a large chunk of space.

**How.**
1. Review the listed files in Finder.
2. Move what you want to keep to external or cloud storage.
3. Delete the rest and empty the Trash.

**Boundary.** Neither native nor third-party: these are your files. Optimizr does not classify them as junk, because only you know whether an export or archive still matters.

### `storage.protected-apps` — Protected apps you cannot uninstall

**Class:** Native (macOS/SIP) · **Fix owner:** Nobody (leave in place) · **Reclaimable:** none

**What.** Optimizr lists app bundles that live under `/System/Applications` or carry the `restricted` file flag in `/Applications`. It reports when the protected bundles total at least 500 MB, and shows the count, total, largest app, and up to eight apps with sizes.

**Why.** System Integrity Protection prevents deleting or modifying these bundles, even as an administrator, and macOS may relaunch required system apps automatically. They can occupy meaningful space, but that space is not recoverable by uninstalling. Showing them prevents protected apps from being mistaken for cleanup targets and explains why "just delete the app" does not work.

**How.**
1. Leave the bundles in place. Do not disable SIP or try to force-delete `/System` apps.
2. Review the app's user data in `~/Library/Containers`, `~/Library/Group Containers`, and `~/Library/Application Support` if you need space.
3. Use the app's own settings for downloads or caches, and System Settings → General → Storage for Apple's breakdown.

**Boundary.** The clearest "native, not actionable" finding. The app bundle is owned by macOS; only the data around it may be yours to manage. The finding is informational and carries no reclaimable bytes precisely because uninstalling is not an option.

### `storage.local-snapshots` — Time Machine local snapshots

**Class:** Native (APFS/Time Machine) · **Fix owner:** macOS · **Reclaimable:** not sized

**What.** `tmutil listlocalsnapshots /` filtered for `com.apple.TimeMachine` entries. Reports the count and latest timestamp; no byte estimate is claimed because public tooling does not expose a reliable per-snapshot size.

**Why.** APFS keeps local snapshots between Time Machine backups. They hold onto deleted data and may consume significant space until macOS thins them.

**How.**
1. List them with `tmutil listlocalsnapshots /`.
2. Run a Time Machine backup first if the last one is old; snapshots are part of the safety net.
3. Ask macOS to thin them with `sudo tmutil thinlocalsnapshots / 20000000000 4`.

**Boundary.** Native. Do not delete snapshots manually; thinning lets APFS reclaim space without breaking the backup chain.

## App and service alternatives

Not every optimization is a cleanup. Sometimes the better move is to run a more efficient tool.

### `memory.alternative.*` / `cpu.alternative.*` — A lighter alternative exists

**Class:** Mixed (app-dependent) · **Fix owner:** You · **Reclaimable:** none (memory/CPU gain, not disk)

**What.** Optimizr groups running processes into app bundles and services, then matches them against a small catalog of known alternatives. It applies a conservative savings range to the measured footprint and only emits a finding when the gain is meaningful: at least the larger of 250 MB or 2% of RAM, or at least 15 CPU points.

**Why.** A more efficient app can recover memory and CPU without deleting anything. Examples include a native browser instead of a Chromium browser, a native editor instead of an Electron editor, OrbStack instead of Docker Desktop, UTM instead of VirtualBox, and iCloud Drive instead of a third-party sync client. The full catalog and ranges are documented in [App & service alternatives](./alternatives).

**How.**
1. Read the rationale and caveat; feature differences can matter more than the estimated gain.
2. Try the alternative with the same tabs, project, containers, or files.
3. Compare memory and CPU in Activity Monitor.
4. Keep the current app until the alternative covers your extensions and workflows.

**Boundary.** Mixed: the condition is the app you chose to run, not macOS itself. The estimate is a range, not a benchmark, and the app is never removed automatically. `ps` CPU percentages are lifetime averages, so treat CPU estimates as directional.

## Choosing what to fix first

Use the class labels to decide where to spend effort:

1. **Third-party findings** are usually the cheapest wins: `brew cleanup`, `docker system prune`, and disabling unused login items are vendor-supported and reversible.
2. **Native storage findings** (Xcode, simulators, snapshots, Trash) recover the most space, but carry data-loss trade-offs. Read the safety note for each.
3. **Native memory/CPU findings** are symptoms of workload. Quitting apps and restarting resolves several at once; no cleaner can do it for you.
4. **Protected-app findings** are context, not a cleanup target. Do not disable SIP or force-delete system bundles; review their user data instead.
5. **Alternative findings** are optional switches. Test the alternative under the same workload and keep it only if it is actually better for you.

The app sorts by severity and then by reclaimable bytes, so the top of the report is already a reasonable order. The class label tells you whether the next step is a vendor command, a macOS setting, or a decision about your own data.
