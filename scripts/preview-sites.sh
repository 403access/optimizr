#!/usr/bin/env bash
# Build docs, assemble the Pages layout, and serve it at production paths.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-4173}"
BUILD=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)
      PORT="${2:?--port requires a value}"
      shift 2
      ;;
    --no-build)
      BUILD=0
      shift
      ;;
    -h | --help)
      echo "Usage: scripts/preview-sites.sh [--port 4173] [--no-build]"
      exit 0
      ;;
    *)
      echo "error: unknown option '$1'" >&2
      exit 2
      ;;
  esac
done

if [[ "$BUILD" -eq 1 ]]; then
  command -v npm >/dev/null 2>&1 || {
    echo "error: npm is required (Node.js 20+)" >&2
    exit 1
  }
  (
    cd "$ROOT/docs-site"
    if [[ ! -d node_modules ]]; then
      npm ci --no-audit --no-fund
    fi
    npm run build
  )
fi

[[ -d "$ROOT/docs-site/build" ]] || {
  echo "error: docs build missing; run without --no-build" >&2
  exit 1
}

echo "→ Assembling site"
rm -rf "$ROOT/.preview"
mkdir -p "$ROOT/.preview/optimizr"
cp -R "$ROOT/marketing/." "$ROOT/.preview/optimizr/"
cp -R "$ROOT/docs-site/build" "$ROOT/.preview/optimizr/docs"
touch "$ROOT/.preview/optimizr/.nojekyll"

cat <<EOF
→ Serving the combined site
  Marketing: http://localhost:$PORT/optimizr/
  Docs:      http://localhost:$PORT/optimizr/docs/
  Stop with Ctrl+C
EOF

exec python3 -m http.server "$PORT" --directory "$ROOT/.preview"
