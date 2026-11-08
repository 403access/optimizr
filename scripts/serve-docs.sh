#!/usr/bin/env bash
# Install docs dependencies if needed and start the Docusaurus dev server.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORCE_INSTALL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      FORCE_INSTALL=1
      shift
      ;;
    -h | --help)
      echo "Usage: scripts/serve-docs.sh [--install]"
      exit 0
      ;;
    *)
      echo "error: unknown option '$1'" >&2
      exit 2
      ;;
  esac
done

command -v npm >/dev/null 2>&1 || {
  echo "error: npm is required (Node.js 20+)" >&2
  exit 1
}

cd "$ROOT/docs-site"

if [[ "$FORCE_INSTALL" -eq 1 || ! -d node_modules ]]; then
  echo "→ Installing docs dependencies"
  npm ci --no-audit --no-fund
fi

echo "→ Starting docs at http://localhost:3100/optimizr/docs/"
exec npm run start
