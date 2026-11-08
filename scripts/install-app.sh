#!/usr/bin/env bash
# Build Optimizr and install it into /Applications.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="/Applications"
LAUNCH=1
BUILD=1

usage() {
  cat <<'EOF'
Usage: scripts/install-app.sh [options]

Options:
  --destination DIR  Install into DIR instead of /Applications
  --no-launch        Install without opening the app
  --skip-build       Reuse the existing dist/Optimizr.app
  -h, --help         Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --destination)
      DESTINATION="${2:?--destination requires a directory}"
      shift 2
      ;;
    --no-launch)
      LAUNCH=0
      shift
      ;;
    --skip-build)
      BUILD=0
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option '$1'" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$BUILD" -eq 1 ]]; then
  "$ROOT/scripts/build-app.sh"
fi

SOURCE="$ROOT/dist/Optimizr.app"
if [[ ! -d "$SOURCE" ]]; then
  echo "error: $SOURCE does not exist; run ./scripts/build-app.sh first" >&2
  exit 1
fi

if [[ ! -d "$DESTINATION" ]]; then
  echo "error: destination '$DESTINATION' does not exist" >&2
  exit 1
fi
if [[ ! -w "$DESTINATION" ]]; then
  echo "error: '$DESTINATION' is not writable by $(whoami)" >&2
  echo "       try: sudo ./scripts/install-app.sh" >&2
  exit 1
fi

TARGET="$DESTINATION/Optimizr.app"

if pgrep -f "Optimizr.app/Contents/MacOS/Optimizr" >/dev/null 2>&1; then
  echo "→ Quitting the running app"
  pkill -f "Optimizr.app/Contents/MacOS/Optimizr" 2>/dev/null || true
  for _ in 1 2 3 4 5; do
    pgrep -f "Optimizr.app/Contents/MacOS/Optimizr" >/dev/null 2>&1 || break
    sleep 0.4
  done
fi

echo "→ Installing to $TARGET"
rm -rf "$TARGET"
/usr/bin/ditto "$SOURCE" "$TARGET"

if ! /usr/bin/codesign --verify --deep --strict "$TARGET" >/dev/null 2>&1; then
  echo "→ Re-signing the installed copy (ad-hoc)"
  /usr/bin/codesign --force --deep --sign - "$TARGET" >/dev/null
fi

/usr/bin/plutil -lint "$TARGET/Contents/Info.plist" >/dev/null
echo "✓ Installed $TARGET"

if [[ "$LAUNCH" -eq 1 ]]; then
  open "$TARGET"
  echo "✓ Launched Optimizr"
fi
