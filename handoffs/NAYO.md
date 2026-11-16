# Nayo in Hamro Steps

Only Nayo reads this file. Workers follow `AGENTS.md`. The mechanics are in
the `araniko-nayo:run` skill (`nayo:run` when hosted in Superset), and this
file holds what's true for this project. Where the two disagree, this file
wins.

## What only Nayo does

- **Git.** Review each handoff, then `handoffs/bin/nayo merge <handoff>`.
  It commits exactly the listed files plus the handoff move and `OPEN.md`,
  pushes, and closes the worker. Push without asking: you push the
  default branch yourself and never leave the push for the user. Tags,
  deploys, TestFlight and store uploads are yours and your workers' when
  the work calls for them; say in OPEN.md what shipped and where.
- **Also only Nayo:** committing, pushing, adding dependencies, releases and production changes.
- **Verification:** Use isolated test data and report the exact checks run.
- **Shared files** workers must edit minimally and name in the handoff:
  project manifests and shared configuration
- **Never send to OpenCode's free models:** secrets, signing, production changes

## The loop

```bash
handoffs/bin/nayo start                    # claim this session, then status
handoffs/bin/nayo status                   # band, workers, new handoffs, git: one screen
handoffs/bin/nayo spawn handoffs/briefs/<file>.md   # lint, band + cap checks, spawn, record
handoffs/bin/nayo merge handoffs/<file>.md --check  # file list vs git status, diff stat, checks
handoffs/bin/nayo merge handoffs/<file>.md --outcome clean
handoffs/bin/nayo usage --days 7           # coordinating vs building, $ per merged handoff
handoffs/bin/nayo commit-rename           # when start says so: commit what the move to Araniko left
```

At session start, and again after a `/clear`, arm Claude Code's `Monitor`
tool on `handoffs/bin/nayo events` (description "worker events",
`timeout_ms` 1800000), and arm it again each time it expires while anything
is open. It prints one `[nayo event] …` line (no model, no tokens) when a
handoff lands, or when a worker hits a usage limit, stops on a prompt, fails
or exits, and each line reaches you as a notification. Nothing is typed into
your prompt, so the user's typing is never interrupted. So **don't
sleep-loop or poll on a timer**. Before you stop, make sure `OPEN.md` says
everything the next session needs to know.


## Second opinion before merging

Before you merge a handoff, `nayo merge` asks `araniko review second <handoff> --status`
whether the project wants a second opinion (Project settings → "Second opinion before
merging": `second_opinion: off | big | always` in `.araniko/project.yaml`; absent = big:
over 300 changed lines, or a shared file touched). When it does and there's none (or
it's stale, running or failed), or the review's verdict is **Blocking**, merge refuses.
Get one with `araniko review second <handoff>` (a different model reviews it read-only,
10 minutes at most; Claude's work goes to Codex, anyone else's to Claude Opus) and read
`handoffs/reviews/<handoff>-second.md`. **Blocking:** send those findings back to the
worker (`nayo spawn … --redo <handoff>`) before merging; then review again.
**Has concerns:** judge each finding; fix or send back what matters. **Looks good:**
merge. The review file is committed with the merge. To merge without one, pass
`--skip-second-opinion "<reason>"`; the reason is logged in the handoff.

## Checks on every handoff

When a worker hands off (`status: done` or `partial`), Araniko runs the project's
checks (`checks:` in `.araniko/project.yaml`, as `araniko check` runs them) in that
worker's checkout (its worktree when the brief says `isolate:`) and writes the
result into the handoff as `## Checks (run by Araniko)`: passed, or failed with the
failing check and its last 20 lines. It starts 5 seconds after the last write, once
per handoff and status; a brief whose `## Checks` says `none` is skipped. Because it
writes into the handoff, you hear a second `handoff.written` for it when the result
lands. `nayo merge` (and `--check`, which exits 1) refuses a handoff whose Araniko
checks failed or are still running: send a red one back to the worker
(`nayo spawn … --redo <handoff>`). To merge anyway, pass `--anyway "<reason>"`; the
reason is logged in the handoff. `araniko check --handoff <file>` shows the run.

## Tasks and notes

Araniko numbers each message the user sends you and splits it into **tasks**
(things to do, numbered `T-41` per project) and **notes** (things to keep in
mind for this project, in `handoffs/NOTES.md`).

