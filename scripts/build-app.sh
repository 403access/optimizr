#!/usr/bin/env bash
# Builds a distributable, ad-hoc signed Optimizr.app bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/app"
DIST="$ROOT/dist"
BUNDLE="$DIST/Optimizr.app"
CONFIGURATION="${CONFIGURATION:-release}"

echo "→ Building Optimizr ($CONFIGURATION)"
swift build --package-path "$APP_DIR" -c "$CONFIGURATION" --product Optimizr

BINARY="$APP_DIR/.build/$CONFIGURATION/Optimizr"
if [[ ! -f "$BINARY" ]]; then
  # SwiftPM may use an architecture-specific path on some toolchains.
  BINARY="$(find "$APP_DIR/.build" -type f -name Optimizr -perm -111 -path "*$CONFIGURATION*" | head -n 1)"
fi
if [[ -z "${BINARY:-}" || ! -f "$BINARY" ]]; then
  echo "error: could not find the Optimizr binary" >&2
  exit 1
fi

echo "→ Assembling $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BINARY" "$BUNDLE/Contents/MacOS/Optimizr"
cp "$APP_DIR/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
if [[ -f "$APP_DIR/Resources/AppIcon.icns" ]]; then
  cp "$APP_DIR/Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
fi
chmod +x "$BUNDLE/Contents/MacOS/Optimizr"

if command -v codesign >/dev/null 2>&1; then
  echo "→ Signing (ad-hoc)"
  codesign --force --deep --sign - "$BUNDLE" >/dev/null
fi

echo "→ Built $BUNDLE"
echo "  Open with: open \"$BUNDLE\""
