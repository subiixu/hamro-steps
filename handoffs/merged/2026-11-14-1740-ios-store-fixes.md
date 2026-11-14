# iOS: App Store audit fixes (privacy link, encryption key, tinted icon alpha)
status: done
agent: claude sonnet
brief: handoffs/briefs/2026-11-14-1725-ios-store-fixes.md
## What the user asked
Fix preflight rows 8 (privacy link), 9 (encryption key), 11 (tinted icon alpha); mark row 6 OK.
## What changed
- Me tab: "Privacy policy" row under Notifications, opens https://subiixu.github.io/hamro-steps/privacy/. It uses the `Icon.health` glyph, the closest existing case. Swap it if you want a different one.
- Welcome: small "Privacy policy" link under the Sign in with Apple button.
- project.yml: `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO`.
- AppIcon-1024-tinted.png flattened onto black (it had fully transparent pixels); `sips -g hasAlpha` now says no.
- docs/app-store-preflight.md rows 6, 8, 9, 11 marked OK.
## Files
- ios/project.yml — modified
- ios/HamroSteps/Features/Me/MeView.swift — modified
- ios/HamroSteps/Features/Onboarding/WelcomeView.swift — modified
- ios/HamroSteps/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-tinted.png — modified
- docs/app-store-preflight.md — modified
## Checks run
`ultron check`: passed · 2 of 2 passed · 1m 14s
- `scripts/check-ios.sh` · passed · 1m 11s
- `scripts/check-backend.sh` · passed · 3.4 s

Screenshots (simulator, `-screen welcome` / `-screen me`):
- Welcome: /private/tmp/claude-501/-Users-subixu-BIXUSTUDIO-DEV-hamro-steps/30b016d3-9df0-4e56-a45b-928b81ca3f5f/scratchpad/welcome.png (link visible under the button)
- Me: /private/tmp/claude-501/-Users-subixu-BIXUSTUDIO-DEV-hamro-steps/30b016d3-9df0-4e56-a45b-928b81ca3f5f/scratchpad/me2.png. NOT verified visually: the iOS notification permission prompt covers the middle of the screen, and I couldn't dismiss it (no Simulator UI, `simctl privacy` denied). The Me row is built and compiles, but I haven't seen it on screen.
- Didn't tap the links to confirm they open Safari.
## Libraries used
Hugeicons — reused the existing `Icon.health` for the Me privacy row; no new icons.
## Notes for Jarvis
- Shared file edit: ios/project.yml, one line as briefed.
- Still the user's: enter the privacy URL in App Store Connect and enable Push on the App ID.
- Suggested commit: "iOS: privacy policy links (Me, Welcome), encryption exemption key, flatten tinted icon alpha, preflight rows 6/8/9/11 OK"

## Checks (run by Ultron)
Passed · 2 of 2 · 4m 37s · 2026-11-14 17:41 · in `/Users/subixu/BIXUSTUDIO/DEV/hamro-steps`
- `scripts/check-ios.sh` · passed · 4m 25s
- `scripts/check-backend.sh` · passed · 11.7 s
