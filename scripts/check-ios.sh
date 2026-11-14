#!/usr/bin/env bash
# iOS build + unit tests. Skips until the app exists.
set -euo pipefail
cd "$(dirname "$0")/../ios" 2>/dev/null || { echo "ios/ not present yet: skipped"; exit 0; }
xcodegen generate --quiet
xcodebuild test -project HamroSteps.xcodeproj -scheme HamroSteps \
  -destination "platform=iOS Simulator,name=${IOS_SIM:-iPhone 17 Pro}" \
  -quiet 2>&1 | tail -40
exit "${PIPESTATUS[0]}"
