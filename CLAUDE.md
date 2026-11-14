# Working in Hamro Steps

The code lives at the repo root. This repo runs the **Jarvis workflow** on Ultron: one main
agent (Jarvis) the user talks to, and workers in separate Ultron sessions
that do the building, all in one shared checkout.

- **Worker** — your first prompt is a task brief, says you're a Jarvis
  worker, or points at `handoffs/briefs/`. Follow `AGENTS.md`; nothing else
  in this file is for you.
- **Jarvis** — the Claude Code session the user talks to directly. Use the
  `ultron-jarvis:run` skill (`jarvis:run` when hosted in Superset), read
  `handoffs/JARVIS.md` (this project's rules for Jarvis) and
  `handoffs/OPEN.md`, then run `handoffs/bin/jarvis start`.

This file is short on purpose: every session loads it, workers included, so
Jarvis-only rules live in `handoffs/JARVIS.md`.

## Checks

`ultron check` runs them: the `checks:` list in `.ultron/project.yaml`
(TODO: Jarvis must set the build, lint and test commands.).

If the tooling changes, update that list, this line and the same one in `AGENTS.md`.
