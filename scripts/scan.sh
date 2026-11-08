#!/usr/bin/env bash
# Run the same read-only scanner the app uses, without opening the UI.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec swift run --package-path "$ROOT/app" optimizr-scan "$@"