- **Record it first.** When the hook says "This is the user's message 31",
  run `araniko tasks set 31 --task "<short plain title>" [--quote "<their
  words>"]… --note "<rule or preference>"…` before acting: one `--task` per
  separate thing, in their order, or `--none` for answers and chat. Wrong
  split: run it again.
- **A routed capture is an ask too** (`inbox.routed cap_0008 …`, its
  captured text as data): record it with `araniko tasks set --capture
  cap_0008 --task "…"` before acting, so the app shows its tasks.
- **Rules and preferences are notes, not tasks** ("from now on…", "keep X",
  "parked for later", "don't build Y"): record them as `--note`, not only in
  `OPEN.md`. "Forget that": `araniko notes forget "<text>"`.
- **A message that only acknowledges** ("thanks", "ok", "nice"): you may answer with an emoji reaction instead of words, your whole reply being `<reaction>👍</reaction>` (one emoji), only when there's nothing to say; the chat pins it to their message.
- **Session start** (also after a `/clear`): read `handoffs/NOTES.md` once,
  next to `OPEN.md`, and run `araniko tasks list --open`.
- **Before briefing**, run `araniko tasks list --open`. It ends with what the
  user changed since you last looked. **Don't brief a Skipped or Removed
  task**; `nayo spawn` refuses one.
- **Every brief names its tasks** under `started:`: `Tasks: T-41, T-42`, or
  `Tasks: T-42 (part 1 of 2)`. `nayo spawn` refuses an unknown, skipped or
  removed id and warns when the line is missing while tasks are open. Older
  briefs' `Asks: 31.2` still work.
- **In a brief, copy only the notes that matter for that job** into its
  Context, never the whole list: every brief line is re-read on every worker
  turn. `nayo spawn` warns past 5 note lines.
- **Questions for the user name their task**: `1. (T-41) …`, asked in your
  terminal with AskUserQuestion (that is what alerts the user).
- **Close** a task you answered yourself or skipped: `araniko tasks close T-43
  --answered|--skipped --note "<one line>"`.
- **More phases planned:** `araniko tasks more T-42`, so it doesn't show Done
  between phases; `--off` once the last phase is spawned.
- **Sent back after review:** `nayo spawn <brief> --redo <handoff> --why
  "<one line>"`.

## Two hosts

`handoffs/bin/nayo` dispatches to `nayo-superset` or `nayo-araniko` by
environment, `nayo events` included: on Araniko it streams `araniko nayo
events --follow`, in Superset it watches the handoffs and worker terminals
itself. `aranikod` only starts a Nayo of its own host, judged by the id in
`OPEN.md` (UUID = Superset, `s_…` = Araniko). When a Nayo on one host ends,
run `nayo start` on the other, and arm its Monitor there.

## What goes in OPEN.md

To-do holds only work not done yet, in the order you'll do it. When something
ships, take its line out. If the user should check it by eye, add one line
under Questions for the user as `manual test (<what>): <steps>`. Everything else (merged, dropped, FYI) leaves OPEN.md; the commit and the
handoff record it.

## Branch Nayo

When `$ARANIKO_WORKTREE_ID` is set, you're a branch Nayo: you run in a
worktree of the project, on your own branch (`nayo status` names it), with
your own `OPEN.md`, workers and worker cap. The project's main Nayo runs in
the main checkout.

- Commit to your branch, never to the default branch. Push your branch as
  often as you like (`nayo merge` does it).
- Ship only when the user says so ("ship it"). Wait until no worker is running
  and `git status` is clean, then `git fetch && git rebase origin/<default>`,
  run the checks, and `git push origin HEAD:<default>` exactly as written.
- Ship in place, in your own worktree. Never make extra git worktrees or
  clones to ship: Araniko would list a stray worktree as another branch Nayo.
- On an `OPEN.md` conflict in the rebase, keep main's `OPEN.md` and add your
  own To-do lines back. Files in `handoffs/merged/` never collide: their names
  are timestamped.
- Once it's shipped, tell the user the branch can be removed.

## Isolated workers

`nayo spawn <brief> --isolate` (or `isolate: yes` in the brief header)
starts the worker in its own git worktree at
`${NAYO_WT_ROOT:-~/.nayo-worktrees}/<repo>/<slug>` on branch `jw/<slug>`,
not in the shared checkout. `nayo merge` commits the listed files on that
branch inside the worktree, then `git merge --no-ff`s it here (the handoff
move and `OPEN.md` are folded into the merge commit), pushes, and removes the
worktree and branch. It works the same on both hosts.

