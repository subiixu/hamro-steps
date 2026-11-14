# New app logo, phase 1: three concepts to choose from
worker: codex
model: gpt-6-astra
effort: high
started: 2026-11-15 01:32 · terminal: s_ff76391f
Tasks: T-38
files: design/logo/**

## Goal
Three distinct new logo concepts for Hamro Steps, each shown as a 1024 app icon and on a phone home-screen mockup, so the user can pick one. Done = `design/logo/` holds, per concept, an SVG source, a 1024×1024 PNG (light), a 180px preview, and one comparison sheet `design/logo/compare.png` with all three side by side at 1024, 180 and 60px, plus `design/logo/concepts.md` with one paragraph per concept and your recommendation. Nothing in the app changes in this phase; the chosen concept is wired in by a second brief.

## Context
- The app: a family step-sharing app for the Nepali diaspora and their parents back in Nepal. One shared daily family goal; warm, plain, built for 50–70-year-old parents. "Hamro" means "our" in Nepali. Read docs/PRD.md lines 1–45 only.
- Current icon (being replaced): design/app-icon/ — three footprints in an orange ring (AppIcon.svg, concept.md, AppIcon-1024.png). The user wants something new, so don't just restyle that idea.
- App palette (redesign just shipped, light mode): accent #E2672F, accent text #B5481B, goal green #2C9A76, canvas #F4F4F6, surface #FFFFFF. Stay in this family; orange should lead.
- Must read at 60px on a home screen: one bold shape, no text, no fine detail, no gradients that turn to mud when small.
- Original work only: no stock art, no copied marks, no Nepali flag or national emblem.
- design/app-icon/build.swift is a dependency-free SVG → PNG exporter (rect, circle, M/C/Z paths). Reuse it or your own tooling; leave design/app-icon/ as it is.

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
- May touch: design/logo/** (new)
- Must not touch: ios/, web/, design/app-icon/, backend/
- Shared files: none

## Phase
Phase 1 of 2 (concepts). Phase 2 exports the chosen one (light, dark, tinted 1024 PNGs into ios/HamroSteps/Resources/Assets.xcassets/AppIcon.appiconset/, plus the web favicon).

## Checks
none (design assets only). Open compare.png yourself and confirm each concept reads at 60px.

## Questions first
Put every question in one first handoff (`status: blocked`) and stop. After
the answers arrive on your terminal, finish this phase without stopping
again. If you have no questions, build straight through.
