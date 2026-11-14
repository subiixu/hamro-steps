#!/usr/bin/env bash
# Convex backend: typecheck + convex-test unit tests (no cloud deployment). Skips until backend/ exists.
set -euo pipefail
cd "$(dirname "$0")/../backend" 2>/dev/null || { echo "backend/ not present yet: skipped"; exit 0; }
[ -d node_modules ] || npm ci --silent
npm run --silent typecheck
npm test --silent 2>&1 | tail -40
exit "${PIPESTATUS[0]}"
