# Working in Hamro Steps as a worker

This repo runs the Jarvis workflow on Ultron. **If you are Codex, OpenCode,
or any agent other than Claude Code, you are always a worker.** If you are
Claude Code, you are a worker when your first prompt is a task brief or points
at `handoffs/briefs/`; otherwise you are Jarvis — read `CLAUDE.md` instead.

The user talks to Jarvis, almost never to you. Never wait for the user or ask
them anything in the terminal: your questions go in your handoff file, Jarvis
batches them for the user, and the answers come back to you over this
terminal. The code lives at the repo root.

## Worker rules

Several workers edit the same checkout at once, in separate Ultron sessions. So:

- **Never commit, push, tag, or open a PR.** Jarvis does that.
- **Never run `git stash`, `git checkout --`, `git restore`, `git reset`,
  `git clean`, `git switch`, `git worktree`, or `git rebase`/`merge`.** Any of
  them silently reverts other workers' uncommitted edits. Read-only git
  (`status`, `diff`, `log`, `show`, `blame`) is fine.
- **Touch only the files your task needs.** The brief's "may touch" list is a
  hard boundary, not a hint — several workers share this checkout, and a file
  you edit outside it is someone else's work you just broke. If you must edit a shared file
  (project manifests and shared configuration), keep the edit minimal and name it in your handoff.
- **Your own subagents follow these same rules** — say so in their briefs.
  They read and summarise; they don't edit. They run on Sonnet by default.
- **Only Jarvis does these:** committing, pushing, adding dependencies, releases and production changes. Write what's needed (a migration
  file, a release note) but leave applying it to Jarvis and flag it in your
  handoff.
- **Ask everything once, up front.** If the task needs rulings, put all your
  questions in your first handoff with `status: blocked` and stop. After the
  answers arrive on this terminal, finish your brief without stopping again,
  unless something truly new comes up.
- **Tasks.** The brief's `Tasks:` header line names what the user asked for
  (`T-41`; older briefs say `Asks: 31.2`). Leave it as it is, and start each
  question for the user with the task it's about: `1. (T-41) …`.
<!-- ultron:reading-rules: Ultron appends this bullet to every Claude worker's system prompt, so keep it self-contained -->
- **Keep your context small: every step re-sends all of it.** Whatever you
  read stays in your context and is paid for again on every later call, so
  a 3,000-token read early in a 60-step task costs 180,000. So:
  - Find before you read: `grep -n` (or `rg -n`) for the symbol, then
    `sed -n 'a,bp'` that range with a little margin, at most ~150 lines at
    a time. Never `cat` a source or CSS file over ~300 lines (`wc -l` first),
    and never `cat` several files at once. The Read tool too: give it an
    `offset` and `limit` (it reads 2,000 lines when you don't).
  - Don't read the same lines twice. After your own edit, trust it; check
    it with a test or `grep -n`, not by re-reading the file.
  - Cap command output: pipe searches and logs through `head`, and for a
    build or test show only the failures (`… 2>&1 | grep -E 'error|FAIL' |
    head -40`), not the full log.
  - Read only the doc sections and design files your brief names, and no
    old handoff unless the brief points at it. For a question that spans
    many files, use a subagent (the scout one, where the project has it):
    it answers in a few lines and keeps the file dumps out of your context.
  - When answers to your questions arrive, build from what you already
    know and your handoff; don't re-read files to get back into it.
  - Take a screenshot only to verify the finished result, once per screen,
    not after each edit. Each one costs ~1,500 tokens on every later call.
  - Never sleep-poll: run a build or test in the foreground with a timeout,
    or in the background and wait for its notification.
<!-- /ultron:reading-rules -->
- **One brief, then hand off.** Do the phase your brief describes, write the
  handoff, and stop. The next phase gets a fresh worker that starts from your
  handoff, so write it for that reader: what's done, what's left, where.
- **Verification:** Use isolated test data and report the exact checks run.
- **Checks:** run `ultron check` before handing off. It runs the project's
  checks (`scripts/check-ios.sh`: xcodebuild test; `scripts/check-backend.sh`: Convex typecheck + tests), from `checks:` in `.ultron/project.yaml`, records the
  result for Jarvis and prints a `## Checks run` section: paste it into your
  handoff as it is. Jarvis won't merge a handoff whose checks are red. A run
  can take minutes, so give the call a long timeout. Say plainly what you
  didn't check.

## Isolated workers

If your prompt says **you are isolated**, you have your own git worktree on
your own branch (`jw/<slug>`), outside the repo, so another worker can edit
the same file at once. What changes for you:

- **Your working directory is the worktree.** Edit, build and test only
  there, `ultron check` included; the brief's repo paths are relative to it.
  Never touch the main checkout. The main checkout's `node_modules` folders
  are linked in, and cargo builds go to a shared build folder, so nothing
  needs installing (the first build can still wait on another worker's).
- **Your handoff goes to the main checkout's `handoffs/`**, at the absolute
  path your prompt gives, so Jarvis sees it. List files relative to the repo,
  as usual.
- **Still no git that changes state:** Jarvis commits your branch and merges
  it. The one exception is a **merge brief** (its header has `merges:`): there
  you run `git merge <main branch>` inside your worktree, and
  `git merge --abort` to start over. Resolve the conflicts, but don't stage
  by hand or commit. Jarvis commits the merge.

## When you finish a task

Write one handoff file, `handoffs/YYYY-MM-DD-HHMM-<short-slug>.md`:

```markdown
# <one-line task title>
status: done | blocked | partial
agent: claude <model> | codex <model>
brief: handoffs/briefs/<the brief you worked from>.md
## What the user asked
<the request, briefly>
## What changed
<behaviour, in plain words>
## Files
- path/relative/to/repo — created | modified | deleted
## Checks run
<what `ultron check` printed, plus anything else you checked; say plainly what wasn't checked>
## Libraries used
<one line per library touched, or `none touched`>
## Questions for the user
<only when status: blocked — numbered, each answerable in a line, each naming its task: `1. (T-41) …`>
## Notes for Jarvis
<things only Jarvis may do, shared-file edits, suggested commit message>
```

The file list must be complete and exact — Jarvis commits by that list, so a
missing file is left behind and an extra one drags in someone else's work.
Under Libraries used, name each library from the brief's `## Libraries and
design rules` that your change used or touched, one line each (`Hugeicons —
icons in the Settings sidebar`), or write `none touched`.
Then say in the terminal that you've handed off, and name the file. If you get
more instructions for the same task later, update the same handoff file
instead of starting a new one.
