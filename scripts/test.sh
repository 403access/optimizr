#!/usr/bin/env bash
# Run the Swift test suite; optionally follow with a live read-only scan.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_SCAN=0
SCAN_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scan)
      RUN_SCAN=1
      shift
      ;;
    --json | --markdown)
      RUN_SCAN=1
      SCAN_ARGS+=("$1")
      shift
      ;;
    -h | --help)
      echo "Usage: scripts/test.sh [--scan] [--json|--markdown]"
      exit 0
      ;;
    *)
      echo "error: unknown option '$1'" >&2
      exit 2
      ;;
  esac
done

echo "→ Running Swift tests"
swift test --package-path "$ROOT/app"

if [[ "$RUN_SCAN" -eq 1 ]]; then
  echo ""
  "$ROOT/scripts/scan.sh" "${SCAN_ARGS[@]}"
fi
