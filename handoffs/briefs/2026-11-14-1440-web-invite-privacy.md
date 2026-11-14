# Static web pages: family invite page and privacy policy
worker: claude
model: sonnet
effort: medium
started: 2026-11-14 14:06 · terminal: s_3cc811f6
Tasks: T-4
files: web/**

## Goal
Two static pages in `web/`, plain HTML + one CSS file with no build step, ready to host anywhere: `web/invite/index.html` and `web/privacy/index.html`. Done = both open correctly from disk in Safari at iPhone and desktop widths, with screenshots in `handoffs/screens/`.

## Context
- Read `docs/PRD.md`. Pilot invites are code-first: an organiser shares a link like `https://<host>/invite/?code=K7M2QX`.
- **Invite page:**
  - Shows the family code big and spaced, with a Copy button.
  - Shows 3 plain steps for a parent: install TestFlight, open the Hamro Steps invite (`https://testflight.apple.com/join/XXXX` as one constant at the top of the file), then sign in and type the code.
  - A missing or invalid `?code` shows a friendly message.
  - Large text, warm palette (accent `#E2672F`, off-white background), system font stack, accessible contrast, light and dark mode.
  - No tracking and no external scripts.
- **Privacy policy:**
  - Plain-English policy built from the PRD's "Privacy, permissions and tech" section:
    - Apple Health step count is read only and never used for ads or sold.
    - Only daily step totals, walk start/stop, status and reactions are shared with your family.
    - No location.
    - Leaving a family removes your shared data from it, and deleting your account removes everything.
    - Data is stored with Convex (the processor).
    - Push notifications are sent via Apple.
    - Contact: `privacy@example.com` placeholder in one place.
  - Effective date 14 November 2026. Mark it clearly as a draft for the founders to review.
- Icons: if any, inline SVGs copied from the Hugeicons free set (stroke-rounded), `currentColor`. No emoji icons.

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
- May touch: `web/**`, `handoffs/screens/`
- Must not touch: everything else

## Checks
none (static pages; not covered by `ultron check`). Validate the HTML (e.g. `npx --yes html-validate` from a temp dir, without adding a package.json to the repo) and attach screenshots.

## Questions first
Put every question in one first handoff (`status: blocked`) and stop. After
the answers arrive on your terminal, finish this phase without stopping
again. If you have no questions, build straight through.
