# iOS redesign, phase 2: every other screen on the new tiles and glass
worker: claude
model: claude-opus-5-5
effort: high
files: ios/HamroSteps/Features/Onboarding/*.swift, ios/HamroSteps/Features/Setup/*.swift, ios/HamroSteps/Features/Settings/*.swift, ios/HamroSteps/Features/Me/*.swift, ios/HamroSteps/Features/Activity/StatusPicker.swift, ios/HamroSteps/Features/Activity/StatusLabel.swift, ios/HamroSteps/Features/Activity/NotificationSettingsView.swift, ios/HamroSteps/Features/Activity/ActivityGallery.swift, ios/HamroSteps/Components/Card.swift, ios/Shared/UI/Icon.swift, ios/Shared/SharedAssets.xcassets/Icons/**

## Goal
Every screen outside Home matches the design canvas, using phase 1's components (Card/tiles, TileLabel with icon, GlassIconButton, glass buttons, colours). No new behaviour.

## Context
- Design: https://claude.ai/artifact/B24MPUiweEWxkdJ1Muuzbi (bottom row = onboarding and setup; top row = status picker, family settings, change name or goal, notifications, Me, delete account).
- Phase 1 handoff: handoffs/merged/2026-11-14-2336-ios-redesign-1-home.md — read its "What changed" and "Notes for Jarvis" first.
- From phase 1: StatusLabel.swift still uses `.foregroundStyle(.secondary)` (below AA on the new canvas) → `.secondaryText`. ActivityGallery still shows the old WalkingBadge pill: move it to phase 1's corner dot.
- Large text: a second opinion on phase 1 caught overflows at accessibility sizes. Check every screen at accessibility XXXL on the iPhone SE simulator (phase 1's `shoot_on` approach in its handoff), and use `"${S:?}"` in any rm.
- Per screen: Welcome (large hero area, app mark, avatars row, black "Continue with Apple" capsule — keep the real SignInWithAppleButton, style .black), name, Health (numbered step tile), start-or-join (two big choice tiles), family name / daily goal (goal stepper in a tile + 2×2 preset grid, "Step 1 of 2"/"Step 2 of 2"), invite (code tile, Share invite = glassProminent, Done = glass), join (code field + family preview tile), status picker sheet (2-column preset tiles with selected accent border, own-text field with counter, expiry capsules, Set status), family settings (Family tile, Invite code tile, People tile with Remove, Notifications row, Leave row in accent text), change name or goal, notifications (toggles in one tile), Me (profile tile, Apple Health tile with two mini tiles, rows), delete account.
- Keep all copy as it is in the code today; the canvas copy is close to it. Where the canvas adds copy that isn't in the app ("Keep my account", "Step 1 of 2"), add only "Step N of 2"; skip the rest.
- Photo areas on Welcome, Invite and start-or-join: NOT in scope (no licensed images yet). Use a flat SurfaceMuted block only if the layout needs the space; otherwise leave it out.
Read narrowly: grep -n and sed -n line ranges.

## Libraries and design rules
<!-- written by jarvis spawn from `ultron knowledge show`; replaced on every spawn -->
### Libraries

- **Hugeicons** (icons): Use Hugeicons for every icon in the UI, keeping one style and stroke weight throughout and colouring with currentColor. No emoji and no hand-drawn SVG icons.
- **Thinking Orbs** (loading): Use Thinking Orbs for every AI "thinking" or loading state instead of a spinner. On web render <ThinkingOrb state="..." size={64|20} /> and pick the state that matches the activity (e.g. searching, composing). Set up: Web: `npm install thinking-orbs`; Mac: `Swift Package Manager: add https://github.com/Jakubantalik/Libraries.dev (branch main), product ThinkingOrbsKit`; iOS: `Swift Package Manager: add https://github.com/Jakubantalik/Libraries.dev (branch main), product ThinkingOrbsKit`. iOS: The page doesn't explicitly say the Swift package supports iOS or macOS, and it gives no CocoaPods option. Mac: The page doesn't explicitly say the Swift package supports macOS; SwiftUI support is implied only. Web: Requires React 18 or newer; the page lists only an npm install line.

### Releasing

- Pushing the default branch isn't a release: each project's Jarvis
  commits and pushes its own main (a plain fast-forward) and never leaves
  the push for the user, unless the project marks main as a release
  (`gates.default_branch_is_release: true`).
- Releasing is the user's: Ultron blocks agents from tagging, force-pushing,
  deploying to production or submitting to a store. Ask the user to do it.
- Every release gets a changelog entry in the user's voice: what changed for
  the person using the app, not which files moved.
- Version numbers are semantic. A release that changes stored data bumps
  the minor version and ships a migration with a rollback note.
- Preview or staging deployments are fine without the user; say where the
  preview is in the handoff.

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

## Answers (2026-11-15 00:32)

Answers from the user (2026-11-15):
1. Build from the brief's per-screen notes, as phase 1 did; keep today's copy and order where the notes are silent.
2. Leave the Notifications row out of Family settings (notifications stay under Me only).
3. Welcome: leave the avatars row out.
4. Health: numbered how-to as you proposed (1 Turn on Steps, 2 Tap Allow; split today's line, same meaning).
5. (Jarvis) Me Apple Health tile: your guess is right: left = connection state, right = "Steps last sent …", today's copy.
Go ahead and build; finish with ultron check, the screenshots and the iPhone SE accessibility XXXL pass, then set the handoff to done.


### The blocked handoff (handoffs/2026-11-14-2353-ios-redesign-2-screens.md)

#### iOS redesign, phase 2: every other screen on the new tiles and glass
status: blocked
agent: claude claude-opus-5-5
brief: handoffs/briefs/2026-11-14-2041-ios-redesign-2-screens.md
#### What the user asked
Restyle every screen outside Home to match the design canvas, using phase 1's tiles, glass buttons and colours. No new behaviour.

#### What changed
So far, only one change: StatusLabel's grey now uses `.secondaryText` (AA on the new canvas), as phase 1 flagged.

I've read every screen in scope and the plan is ready. Most of the brief's per-screen spec maps straight onto phase 1's components: Card/TileLabel tiles, `PrimaryButton` (`.glassProminent`), `.glass` secondary buttons and `bentoSurface`.

Five points need a ruling before I build. They're below. The main one: **I can't open the design canvas.** The Claude Docs read of `B24MPUiweEWxkdJ1Muuzbi` was refused with "access". Phase 1 didn't open it either.

Plan once answered, all in the files the brief lists:
- Welcome:
  - a larger app-mark hero
  - the three points in one tile
  - the real `SignInWithAppleButton` in `.black` as a 56pt capsule (the dark-mode branch goes, since the app is light only)
- Name: the field in a tile.
- Health: the numbered step tile (see Q4), and "Not now" as `.glass`.
- Start or join: two big choice tiles.
- Family name and Daily goal:
  - "Step 1 of 2" and "Step 2 of 2" above the titles
  - the goal stepper in a `bentoSurface` tile, with `GlassIconButton`-style ∓ buttons
  - the 2×2 preset tiles with an accent border when selected (one column at accessibility sizes, as today)
- Invite: a code tile, Share invite as `.glassProminent`, Done as `.glass`.
- Join: the code field in a tile, and the family preview as a tile.
- Status picker:
  - presets as 2-column tiles with an accent border when selected
  - the own-text field in a tile, with its counter
  - expiry capsules
  - Set status as `.glassProminent` tinted accent
- Family settings: from a List to a ScrollView of tiles (Family, Invite code, People with Remove, then the rows). Leave stays a row in AccentText.
- Change name or goal: the same tiles as the setup screens.
- Notifications: the four switches in one tile, and the greys moved to `.secondaryText`.
- Me: a profile tile, an Apple Health tile (see Q5), and the rows in a tile.
- Delete account: the list in a tile.
- ActivityGallery: the WalkingBadge pill swapped for phase 1's corner `WalkingDot`.

#### Files
- ios/HamroSteps/Features/Activity/StatusLabel.swift — modified
- handoffs/2026-11-14-2353-ios-redesign-2-screens.md — created

#### Checks run
None yet. `ultron check`, the 10 `-screen` screenshots and the iPhone SE accessibility XXXL pass come after the answers. The status picker and notifications screens will be shot through `-activityGallery status|notifications`.

#### Libraries used
none touched

#### Questions for the user
1. The design canvas link can't be read from a worker session (access refused). Can you save screenshots of its two rows into `design/` or `handoffs/screens/`? Or should I build from the brief's per-screen notes alone, as phase 1 did?
2. Family settings: the brief lists a "Notifications row", but today notifications live only under Me, and they're per person, not per family. Should I add a row in Family settings that opens the same Notifications screen (a second way in), or leave it out?
3. Welcome "avatars row": no one's family exists before sign-in. Should I show a decorative row of 4–5 coloured initial avatars, or leave it out?
4. Health "numbered step tile": my plan is to turn today's line "On the next screen, turn on Steps, then tap Allow." into a tile with 1 "Tap Allow step count", 2 "Turn on Steps", 3 "Tap Allow". That splits existing copy into slightly new wording. OK? Or should I number the four existing reasons in a tile instead (no new words)?
5. Me "Apple Health tile with two mini tiles": my guess is left = state ("Reading steps", "Permission asked" or "Not connected") and right = "Steps last sent 5 min ago", using today's copy. Is that right, or what do the two mini tiles show on the canvas?

#### Notes for Jarvis
- No shared files touched.
- The four answers that don't need the canvas can come back on their own. If there are no screenshots for Q1, I'll follow the brief's notes. Where the brief is silent, I'll keep today's copy and order.
- Delete account keeps the system red, as today. The brief doesn't mention it, and I won't add "Keep my account".
