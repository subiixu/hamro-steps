# <one-line task title>
worker: claude | codex | opencode | grok
model: <fable | claude-opus-5-5 | sonnet | haiku | gpt-6-astra | gpt-5.6-sol | gpt-5.6-terra | gpt-5.6-luna | grok-4.7; optional for opencode and grok>
  # note the reason when the usage band changed the choice, e.g. `claude-opus-5-5 (amber band; fable-tier task)`
effort: <low | medium | high | xhigh>
started: <YYYY-MM-DD HH:MM> · terminal: <filled in by jarvis spawn>
Tasks: <the user's tasks this brief works on, e.g. T-41, T-42 — or T-42 (part 1 of 2). Drop the line when the work wasn't asked for>
why: <written by jarvis spawn --redo --why; don't write it by hand>
isolate: <optional: `yes` for the worker's own git worktree (two briefs lightly touching one file); jarvis spawn rewrites it to `<worktree> · branch: jw/<slug>`. Drop the line otherwise>
files: <the paths or globs this worker expects to touch, comma-separated (`crates/foo/src/*.rs, docs/x.md`). jarvis spawn refuses, without --force, a non-isolated brief whose files overlap a running non-isolated worker's>
budget: <optional: this worker's own limits, any of `45m · $10 · 120k` (minutes working, USD, thousand tokens of context); past one, ultrond asks it for a partial handoff. Drop the line to use Settings → Jarvis → Workers>

## Goal
<what done looks like for THIS phase, in one paragraph>

## Context
<decisions already made, files to read first, the previous phase's handoff in handoffs/merged/>
Read narrowly: open the brief, docs/PRD.md and merged handoffs with grep -n and line ranges (sed -n), never whole-file cat.

## Scope
- May touch: <paths>
- Must not touch: <paths>
- Shared files (edit minimally, name in handoff): <paths>

## Phase
<one phase. A job with several phases gets one brief per phase; the next one
is spawned with `jarvis spawn <brief> --after <this handoff>`>

## Checks
<`ultron check`, plus what else to verify (an `ultron …` run, a screen to look at). Write
`none` when the project's checks don't apply (docs only): `jarvis merge` then skips its
refusal of red checks>

## Questions first
Put every question in one first handoff (`status: blocked`) and stop. After
the answers arrive on your terminal, finish this phase without stopping
again. If you have no questions, build straight through.
