# Optimizr

**Find the drag. Fix the Mac.**

Optimizr is a native macOS app that audits your Mac across three dimensions — **memory, CPU, and storage** — and turns the raw numbers into a prioritized list of concrete optimizations. Every finding explains what is happening, why it matters, how much space or performance it can recover, and the exact steps to resolve it.

> Status: active development. See the [roadmap](docs-site/docs/roadmap.md) for what has shipped and what comes next.

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
scripts/              Build, bundling, and release helpers
.github/workflows/    CI and GitHub Pages deployment
```

## Quick start

### Run the app from source

```bash
cd app
swift run Optimizr
```

### Build a signed app bundle

```bash
./scripts/build-app.sh
open dist/Optimizr.app
```

### Run the documentation site

```bash
cd docs-site
bun install
bun run start
```

### Preview the marketing site

```bash
python3 -m http.server 4173 --directory marketing
```

## Documentation

- [Product overview](docs-site/docs/product/overview.md)
- [Findings catalog](docs-site/docs/product/findings-catalog.md)
- [Architecture](docs-site/docs/tech/architecture.md)
- [Roadmap and changelog](docs-site/docs/roadmap.md)

Once deployed, the docs live at `https://403access.github.io/optimizr/docs/` and the marketing site at `https://403access.github.io/optimizr/`.

## Contributing

Every meaningful change should update the relevant docs and the roadmap changelog in the same commit. See [Contributing](docs-site/docs/tech/contributing.md).

## License

MIT © 2026 Oliver Molnar