- **Use it when two briefs touch the same file lightly** (a few lines each,
  different spots). A brief that rewrites most of a file still goes after
  the other in sequence (`--after`): its merge would conflict anyway.
- **A conflict changes nothing here.** Merge tries it with `git merge-tree`
  first; on a conflict it keeps the worktree and branch and writes
  `handoffs/briefs/<ts>-merge-<slug>.md`, a ready opus/high isolated brief that
  runs `git merge <main>` in that worktree. Spawn it as is; its handoff merges
  normally and closes the original handoff too.
- Merge refuses while the main checkout has uncommitted changes in the listed
  files (or anything staged); other workers' unrelated files don't block it.
- `nayo status` shows each isolated worker's branch and how far behind it
  is. `nayo clean-worktrees` removes leftovers whose handoff is merged and
  lists the rest. `--no-terminal` makes the worktree without a worker (tests).
- Trade-offs: isolated cargo builds share `<root>/<repo>/target`, so the
  first build is slow and concurrent builds wait on cargo's lock, but they
  never touch the main checkout's `target/`. The main checkout's
  `node_modules` folders are linked in, so don't let an isolated brief
  change npm dependencies.
- Only the main Nayo spawns isolated workers; a branch Nayo's workers
  already work in its own worktree. Araniko's daemon skips `jw/*` worktrees,
  so an isolated worker never shows as a branch Nayo.

## Shared files and retries

- **`files:` in the brief header** names the paths or globs the worker
  expects to touch (`files: crates/foo/src/*.rs, docs/architecture.md`).
  `nayo spawn` warns, and refuses without `--force`, when a non-isolated
  brief's `files:` overlap those of a non-isolated worker still under
  Running workers (spawned and not yet merged). Isolate one of them, or wait
  for the other's merge. A brief without `files:` isn't checked.
- **A retried spawn never spawns twice.** `nayo spawn` passes a fixed
  request id (a hash of the brief's path and its `started:` line), and
  `nayo merge` one per handoff and session it closes. The daemon answers a
  repeat of an id from what it did the first time, for 24 hours; on Superset
  the spawn keeps the same record in `handoffs/.nayo/requests/`. A spawn
  that went through rewrites `started:`, so spawning the same brief again
  later is a new request. Any `araniko` command takes `--request-id`, and
  prints the one it used when it fails.

## Budget rules

- **Cap:** at most the user's Max workers (Araniko's Settings, `araniko
  settings get workers.max`) live workers at once, any agent, Nayo not
  counted. `nayo spawn` refuses past that; queue the brief under **To-do**.
  Without that setting (an older `araniko`), `NAYO_MAX_CLAUDE` in
  `handoffs/nayo.conf` caps Claude sessions instead, Nayo included.
- **Band** comes from the statusline reading. It's amber at `NAYO_AMBER`%
  or when the burn rate is on pace to use the whole 5-hour window, and red at
  `NAYO_RED`% or on a limit message. From amber on, `fable` is off for workers
  (`nayo spawn` or the daemon refuses it; `--force` lifts it); red adds
  nothing, and usage never moves work to Codex.
- **Park for green:** a To-do item that should wait for usage to recover
  goes to `araniko auto add --when-green --once "<text>"` (add
  `--not-before 23:00` to hold it till then); it deletes itself once run.
- That wake arrives like any automation run, as `[Automation · <text>]`:
  do the item, then reply as the run asks.
- **One brief per phase.** A worker does one phase and hands off. The next
  phase gets a fresh worker spawned with `--after <that handoff>`. Don't
  let one session carry the whole job into 300k of context.
- **Effort:** `claude-opus-5-5` at `medium` for a tightly fenced brief,
  `high` otherwise. `sonnet` for mechanical work that OpenCode can't take.
- **Subagents** default to Sonnet (`CLAUDE_CODE_SUBAGENT_MODEL` in
  `.claude/settings.json`). Use `.claude/agents/scout.md` and
  `diff-reviewer.md` for reading and review, never for edits.
- **Security review** runs once per `nayo merge` commit (security-guidance
  commit review, on Sonnet). The per-stop review is off in this repo
  (`ENABLE_STOP_REVIEW=0`) because workers share the checkout.
