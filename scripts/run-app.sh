#!/usr/bin/env bash
# Build and launch the local dist copy of Optimizr.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build)
      BUILD=0
      shift
      ;;
    -h | --help)
      echo "Usage: scripts/run-app.sh [--no-build]"
      exit 0
      ;;
    *)
      echo "error: unknown option '$1'" >&2
      exit 2
      ;;
  esac
done

if [[ "$BUILD" -eq 1 ]]; then
  "$ROOT/scripts/build-app.sh"
fi

BUNDLE="$ROOT/dist/Optimizr.app"
if [[ ! -d "$BUNDLE" ]]; then
  echo "error: $BUNDLE does not exist; run ./scripts/build-app.sh first" >&2
  exit 1
fi

if pgrep -f "Optimizr.app/Contents/MacOS/Optimizr" >/dev/null 2>&1; then
  pkill -f "Optimizr.app/Contents/MacOS/Optimizr" 2>/dev/null || true
  sleep 0.4
fi

open "$BUNDLE"
echo "✓ Running $BUNDLE"
