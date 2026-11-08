---
title: Roadmap & changelog
sidebar_position: 8
---

# Roadmap & changelog

This page is the single source of truth for where Optimizr is going and what has already shipped. Every meaningful commit updates it, and each entry records the *why*, the change, and how it was validated.

## Vision

Make Mac performance **legible, actionable, and safe**. A user should be able to open one native app, see what is actually slow, understand the trade-off, and fix it without trusting a black box with destructive access.

## Product principles

1. **Read-only by design.** Observation must not require mutation rights.
2. **Explain before prescribing.** Evidence and mechanism first, commands second.
3. **Prioritize.** A ranked list beats a dashboard of charts.
4. **Local and quiet.** No account, telemetry, or network dependency.
5. **Ship documented.** Product, tech, and roadmap move together.

## Status at a glance

| Milestone | Status | Target |
| --- | --- | --- |
| Native scanner MVP (memory, CPU, storage) | ✅ Shipped | v0.1.0 |
| Prioritized findings, evidence, remediation | ✅ Shipped | v0.1.0 |
| Headless CLI with JSON/Markdown | ✅ Shipped | v0.1.0 |
| Docusaurus documentation | ✅ Shipped | v0.1.0 |
| Marketing site | ✅ Shipped | v0.1.0 |
| GitHub Pages deployment | ✅ Shipped | v0.1.0 |
| Public v0.1.0 app release | ✅ Shipped | v0.1.0 |
| Scan history and trends | 🟡 Next | v0.2.0 |
| Menu-bar mode and scheduled scans | 🟡 Next | v0.2.0 |
| Notarized, signed distribution | 🟡 Next | v0.2.0 |
| Interactive one-click fixes | ⚪ Later | v1.0 |
| Localization | ⚪ Later | v1.0 |

## Now

The current release is a **read-only auditor** with broad coverage and an opinionated report:

- 22 findings across three categories.
- Stable IDs, severity thresholds, evidence, references, and remediation steps.
- Category and free-text filtering; detail pane with Reveal in Finder and copyable commands.
- Markdown export from the app; JSON and Markdown from the CLI.
- 23 unit tests.
- One Pages artifact containing docs and marketing, deployed by GitHub Actions.

## Next (v0.2)

- [ ] **Scan history.** Persist reports locally (SQLite or JSON) and show deltas: swap over time, storage trend, recurring findings.
- [ ] **Menu-bar companion.** A small status item with score and a one-click rescan, without a Dock-only workflow.
- [ ] **Scheduled scans.** Opt-in weekly audit with a local notification; no background network.
- [ ] **More storage targets.** npm/pnpm/yarn caches, browser profile caches, Mail downloads, Logic/GarageBand libraries, Steam, old iOS runtimes.
- [ ] **Better process attribution.** Map launch items to running processes and responsible apps where possible.
- [ ] **Snapshot sizing.** Investigate APFS snapshot size reporting without shelling out to unsupported tools.
- [ ] **Notarization and a signed DMG.** Developer ID, hardened runtime, notarytool, and a release DMG.
- [ ] **UI polish.** Snapshot/visual tests, keyboard navigation, accessibility labels for every control.
- [ ] **Localization scaffolding.** String catalogs and a documented translation workflow.

## Later (v1.0)

- [ ] **Interactive fixes.** Narrowly scoped, reversible, explicitly confirmed actions (empty Trash, run Homebrew cleanup). Never a blanket "optimize" button.
- [ ] **Baselines and alerting.** Compare against a user-defined baseline and flag regressions.
- [ ] **Rule packs.** A documented format for custom thresholds and team-specific audits.
- [ ] **Intel and multi-OS validation matrix.** CI on Intel runners if available; support the current and previous two macOS versions.
- [ ] **Sandboxed distribution path.** Compatibility with App Sandbox/Mac App Store constraints, or a clear explanation of why not.
- [ ] **Report sharing.** Redaction options for paths and host names before export.

## Explicit non-goals

- A one-click cleaner that deletes without review.
- Antivirus, firewall, or malware scanning.
- A privileged helper or daemon.
- Cloud accounts, telemetry, or remote dashboards.
- Synthetic benchmarks presented as universal truth.

## Changelog

