# <one-line task title>
worker: claude | codex | opencode | grok
model: <Claude: drop the line to take Settings → Nayo → Workers model; name one only to differ, with the reason in brackets, e.g. `claude-opus-5-5 (cross-crate design)`. Codex: gpt-6-astra | gpt-5.6-sol | gpt-5.6-terra | gpt-5.6-luna; optional for opencode and grok>
effort: <Claude: drop the line to take the Workers default; else low | medium | high | xhigh, with the reason in brackets>
started: <YYYY-MM-DD HH:MM> · terminal: <filled in by nayo spawn>
Tasks: <the user's tasks this brief works on, e.g. T-41, T-42 — or T-42 (part 1 of 2). Drop the line when the work wasn't asked for>
why: <written by nayo spawn --redo --why; don't write it by hand>
isolate: <optional: `yes` for the worker's own git worktree (two briefs lightly touching one file); nayo spawn rewrites it to `<worktree> · branch: jw/<slug>`. Drop the line otherwise>
budget: <optional: this worker's own limits, any of `45m · $10 · 120k` (minutes working, USD, thousand tokens of context); past one, aranikod asks it for a partial handoff. Drop the line to use Settings → Nayo → Workers>

## Goal
<one sentence: what done looks like for THIS phase>

## Done so far
<what earlier phases finished (their handoffs in handoffs/merged/), or `nothing yet`>

## Remaining
<what this phase does>

## Dead ends
<what was tried or ruled out, so the worker doesn't retry it, or `none known`>

## Acceptance
`<one command that fails now and must pass when this phase is done>`

## File scope
<!-- repo-relative globs, one per line: `*` stays in one folder, `**` crosses folders. nayo merge refuses a handoff listing a file outside them (an isolated branch's are put back), and nayo spawn refuses one overlapping a running worker's -->
- <crates/foo/src/**>

## Context
<decisions already made, files to read first>
Read narrowly: open the brief, docs/PRD.md and merged handoffs with grep -n and line ranges (sed -n), never whole-file cat.

## Scope
- Must not touch: <paths>
- Shared files (edit minimally, name in handoff): <paths>

## Phase
<one phase. A job with several phases gets one brief per phase; the next one
is spawned with `nayo spawn <brief> --after <this handoff>`>

## Checks
<scoped commands only (the Acceptance command, the tests for the module or package touched,
the linter on the worker's own files), plus what else to verify (an `araniko …` run, a screen
to look at). Write `none` when the project's checks don't apply (docs only): `nayo merge` then
skips its refusal of red checks>
**Scoped checks only.** Run the commands above and nothing wider: never the whole test suite
(`cargo test --workspace`, a bare `cargo test`, `npm test` across the repo), a workspace-wide
lint or `araniko check`, in the foreground or the background. Other workers build in this
checkout, so a full run queues for 20+ minutes. Araniko runs the full checks on your
handoff and Nayo runs them at merge.
<!-- optional: commands `nayo merge <handoff> --check --verify` runs on HEAD plus exactly the
handoff's listed changes, in a throwaway worktree (class=light runs at once; another class runs
under `nayo lock <class>`; timeout= in seconds; reuse=never if --reuse mustn't skip it):

```bash verify class=light timeout=300
bash kits/foo/tests/foo.sh
```

An optional ```json verify-inputs``` block names untracked files a check needs:
{"copy": [".env.test"], "requires": ["path/that/must/exist"]} -->

## Questions first
Put every question in one first handoff (`status: blocked`) and stop. After
the answers arrive on your terminal, finish this phase without stopping
again. If you have no questions, build straight through.
