#!/usr/bin/env bash
# iOS build + unit tests on a throwaway simulator per run, so parallel workers never clash.
set -euo pipefail
cd "$(dirname "$0")/../ios" 2>/dev/null || { echo "ios/ not present yet: skipped"; exit 0; }
KEY=$(echo "$PWD" | shasum | cut -c1-8)
LOCK="${TMPDIR:-/tmp}/hamro-check-$KEY.lock"
# One build per checkout at a time (Xcode's build DB can't be shared); wait up to 20 min.
# A lock left by a killed run (SIGKILL skips the trap) is broken: its pid is dead, or it has no pid file and is >30 min old.
stale_lock() {
  local p
  if [ -f "$LOCK/pid" ]; then
    p=$(cat "$LOCK/pid" 2>/dev/null)
    [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null
  else
    [ -d "$LOCK" ] && [ -n "$(find "$LOCK" -maxdepth 0 -mmin +30 2>/dev/null)" ]
  fi
}
got=0
for _ in $(seq 1 1200); do
  if mkdir "$LOCK" 2>/dev/null; then echo $$ > "$LOCK/pid"; got=1; break; fi
  if stale_lock; then
    echo "check-ios: removing stale lock $LOCK"
    if mv "$LOCK" "$LOCK.stale.$$" 2>/dev/null; then
      rm -rf "$LOCK.stale.$$"
      continue
    fi
  fi
  sleep 1
done
[ "$got" = 1 ] || { echo "check-ios: another check held $LOCK for 20 min"; exit 1; }
SIM=""
trap '[ -n "$SIM" ] && { xcrun simctl shutdown "$SIM" >/dev/null 2>&1; xcrun simctl delete "$SIM" >/dev/null 2>&1; }; rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null; true' EXIT
xcodegen generate --quiet
# Delete simulators left by dead runs (hamro-check-<pid> with a dead pid); nothing else.
xcrun simctl list devices 2>/dev/null | sed -nE 's/^ *hamro-check-([0-9]+) \(([0-9A-F-]+)\).*/\1 \2/p' | while read -r opid udid; do
  kill -0 "$opid" 2>/dev/null || { xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true; xcrun simctl delete "$udid" >/dev/null 2>&1 || true; }
done
SIM_NAME="hamro-check-$$"
SIM=$(xcrun simctl create "$SIM_NAME" "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro")
set +e
xcodebuild test -project HamroSteps.xcodeproj -scheme HamroSteps \
  -destination "id=$SIM" -derivedDataPath "${TMPDIR:-/tmp}/hamro-dd-$KEY" \
  -collect-test-diagnostics never -quiet 2>&1 | tail -40
code=${PIPESTATUS[0]}
exit "$code"
