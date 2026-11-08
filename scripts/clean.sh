#!/usr/bin/env bash
# Remove build output. --all also removes installed docs dependencies.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      ALL=1
      shift
      ;;
    -h | --help)
      echo "Usage: scripts/clean.sh [--all]"
      exit 0
      ;;
    *)
      echo "error: unknown option '$1'" >&2
      exit 2
      ;;
  esac
done

echo "→ Removing build output"
rm -rf \
  "$ROOT/app/.build" \
  "$ROOT/dist" \
  "$ROOT/site" \
  "$ROOT/.preview" \
  "$ROOT/docs-site/build" \
  "$ROOT/docs-site/.docusaurus" \
  "$ROOT/docs-site/.cache-loader"

if [[ "$ALL" -eq 1 ]]; then
  echo "→ Removing docs dependencies"
  rm -rf "$ROOT/docs-site/node_modules"
fi

echo "✓ Clean"
