# Optimizr

**Find the drag. Fix the Mac.**

[Download for macOS](https://github.com/403access/optimizr/releases/latest) · MIT licensed · macOS 14+

Optimizr is a native macOS app that audits your Mac across three dimensions — **memory, CPU, and storage** — and turns the raw numbers into a prioritized list of concrete optimizations. Every finding explains what is happening, why it matters, how much space or performance it can recover, and the exact steps to resolve it.

> Status: v0.1.0 MVP. **Docs:** https://403access.github.io/optimizr/docs/ · **Site:** https://403access.github.io/optimizr/  
> See the [roadmap](docs-site/docs/roadmap.md) for what has shipped and what comes next.

## Why Optimizr

Most "cleaner" apps are opaque: they show a scary number and ask for permission to delete things. Optimizr is the opposite.

- **Read-only by default.** The scanner inspects your Mac; it never deletes, kills, or changes anything without you doing it yourself.
- **Explainable findings.** Each finding carries its evidence, severity, and a reproducible remediation recipe.
- **Three lenses, one report.** Memory, CPU, and storage are analyzed together so you can see the trade-offs.
- **Native and local.** SwiftUI, no telemetry, no network calls, no account.

## Project layout

```
app/                  Native macOS app (SwiftUI + Swift Package Manager)
docs-site/            Product, technical, and roadmap documentation (Docusaurus)
marketing/            Static marketing site
scripts/              Task runner: install, run, test, docs, icon, clean
.github/workflows/    CI and GitHub Pages deployment
```

## Install

```bash
./scripts/optimizr install
```

Builds the app, ad-hoc signs it, copies it to `/Applications/Optimizr.app`, verifies the signature, and launches it. Use `--no-launch` to install only, or `./scripts/optimizr uninstall` to remove it.

## Everyday commands

All common tasks go through one script:

| Task | Command |
| --- | --- |
| Install + launch | `./scripts/optimizr install` |
| Build only | `./scripts/optimizr build` |
| Run the local dist build | `./scripts/optimizr run` |
| Run tests | `./scripts/optimizr test` |
| Tests + live scan | `./scripts/optimizr test --scan` |
| Headless scan | `./scripts/optimizr scan --markdown` |
| Docs dev server | `./scripts/optimizr docs` |
| Combined docs + marketing preview | `./scripts/optimizr site` |
| Regenerate the icon | `./scripts/optimizr icon` |
| Clean build output | `./scripts/optimizr clean` |
| Uninstall | `./scripts/optimizr uninstall` |

Run `./scripts/optimizr help` for options. The focused helpers in `scripts/` can also be called directly.

Developer cleanup is included in every scan: `node_modules`, rebuildable project output across common toolchains (including Bun, pnpm, Yarn, Python, Rust, Java, Swift, Flutter, and more), and global package-manager caches. Evidence is grouped by project by default; pass `--deep-dev` to `./scripts/optimizr scan` (or enable **Show nested dev folders** in the sidebar) to expand nested projects.

### Iterate on the UI without a bundle

```bash
cd app
swift run Optimizr
```

## Documentation

- [Product overview](docs-site/docs/product/overview.md)
- [Findings catalog](docs-site/docs/product/findings-catalog.md)
- [Optimization guide](docs-site/docs/product/optimizations.md)
- [App & service alternatives](docs-site/docs/product/alternatives.md)
- [Architecture](docs-site/docs/tech/architecture.md)
- [Roadmap and changelog](docs-site/docs/roadmap.md)

Live on GitHub Pages:

- Docs: https://403access.github.io/optimizr/docs/
- Marketing: https://403access.github.io/optimizr/

Both are built from this repository and deployed by `.github/workflows/pages.yml`.

## Contributing

Every meaningful change should update the relevant docs and the roadmap changelog in the same commit. See [Contributing](docs-site/docs/tech/contributing.md).

## License

MIT © 2026 Oliver Molnar
