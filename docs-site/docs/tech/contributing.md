---
title: Contributing
sidebar_position: 7
---

# Contributing

Optimizr is a small project with a deliberately strict bar: every change should be understandable, safe, and documented in the same commit.

## Definition of done

A change is complete when:

- [ ] The app builds and all tests pass.
- [ ] A live `optimizr-scan` still produces a valid report.
- [ ] New behavior is covered by a test when it is parser/scoring logic.
- [ ] Product behavior is documented or updated in `docs-site/docs/product/`.
- [ ] Technical behavior is documented or updated in `docs-site/docs/tech/`.
- [ ] The [roadmap](../roadmap) changelog has a new entry with the reason and validation.
- [ ] The commit is self-contained and the message explains *why*, not just *what*.

If a change is too large to describe in one roadmap entry, split it.

## Commit convention

Use a short imperative subject with a type prefix:

```
feat(app): add CPU thermal finding
fix(core): handle swap units in gigabytes
docs(tech): document command runner timeouts
ci: deploy marketing site with docs
build(app): sign the app bundle
test(core): cover large-file parsing
chore: initialize monorepo
```

### Trailers

Every commit ends with:

```
Change: <one-line product/engineering change>
Refs: roadmap#<anchor>
```

Example:

```
feat(app): add CPU thermal finding

Detect pmset thermal throttling and surface a remediation path.

Change: CPU thermal finding
Refs: roadmap#cputherm
```

The `Change` trailer is what the roadmap summarizes. The `Refs` trailer points to the roadmap section that was updated.

### What belongs in a commit

- One logical change.
- Its tests.
- Its docs and roadmap entry.

Do not mix formatting-only churn with behavior changes. Do not commit generated build output (`app/.build`, `dist`, `site`, `docs-site/build`).

## Branches and pull requests

The project currently ships from `main`, with short-lived branches for larger changes:

```bash
git switch -c feat/menu-bar
# work, test, document
git commit
git push -u origin feat/menu-bar
```

A pull request should include:

1. The problem and the approach.
2. Evidence (test output, CLI output, screenshots when UI changes).
3. Safety impact: does it read more data, add a command, or change a destructive recommendation?
4. Docs and roadmap updates.

## Code style

### Swift

- Swift 5 language mode target, macOS 14 deployment target.
- Core has no SwiftUI/AppKit imports; keep it testable and CLI-usable.
- Prefer small pure functions for parsing and threshold math.
- Every external command gets a timeout.
- Never invoke `/bin/sh`; pass executable + arguments.
- Keep user-facing text specific and calm. Explain the mechanism, not just the instruction.
- Use stable finding IDs; do not encode PIDs or timestamps.

### TypeScript / CSS

- Docusaurus config and sidebars are typed.
- Internal links use root-relative docs paths (for example `/product/overview`), never absolute production URLs.
- Custom CSS uses Infima variables and supports both light and dark modes.

### Shell

- `set -euo pipefail` in scripts.
- Quote paths.
- Fail with a clear message when a required artifact is missing.

## Adding a scanner or finding

Read [Scanner engine](./scanner-engine) first. The short version:

1. Gather evidence with a bounded, read-only command.
2. Parse it in a pure function.
3. Set a documented threshold and severity.
4. Provide remediation steps; mark destructive commands clearly.
5. Add the finding ID and threshold table to the [catalog](../product/findings-catalog).
6. Add a parser/threshold test.
7. Verify with `./scripts/optimizr scan` on a real Mac.
8. Update the roadmap.

### Safety review

Any new command must answer:

- Does it mutate the system? (must not)
- Can a user-controlled path reach a shell? (must not)
- Is there a timeout? (must)
- Is the output size bounded? (prefer yes)
- Is the finding's advice reversible or clearly warned?
- Is the evidence verifiable by the user?

## Documentation style

- Explain the *why* before the *how*.
- Prefer concrete numbers, file paths, and commands.
- Keep the [findings catalog](../product/findings-catalog) as the source of truth for thresholds.
- When behavior changes, update the doc in the same commit; do not leave a "TODO: docs".
- Use sentence case for headings, except products and proper nouns.

## Release process

1. Ensure `main` is green.
2. Update the version in `app/Resources/Info.plist` and the roadmap.
3. Run the full checklist in [Testing](./testing#manual-qa-checklist).
4. Tag:

```bash
git tag v0.2.0
git push origin v0.2.0
```

5. The release workflow builds, tests, packages, and attaches the app zip.
6. Verify the Pages deployment and the release asset.

## Reporting issues

Include:

- macOS version and Mac model.
- Optimizr version/commit.
- What the report said (redact paths if needed).
- The relevant command output if you are comfortable sharing it.

Security issues: see [Safety & privacy](../product/safety-and-privacy#reporting-a-security-issue).
