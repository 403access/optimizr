---
slug: /
id: intro
title: Optimizr documentation
sidebar_position: 1
---

# Optimizr

**Find the drag. Fix the Mac.**

Optimizr is a native macOS utility that audits your Mac across memory, CPU, and storage, then turns the raw numbers into a prioritized, explainable list of optimizations. It is read-only by design: the app inspects your system and gives you the exact steps — and copy-ready commands — to fix what it finds. It never deletes files, terminates processes, or changes settings on its own.

<div className="docs-cards">
  <a className="docs-card" href="./product/overview"><strong>Product overview</strong><span>What Optimizr scans, how the health score works, and who it is for.</span></a>
  <a className="docs-card" href="./product/findings-catalog"><strong>Findings catalog</strong><span>Every check, its threshold, evidence, severity, and recommended fix.</span></a>
  <a className="docs-card" href="./product/optimizations"><strong>Optimization guide</strong><span>What, why, and how for each fix — with native vs third-party scope.</span></a>
  <a className="docs-card" href="./tech/architecture"><strong>Engineering</strong><span>Architecture, scanner engine, data model, build, test, and deployment.</span></a>
  <a className="docs-card" href="./roadmap"><strong>Roadmap & changelog</strong><span>What shipped, what is next, and the decision log behind the product.</span></a>
</div>

## Current status

| Area | State |
| --- | --- |
| macOS app | Working MVP — SwiftUI, macOS 14+, Apple silicon tested |
| Scanner coverage | 26 built-in checks plus contextual app-alternative findings, including developer artifacts and package caches |
| Automation | Read-only scans; no destructive actions |
| Tests | 43 unit tests covering parsers, developer artifact grouping, alternatives, scoring, and report export |
| Documentation | This Docusaurus site |
| Marketing site | Static site deployed alongside these docs |
| Deployment | GitHub Pages via GitHub Actions |

## Get started

Run the app from source:

Install it into Applications and launch:

```bash
./scripts/optimizr install
```

Or build and run the local bundle without installing:

```bash
./scripts/optimizr run
```

For a headless scan that can be scripted or used in CI:

```bash
./scripts/optimizr scan --json
```

All common tasks are available through `./scripts/optimizr help`.

- [Build and run details](./tech/build-and-run)
- [Read the net-new roadmap](./roadmap)
- [Browse all findings](./product/findings-catalog)
- [Understand each optimization](./product/optimizations)
- [Compare app and service alternatives](./product/alternatives)

## Principles

1. **Explain, don't scare.** A finding without evidence and a fix is just anxiety. Every check shows its numbers and a reproducible step.
2. **Read-only by default.** Observing a system should not require trusting a utility to mutate it. The user stays in control.
3. **Local and quiet.** No account, no telemetry, no network calls. The scanner runs with the user's existing permissions.
4. **Native over novelty.** SwiftUI and Foundation do the work; there are no runtime dependencies and no privileged helper.
5. **Document the change.** Every feature lands with product docs, technical docs, and a roadmap entry in the same commit.
