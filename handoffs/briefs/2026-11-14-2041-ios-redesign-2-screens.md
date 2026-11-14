# iOS redesign, phase 2: every other screen on the new tiles and glass
worker: claude
model: claude-opus-5-5
effort: high
files: ios/HamroSteps/Features/Onboarding/*.swift, ios/HamroSteps/Features/Setup/*.swift, ios/HamroSteps/Features/Settings/*.swift, ios/HamroSteps/Features/Me/*.swift, ios/HamroSteps/Features/Activity/StatusPicker.swift, ios/HamroSteps/Features/Activity/NotificationSettingsView.swift, ios/HamroSteps/Features/Activity/ActivityGallery.swift, ios/HamroSteps/Components/Card.swift, ios/Shared/UI/Icon.swift, ios/Shared/SharedAssets.xcassets/Icons/**

## Goal
Every screen outside Home matches the design canvas, using phase 1's components (Card/tiles, TileLabel with icon, GlassIconButton, glass buttons, colours). No new behaviour.

## Context
- Design: https://claude.ai/artifact/B24MPUiweEWxkdJ1Muuzbi (bottom row = onboarding and setup; top row = status picker, family settings, change name or goal, notifications, Me, delete account).
- Phase 1 handoff (merged before this one): read its "What changed" and "Notes for Jarvis" first.
- Per screen: Welcome (large hero area, app mark, avatars row, black "Continue with Apple" capsule — keep the real SignInWithAppleButton, style .black), name, Health (numbered step tile), start-or-join (two big choice tiles), family name / daily goal (goal stepper in a tile + 2×2 preset grid, "Step 1 of 2"/"Step 2 of 2"), invite (code tile, Share invite = glassProminent, Done = glass), join (code field + family preview tile), status picker sheet (2-column preset tiles with selected accent border, own-text field with counter, expiry capsules, Set status), family settings (Family tile, Invite code tile, People tile with Remove, Notifications row, Leave row in accent text), change name or goal, notifications (toggles in one tile), Me (profile tile, Apple Health tile with two mini tiles, rows), delete account.
- Keep all copy as it is in the code today; the canvas copy is close to it. Where the canvas adds copy that isn't in the app ("Keep my account", "Step 1 of 2"), add only "Step N of 2"; skip the rest.
- Photo areas on Welcome, Invite and start-or-join: NOT in scope (no licensed images yet). Use a flat SurfaceMuted block only if the layout needs the space; otherwise leave it out.
Read narrowly: grep -n and sed -n line ranges.

## Libraries and design rules
- Icons: Hugeicons only via `Icon`; map the canvas stand-ins to the nearest Hugeicon.
- Loading: Thinking Orbs as today.

## Scope
- May touch: the files in `files:` above.
- Must not touch: Home (phase 1), Services/, Sync/, Push/, backend/, web/.
- Shared files: none expected.

## Phase
Phase 2 of 2, after handoffs/…-ios-redesign-1-system-home.md is merged.

## Checks
`ultron check`. Then one simulator screenshot per screen via the debug `-screen` launches (welcome, name, health, setup, createName, createGoal, invite, join, settings, me), saved under handoffs/screens/.

## Questions first
Put every question in one first handoff (`status: blocked`) and stop. After the answers arrive on your terminal, finish this phase without stopping again. If you have no questions, build straight through.
