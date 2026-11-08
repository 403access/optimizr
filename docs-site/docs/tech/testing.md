---
title: Testing
sidebar_position: 5
---

# Testing

## Running the suite

```bash
./scripts/optimizr test
```

The current suite has **32 tests** in three groups. They run in about a second because they exercise pure functions; they do not need special permissions, network access, or a particular machine state.

## What is covered

### Parsers (15 tests)

| Test | Protects |
| --- | --- |
| `testParsesVMStatistics` | Page-size header, page counters, derived bytes |
| `testRejectsUnrelatedOutput` | A parser must not invent a result |
| `testParsesSwapUsageInMegabytes` | Real `sysctl` format and fraction math |
| `testParsesSwapUsageInGigabytes` | Unit suffix handling |
| `testSwapParseFailsWithoutValues` | Missing data yields nil |
| `testParsesMemoryPressure` | Last-line percentage extraction |
| `testClampsMemoryPressure` | Percentages are clamped to 0…100 |
| `testParsesProcessSamples` | `ps` columns, RSS conversion, app-name shortening |
| `testSkipsMalformedProcessLines` | Garbage rows are ignored |
| `testParsesLoadAverage` | Braced sysctl format |
| `testParsesThermalState` | `pmset` speed limit and throttling flag |
| `testHealthyThermalState` | No false positive at 100% |
| `testParsesLowPowerMode` | `pmset` flag |
| `testParsesDuOutput` | Kilobyte-to-byte conversion |
| `testParsesLargeFiles` | `size|path` format and home abbreviation |

### Model and scoring (8 tests)

| Test | Protects |
| --- | --- |
| `testReportSortsBySeverityThenSize` | Priority ordering |
| `testReclaimableTotalsAreGroupedByCategory` | Totals and per-category sums |
| `testHealthScoreDropsWithSeverity` | Penalty math and averaging |
| `testHealthScoreAveragesCategoriesAndFloorsEachAtZero` | Category floor and overall average |
| `testMarkdownExportIncludesEvidenceAndCommands` | Export contract |
| `testSnapshotDerivedValues` | Pressure label, disk/swap fractions |
| `testSeverityThresholds` | Storage threshold helper |
| `testUptimeFormatting` | Human-readable durations |

## Why parser tests matter

The scanner is a long chain of assumptions about text produced by macOS utilities. A single column-order change in `ps` output or a locale difference in `sysctl` can silently produce a wrong finding. Parser tests pin the format and make the assumptions explicit.

Tests use realistic fixtures copied from macOS output, including Apple's period-terminated page counts and the `(encrypted)` suffix on swap usage.

## What is not covered yet

- Live scanner integration tests (they would depend on the host machine).
- SwiftUI view tests / snapshot tests.
- Permission-denied paths.
- Performance regression tests for `du` and `find`.
- A test for `LaunchItemInventory` (it currently reads fixed system paths, so it is not easily isolated).

These are candidates for a future test target and are listed on the [roadmap](../roadmap).

## Live smoke test

The headless CLI is the integration check:

```bash
./scripts/optimizr test --scan
./scripts/optimizr scan --json | python3 -m json.tool > /dev/null
```

On the development Mac, the expected result is a valid report with real findings — not an empty scan. An empty report on a machine that is clearly under pressure is a bug.

A safe CI smoke test runs the CLI and asserts that it exits successfully; CI runners may legitimately have no findings.

## CI

The `ci` workflow runs on macOS for pushes and pull requests:

1. `swift build`
2. `swift test`
3. `swift run optimizr-scan` (smoke)
4. `./scripts/build-app.sh` (bundle assembly)
5. Docs build with npm: `npm ci --no-audit --no-fund && npm run build`

The docs build is strict on broken links, so a broken documentation link fails CI.

## Adding tests

- Pure parsing logic → `ParserTests`.
- Scoring, sorting, totals, export → `ModelTests`.
- A new scanner should at least get a parser test if it parses text, and a threshold test if it computes severity.
- Name tests by behavior, not implementation (`testParsesSwapUsageInGigabytes`, not `testSwap2`).
- Use realistic fixture strings and include a malformed case.
- Do not depend on the current time, the user's home directory contents, or the host's load.

## Manual QA checklist

Before a release:

- [ ] Launch the app on a clean profile; the first scan completes without a beachball.
- [ ] Overview shows host, OS, score, vitals, category cards, and top opportunities.
- [ ] Each category lists findings; filtering by text and severity works.
- [ ] Selecting a finding updates the detail pane.
- [ ] Copy command puts the exact command on the clipboard.
- [ ] Reveal in Finder opens the containing folder.
- [ ] Export produces a readable Markdown file.
- [ ] Rescan preserves the current category and selection when possible.
- [ ] The app does not request network, Accessibility, or Full Disk Access.
- [ ] Quit the app; no helper process remains.
- [ ] Run the headless CLI and confirm valid JSON.
