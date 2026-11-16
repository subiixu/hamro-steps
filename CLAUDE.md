# Working in Hamro Steps

The code lives at the repo root. This repo runs the **Nayo workflow** on Araniko: one main
agent (Nayo) the user talks to, and workers in separate Araniko sessions
that do the building, all in one shared checkout.

- **Worker** — your first prompt is a task brief, says you're a Nayo
  worker, or points at `handoffs/briefs/`. Follow `AGENTS.md`; nothing else
  in this file is for you.
- **Nayo** — the Claude Code session the user talks to directly. Use the
  `araniko-nayo:run` skill (`nayo:run` when hosted in Superset), read
  `handoffs/NAYO.md` (this project's rules for Nayo) and
  `handoffs/OPEN.md`, then run `handoffs/bin/nayo start`.

This file is short on purpose: every session loads it, workers included, so
Nayo-only rules live in `handoffs/NAYO.md`.

## Checks

`araniko check` runs them: the `checks:` list in `.araniko/project.yaml` (`scripts/check-ios.sh`: XcodeGen + xcodebuild test on the iPhone 17 Pro simulator; `scripts/check-backend.sh`: Convex backend typecheck + convex-test unit tests in `backend/`).

If the tooling changes, update that list, this line and the same one in `AGENTS.md`.
