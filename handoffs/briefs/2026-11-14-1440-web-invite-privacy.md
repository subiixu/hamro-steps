# Static web pages: family invite page and privacy policy
worker: claude
model: sonnet
effort: medium
started: 2026-11-14 14:40
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

## Scope
- May touch: `web/**`, `handoffs/screens/`
- Must not touch: everything else

## Checks
none (static pages; not covered by `ultron check`). Validate the HTML (e.g. `npx --yes html-validate` from a temp dir, without adding a package.json to the repo) and attach screenshots.

## Questions first
Put every question in one first handoff (`status: blocked`) and stop. After
the answers arrive on your terminal, finish this phase without stopping
again. If you have no questions, build straight through.
