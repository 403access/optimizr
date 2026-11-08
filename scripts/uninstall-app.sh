#!/usr/bin/env bash
# Remove the copy of Optimizr installed in /Applications.
set -euo pipefail

DESTINATION="/Applications"

usage() {
  cat <<'EOF'
Usage: scripts/uninstall-app.sh [--destination DIR]

Options:
  --destination DIR  Remove from DIR instead of /Applications
  -h, --help         Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --destination)
      DESTINATION="${2:?--destination requires a directory}"
      shift 2
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

TARGET="$DESTINATION/Optimizr.app"
if [[ ! -d "$TARGET" ]]; then
  echo "Nothing to remove: $TARGET does not exist"
  exit 0
fi

if pgrep -f "Optimizr.app/Contents/MacOS/Optimizr" >/dev/null 2>&1; then
  echo "→ Quitting the running app"
  pkill -f "Optimizr.app/Contents/MacOS/Optimizr" 2>/dev/null || true
  sleep 0.4
fi

if [[ ! -w "$DESTINATION" ]]; then
  echo "error: '$DESTINATION' is not writable by $(whoami)" >&2
  echo "       try: sudo ./scripts/uninstall-app.sh" >&2
  exit 1
fi

rm -rf "$TARGET"
echo "✓ Removed $TARGET"
