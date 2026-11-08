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
| Bun (optional) | 1.2+ | Faster docs installs; npm works too |
| Python + Pillow | 3.10 + Pillow 10 | Regenerating the app icon only |

The project is developed with Xcode 27 / Swift 6.4 on Apple silicon, but the package declares macOS 14 and Swift 5 language mode.

## Run the app

```bash
cd app
swift run Optimizr
```

The first build resolves no external dependencies, so it is fast. A window opens and starts a scan automatically.

## Build an app bundle

```bash
./scripts/build-app.sh
open dist/Optimizr.app
```

`build-app.sh`:

1. Runs `swift build -c release --product Optimizr`.
2. Assembles `dist/Optimizr.app/Contents/{MacOS,Resources}`.
3. Copies `Info.plist` and `AppIcon.icns`.
4. Ad-hoc signs the bundle with `codesign --force --deep --sign -`.

Use a different configuration if needed:

```bash
CONFIGURATION=debug ./scripts/build-app.sh
```

### Why ad-hoc signing?

There is no Apple Developer ID in the build environment, so the bundle is signed locally. Gatekeeper may warn on another Mac. Right-click → Open, or build from source. Notarization is a roadmap item.

## Headless CLI

```bash
cd app
swift run optimizr-scan             # human-readable summary
swift run optimizr-scan --json      # full report as JSON
swift run optimizr-scan --markdown  # Markdown report
```

The release binary can be copied anywhere:

```bash
cp app/.build/release/optimizr-scan /usr/local/bin/
optimizr-scan --markdown > ~/Desktop/mac-report.md
```

The CLI uses the same `ScanEngine` as the app, so output is consistent.

## Run the documentation site

```bash
cd docs-site
bun install          # or npm install
bun run start        # http://localhost:3100/optimizr/docs/
```

Docusaurus is configured with:

```ts
url: 'https://403access.github.io',
baseUrl: '/optimizr/docs/',
```

Local development serves the site under `/optimizr/docs/`, matching production. If you change `baseUrl`, also change the marketing link and the deployment workflow.

Build and serve the production output:

```bash
bun run build
bun run serve
```

## Preview the marketing site

```bash
python3 -m http.server 4173 --directory marketing
```

Open `http://localhost:4173/`. The docs link points to `./docs/`, which only exists in the assembled Pages artifact. To preview the combined site locally at the same paths as production:

```bash
# Build docs
cd docs-site && bun run build && cd ..

# Assemble the same layout the workflow deploys
rm -rf site && mkdir -p site
cp -R marketing/. site/
cp -R docs-site/build site/docs
touch site/.nojekyll

# Serve it under /optimizr/ because Docusaurus uses baseUrl /optimizr/docs/
rm -rf .preview && mkdir -p .preview/optimizr
cp -R site/. .preview/optimizr/
python3 -m http.server 4173 --directory .preview
# → http://localhost:4173/optimizr/ and http://localhost:4173/optimizr/docs/
```

If you serve the artifact at `/` instead, the docs HTML will load without its CSS because Docusaurus emits asset URLs under `/optimizr/docs/`.

## Regenerate the icon

The SVG in `app/Resources/Icon.svg` is the visual source of truth. The deterministic renderer is:

```bash
python3 scripts/make-icon.py
```

This writes `app/Resources/AppIcon-1024.png` and `AppIcon.icns` and requires Pillow. It is not part of the normal build; the generated `.icns` is committed so CI does not need Python imaging libraries.

## Environment variables

The build supports:

| Variable | Default | Purpose |
| --- | --- | --- |
| `CONFIGURATION` | `release` | SwiftPM build configuration for `build-app.sh` |

There are no runtime secrets and no `.env` file. The app reads no configuration.

## Troubleshooting

### `swift build` fails with a target path error

The package expects `Sources/Optimizr`, `Sources/OptimizrCore`, `Sources/OptimizrScan`, and `Tests/OptimizrCoreTests`. Run commands from `app/` or use `--package-path app`.

### The app opens but the window is blank

The window uses a hidden title bar and a custom background. Make sure you are on macOS 14+; older systems cannot render the SwiftUI APIs used. Check Console for a crash report named `Optimizr`.

### Gatekeeper blocks the app

Use right-click → Open once, or build from source. Do not disable Gatekeeper globally. A notarized build is planned.

### A storage finding is missing

The relevant directory may not exist, may be unreadable, or the command may have hit its timeout. The scanner skips unreadable paths; it does not guess sizes.

### Docs build fails on `onBrokenLinks`

The configuration is strict on purpose. Fix the link or update the sidebar. Run `bun run build` locally before pushing.

### Port 3100 is in use

```bash
bun run start -- --port 3200
```

### Docusaurus cache issues

```bash
bun run clear && bun run build
```