| Date | Area | Change | Commit |
| --- | --- | --- | --- |
| 2026-11-08 | Foundation | Monorepo, license, README, project layout | [`89b9368`](https://github.com/403access/optimizr/commit/89b9368) |
| 2026-11-08 | App | Native scanner MVP, UI, CLI, tests, bundling | [`28757e0`](https://github.com/403access/optimizr/commit/28757e0) |
| 2026-11-08 | Docs | Docusaurus product, engineering, and roadmap docs | [`e77d867`](https://github.com/403access/optimizr/commit/e77d867) |
| 2026-11-08 | Marketing | Static marketing site | [`09891a8`](https://github.com/403access/optimizr/commit/09891a8) |
| 2026-11-08 | CI/CD | GitHub Actions CI, Pages deploy, release packaging | [`ee69015`](https://github.com/403access/optimizr/commit/ee69015) |
| 2026-11-08 | CI fix | npm lockfile, manifest fix, pinned toolchain | [`3f4e4e9`](https://github.com/403access/optimizr/commit/3f4e4e9) |
| 2026-11-08 | Deployment | Docs and marketing live on GitHub Pages | [`0d0e195`](https://github.com/403access/optimizr/commit/0d0e195) |
| 2026-11-08 | Release | v0.1.0 app zip, checksum, and release notes | tag [`v0.1.0`](https://github.com/403access/optimizr/releases/tag/v0.1.0) |

### #foundation — Project foundation

**Why:** Establish a coherent repository before code, so the app, docs, and site evolve together and every later change has a place to be documented.

**What:** MIT license, README with positioning and quick start, `.gitignore` covering Swift/Node/build output, and the `app/`, `docs-site/`, `marketing/`, `scripts/`, and `.github/` layout.

**Validation:** `git status` clean after the initial commit; `.build`, `dist`, `node_modules`, and generated sites ignored.

### #scanner-mvp — Native scanner MVP

**Why:** The core user problem is opacity: people know the Mac is slow but not why, and cleaner apps ask for dangerous permissions without explaining the trade-off. The MVP proves that a read-only scanner can still be useful.

**What:**

- `OptimizrCore` with `ScanEngine`, `SystemProfiler`, three scanners, parsers, model, and Markdown export.
- Memory: pressure, swap, top RSS consumer, compressed memory.
- CPU: load per core, hot process, thermal throttling, Low Power Mode, third-party launch items, long uptime.
- Storage: low disk, app/Homebrew/Xcode/simulator/backup/Trash/Docker caches, large files, Time Machine snapshots.
- SwiftUI app with overview, category browser, detail pane, search/severity filters, copy commands, Reveal in Finder, export.
- `optimizr-scan` CLI with `--json` and `--markdown`.
- `ShellCommandRunner` with no shell, timeouts, temporary-file capture, `SIGTERM`/`SIGKILL`.
- 23 unit tests and a deterministic icon pipeline.
- `scripts/build-app.sh` producing an ad-hoc signed bundle.

**Validation:** `swift build`, `swift test` (23 passing), `swift run optimizr-scan` on a real Mac produced 10–11 findings and a valid report, `./scripts/build-app.sh` produced a launchable app.

**Docs:** [Architecture](tech/architecture), [Scanner engine](tech/scanner-engine), [Data model](tech/data-model), [Findings catalog](product/findings-catalog), [Safety & privacy](product/safety-and-privacy).

### #documentation-site — Docusaurus documentation

**Why:** A scanner's conclusions are only trustworthy if its thresholds and safety model are inspectable. Documentation is part of the product, not an afterthought.

**What:**

- Docusaurus 3.10 with a curated sidebar: Product, Engineering, Roadmap.
- Product docs: overview, findings catalog, safety/privacy, FAQ.
- Technical docs: architecture, scanner engine, data model, build/run, testing, deployment, contributing.
- Custom light/dark theme, strict broken-link checking, docs served at `/optimizr/docs/`.

**Validation:** `npm ci && npm run build` succeeds; all internal links resolve under the configured base path.

**Docs:** this site.

### #marketing-site — Marketing site

**Why:** The project needs a clear public explanation of what it is, what it refuses to do, and how to try it. The marketing page doubles as the top of the documentation funnel.

**What:**

- Dependency-free static site with a custom product mockup, category sections, safety section, CLI snippet, FAQ, and download/docs CTAs.
- Responsive layout, reduced-motion support, local icon assets, and relative links to `docs/`.
- Deployed from the same Pages artifact as the docs.

**Validation:** served locally at `http://localhost:4173/`; links resolve in the assembled artifact; no external asset dependencies.

### #deployment — CI and GitHub Pages

**Why:** Documentation and marketing must be verifiable from the repository, not a manual upload. The app should also be tested on every change and packaged on tags.

**What:**

- `ci.yml`: macOS Swift build/test/smoke, app bundle, docs build.
- `pages.yml`: npm docs build, marketing + docs assembly, Pages artifact, OIDC deploy.
- `release.yml`: tag-triggered test, bundle, zip, GitHub Release.
- Pages configured with GitHub Actions as the source.
- Public URLs: docs at `/optimizr/docs/`, marketing at `/optimizr/`.

**Validation:** workflow runs green; both URLs return the deployed content; `workflow_dispatch` can re-deploy.

### #public-deployment — Public deployment verified

**Why:** A documentation site and a marketing page only count if they are reachable from a clean browser at the URLs the product advertises.

**What:**

- GitHub Pages configured with GitHub Actions as the build source.
- `Deploy docs and marketing` run [`42477953402`](https://github.com/403access/optimizr/actions/runs/42477953402) deployed the combined artifact.
- `CI` run [`42477485253`](https://github.com/403access/optimizr/actions/runs/42477485253) passed the macOS build/test/smoke/bundle job and the docs build.
- Docs use `baseUrl: /optimizr/docs/`; the marketing site links to `docs/` relative to the artifact root.
- The docs build uses npm with a committed `package-lock.json`, avoiding the Bun bootstrap that stalled on the Pages runner.

**Validation:**

- `https://403access.github.io/optimizr/` → HTTP 200, custom CSS/JS and icons load.
- `https://403access.github.io/optimizr/docs/` → HTTP 200, Docusaurus CSS and assets load.
- Spot checks for `/docs/roadmap`, `/docs/product/overview`, `/docs/product/safety-and-privacy`, `/docs/tech/architecture`, and `/docs/tech/build-and-run` all return 200.
- Desktop and 390 px mobile screenshots were rendered from the live URLs.

**Docs:** [Deployment](tech/deployment).

### #release-v010 — v0.1.0 release

**Why:** The marketing page promises a download, and a source-only project should still ship a runnable artifact for people who do not want a toolchain.

**What:**

- Tag `v0.1.0` points at the documented `main` commit.
- The `Release` workflow ran `swift test`, built and ad-hoc signed the app bundle, zipped it with `ditto`, generated a SHA-256 checksum, and published a GitHub Release.
- Assets: `Optimizr-v0.1.0-macos.zip` (1.2 MB) and `.sha256`.
- The marketing Download CTA targets `releases/latest`.

**Validation:** release workflow run [`42478335968`](https://github.com/403access/optimizr/actions/runs/42478335968) succeeded; the release is public, non-draft, and both assets return HTTP 200. The zip is ad-hoc signed, not notarized; release notes state this.

## Decision log

| Decision | Alternatives considered | Why |
| --- | --- | --- |
| Read-only, copy-only commands | One-click auto-fix; privileged helper | Removes the highest-risk trust requirement; keeps the app reviewable |
| Swift Package Manager, no Xcode project | `.xcodeproj`, Tuist | Fewer generated files, clean CLI build, easy CI |
| Core library separate from SwiftUI | Scanner code inside the app target | Testability and a shared CLI |
| Average category scores | Sum all penalties; weighted score | One pathological category should not erase two healthy ones |
| No persistence in MVP | SQLite history from day one | Avoids migration burden while the finding model settles; history is the top v0.2 item |
| Docusaurus + static marketing in one artifact | Two Pages sites; separate repos | One deploy, shared domain path, relative links |
| No external Swift packages | Sparkle, swift-argument-parser, etc. | Minimal supply chain and build time; add only when justified |
| Ad-hoc signing for MVP | Developer ID + notarization | No certificate in the build environment; documented limitation |

## Success metrics

For v0.2 we will track, locally and in aggregate without telemetry:

- Scan completes in under 15 seconds on a typical SSD.
- ≥ 90% of findings include at least one remediation step and one evidence metric.
- Docs build has zero broken links.
- No destructive action is executable from the app.
- Test suite covers every parser and every scoring rule.
- Users can go from launch to a prioritized finding in under 10 seconds.

## How this page changes

Every commit includes a `Change:` trailer and updates the relevant section here. A roadmap entry is written in the same commit as the code it describes; it is never deferred. If a planned item is dropped, it moves to the decision log with the reason.
