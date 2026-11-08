---
title: Build & run
sidebar_position: 4
---

# Build & run

## Requirements

| Tool | Minimum | Used for |
| --- | --- | --- |
| macOS | 14 Sonoma | App deployment target |
| Xcode / Swift | Swift 6.0 toolchain | Building the package |
| Node.js | 20 | Docusaurus |
| Python + Pillow | 3.10 + Pillow 10 | Regenerating the app icon only |

The project is developed with Xcode 27 / Swift 6.4 on Apple silicon, but the package declares macOS 14 and Swift 5 language mode.

## Task runner

Use `scripts/optimizr` instead of spelling out build commands:

| Task | Command |
| --- | --- |
| Build + install to `/Applications` + launch | `./scripts/optimizr install` |
| Install without launching | `./scripts/optimizr install --no-launch` |
| Build `dist/Optimizr.app` | `./scripts/optimizr build` |
| Run the local dist build | `./scripts/optimizr run` |
| Test | `./scripts/optimizr test` |
| Test then live scan | `./scripts/optimizr test --scan` |
| Headless scan | `./scripts/optimizr scan` |
| Docs dev server | `./scripts/optimizr docs` |
| Combined docs + marketing preview | `./scripts/optimizr site` |
| Regenerate the icon | `./scripts/optimizr icon` |
| Clean build output | `./scripts/optimizr clean` |
| Remove the `/Applications` copy | `./scripts/optimizr uninstall` |

`./scripts/optimizr help` lists the options. Each command delegates to a focused script in `scripts/`, which can be invoked directly.

## Run the app

```bash
./scripts/optimizr run
```

Or, for a raw SwiftPM run without packaging:

```bash
cd app
swift run Optimizr
```

The first build resolves no external dependencies, so it is fast. A window opens and starts a scan automatically.

## Install to Applications

```bash
./scripts/optimizr install
```

`install-app.sh` builds the bundle, quits any running copy, copies it to `/Applications/Optimizr.app`, verifies the code signature, and launches it. If `/Applications` is not writable, it stops with a clear message instead of silently escalating.

```bash
./scripts/optimizr install --no-launch
./scripts/optimizr install --skip-build
./scripts/optimizr uninstall
```

## Build an app bundle

```bash
./scripts/optimizr build
open dist/Optimizr.app
```

`build-app.sh`:

1. Runs `swift build -c release --product Optimizr`.
2. Assembles `dist/Optimizr.app/Contents/{MacOS,Resources}`.
3. Copies `Info.plist` and `AppIcon.icns`.
4. Ad-hoc signs the bundle with `codesign --force --deep --sign -`.

Use a different configuration if needed:

```bash
CONFIGURATION=debug ./scripts/optimizr build
```

### Why ad-hoc signing?

There is no Apple Developer ID in the build environment, so the bundle is signed locally. Gatekeeper may warn on another Mac. Right-click → Open, or build from source. Notarization is a roadmap item.

## Headless CLI

```bash
./scripts/optimizr scan             # human-readable summary
./scripts/optimizr scan --json      # full report as JSON
./scripts/optimizr scan --markdown  # Markdown report
```

The release binary can be copied anywhere:

```bash
cp app/.build/release/optimizr-scan /usr/local/bin/
optimizr-scan --markdown > ~/Desktop/mac-report.md
```

The CLI uses the same `ScanEngine` as the app, so output is consistent.

## Run the documentation site

```bash
./scripts/optimizr docs
```

The script installs npm dependencies on first use and starts Docusaurus at `http://localhost:3100/optimizr/docs/`. Force a reinstall with `--install`.

Docusaurus is configured with:

```ts
url: 'https://403access.github.io',
baseUrl: '/optimizr/docs/',
```

Local development serves the site under `/optimizr/docs/`, matching production. If you change `baseUrl`, also change the marketing link and the deployment workflow.

Build and serve the production output:

```bash
npm run build
npm run serve
```

## Preview the combined sites

```bash
./scripts/optimizr site
```

This builds Docusaurus, assembles the exact Pages layout under `.preview/optimizr/`, and serves it at production paths:

- `http://localhost:4173/optimizr/`
- `http://localhost:4173/optimizr/docs/`

Use `--port` to change the port and `--no-build` to reuse the current docs build.

If you serve the artifact at `/` instead, the docs HTML will load without its CSS because Docusaurus emits asset URLs under `/optimizr/docs/`.

## Regenerate the icon

The SVG in `app/Resources/Icon.svg` is the visual source of truth. The deterministic renderer is:

```bash
./scripts/optimizr icon
```

This writes `app/Resources/AppIcon-1024.png` and `AppIcon.icns` and requires Pillow. It is not part of the normal build; the generated `.icns` is committed so CI does not need Python imaging libraries.

## Environment variables

The build supports:

| Variable | Default | Purpose |
| --- | --- | --- |
| `CONFIGURATION` | `release` | SwiftPM build configuration for `build-app.sh` |

Example: `CONFIGURATION=debug ./scripts/optimizr build`.

There are no runtime secrets and no `.env` file. The app reads no configuration.

## Troubleshooting

### `swift build` fails with a target path error

The package expects `Sources/Optimizr`, `Sources/OptimizrCore`, `Sources/OptimizrScan`, and `Tests/OptimizrCoreTests`. Use `./scripts/optimizr build` (or pass `--package-path app` to SwiftPM).

### The app opens but the window is blank

The window uses a hidden title bar and a custom background. Make sure you are on macOS 14+; older systems cannot render the SwiftUI APIs used. Check Console for a crash report named `Optimizr`.

### Gatekeeper blocks the app

Use right-click → Open once, or build from source. Do not disable Gatekeeper globally. A notarized build is planned.

### A storage finding is missing

The relevant directory may not exist, may be unreadable, or the command may have hit its timeout. The scanner skips unreadable paths; it does not guess sizes.

### Docs build fails on `onBrokenLinks`

The configuration is strict on purpose. Fix the link or update the sidebar. Run `npm run build` in `docs-site/` locally before pushing.

### Port 3100 is in use

```bash
npm run start -- --port 3200
```

### Docusaurus cache issues

```bash
npm run clear && npm run build
```
