#!/usr/bin/env python3
"""nayo-verify.py: the engine behind `nayo merge <handoff> --check --verify [--reuse]`.
The host script (nayo-araniko, nayo-superset) prints its usual review, then runs this with
`python3 -I`; nothing else should call it. Ported from the Jarvis kit's jarvis-verify.py.

  nayo-verify.py --root <checkout> --handoff <file> --runner <host script> --bash <path>
                 [--source <worktree> --base <commit>] [--max-sec N] [--lock-wait N] [--grace N]
                 [--reuse=0|1] [--max-age N] [--reuse-env "NAMES"]

It runs the brief's ```bash verify``` blocks under ## Checks against HEAD plus exactly the
handoff's listed changes (taken from --source, an isolated worker's worktree, when given:
its changes since --base), in a detached worktree of its own:

  handoffs/.nayo/verify/<attempt>/        0700, always removed at the end
      owner      PID and start time of the verifier, the running check's process group
      tree/      the worktree: HEAD, the listed changes, verify-inputs copies
      snapshot/  the listed files' bytes as read
      checks/    each block's script, byte for byte
  handoffs/.nayo/verify-results/<attempt>/  kept: result, check-N.log

Each block runs in a fresh `bash --noprofile --norc -e -o pipefail` at the worktree root,
in a process group of its own, with its timeout. A class other than light runs under
`nayo lock <class>` of the original checkout when the host script has `lock`, and
unleased (said so) when it doesn't. One cleanup path, for pass, failure, timeout, INT,
TERM and HUP, stops what is left of the check's group and removes the worktree; a watchdog
in its own session does the same if this process dies without it. Nothing is committed and
the checkout's files, index and HEAD are left as they were.

One attempt at a time per checkout (a flock on handoffs/.nayo/verify.lease). With --reuse,
a pass is reported instead of re-run when the newest finished attempt for the same handoff
had the same verify_key (HEAD, the candidate tree, the listed bytes, the brief without
started:, the blocks, the inputs, this helper and the runner, bash, OS and an environment
digest), passed, cleaned up, and finished under --max-age seconds ago, and no block says
reuse=never.

Exit 0 passed · 1 file list mismatch, missing input or a failed check · 2 bad
brief/handoff or setup/cleanup failure · 75 lease wait ran out or the inputs moved ·
124 a check timed out · 129/130/143 HUP/INT/TERM.
Python 3.8+, standard library only.
"""
import argparse, fcntl, hashlib, json, os, re, shutil, signal, stat, subprocess, sys, time

KEY_SCHEMA = "nayo-verify-key-1"
SKEW = 60
KEY_ENV = ("PATH", "HOME", "SHELL", "LANG", "TZ", "CI", "NODE_ENV", "NODE_OPTIONS", "PYTHONHASHSEED",
           "JAVA_HOME", "GOPATH", "GOFLAGS", "CARGO_HOME", "CARGO_TARGET_DIR", "RUSTUP_TOOLCHAIN",
           "LD_LIBRARY_PATH", "DYLD_LIBRARY_PATH")
TAIL = 40
ACTIONS = ("created", "modified", "deleted")
STATE_DIR = "handoffs/.nayo"
SIGCODE = {signal.SIGINT: 130, signal.SIGTERM: 143, signal.SIGHUP: 129}
# what a check must not inherit: another checkout's git, a profile, a dependency path
SCRUB = ("BASH_ENV", "ENV", "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR",
         "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_PREFIX", "GIT_NAMESPACE",
         "PYTHONPATH", "PYTHONHOME", "NODE_PATH", "VIRTUAL_ENV", "NAYO_LOCKS_HELD", "JARVIS_LOCKS_HELD",
         "CLAUDE_PROJECT_DIR", "OLDPWD")
CONVERT = """Mark each command the brief's ## Checks should run, for example:

```bash verify class=light timeout=300
bash -n src/tool.sh
```

class=light runs at once; any other class runs under that class's `nayo lock` lease.
Prose around the blocks stays yours to review."""


class Fail(Exception):
    def __init__(self, code, msg):
        Exception.__init__(self, msg)
        self.code, self.msg = code, msg


class Interrupted(Exception):
    pass


def say(msg=""):
    print(msg, flush=True)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def fsha(path):
    try:
        with open(path, "rb") as f:
            return sha(f.read())
    except OSError:
        return None


def git_env():
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_") or k == "GIT_CONFIG_NOSYSTEM"}
    env["GIT_TERMINAL_PROMPT"] = "0"
    env["LC_ALL"] = "C"
    return env


def git(root, *args, inp=None, env=None, ok=(0,), literal=True):
    pre = ["--literal-pathspecs"] if literal else []    # check-ignore takes no pathspec magic
    p = subprocess.run(["git", "-C", root] + pre + ["-c", "core.hooksPath=/dev/null"] + list(args),
                       input=inp, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env or git_env())
    if p.returncode not in ok:
        raise Fail(2, "git %s failed: %s" % (args[0], p.stderr.decode("utf-8", "replace").strip()[:400]))
    return p


def lstart_of(pid):
    """A process's start time; empty if gone or a zombie."""
    try:
        out = subprocess.run(["ps", "-o", "stat=,lstart=", "-p", str(pid)], stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, env=dict(os.environ, TZ="UTC", LC_ALL="C")).stdout.decode()
    except OSError:
        return ""
    f = out.split()
    return "" if len(f) < 6 or f[0].startswith("Z") else "_".join(f[1:6])


def group_members(pgid):
    """Live (non-zombie) processes in a process group."""
    try:
        out = subprocess.run(["ps", "-A", "-o", "pid=,pgid=,stat="], stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL).stdout.decode()
    except OSError:
        return []
    return [int(f[0]) for f in (line.split() for line in out.splitlines())
            if len(f) >= 3 and f[1] == str(pgid) and not f[2].startswith("Z")]


def stop_group(pgid, start, grace, direct=True):
    """TERM, then KILL after grace, a check's process group, only while it is still ours: our
    unreaped child (direct), or a leader whose start time still matches."""
    if not pgid:
        return
    pgid = int(pgid)
    if not direct:
        leader = lstart_of(pgid)
        if leader and start and leader != start:
            return                    # the PID is someone else's now
        if not leader and not group_members(pgid):
            return
    for sig, wait in ((signal.SIGTERM, grace), (signal.SIGKILL, 2)):
        if not group_members(pgid):
            return
        try:
            os.killpg(pgid, sig)
        except (ProcessLookupError, PermissionError):
            return
        end = time.time() + wait
        while time.time() < end:
            if not group_members(pgid):
                return
            time.sleep(0.05)


def remove_attempt(root, attempt, tree):
    """Remove an attempt's worktree (git's entry for it too) and its directory; True when nothing is left."""
    if tree and os.path.lexists(tree):
        git(root, "worktree", "remove", "--force", "--force", tree, ok=(0, 1, 128))
    if tree and os.path.lexists(tree):
        shutil.rmtree(tree, ignore_errors=True)
    git(root, "worktree", "prune", ok=(0, 1, 128))
    if attempt and os.path.lexists(attempt):
        shutil.rmtree(attempt, ignore_errors=True)
    return not ((attempt and os.path.lexists(attempt)) or (tree and os.path.lexists(tree)))


def write_atomic(path, text, mode=0o600):
    tmp = "%s.tmp.%d" % (path, os.getpid())
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.replace(tmp, path)


def read_rec(path):
    d = {}
    try:
        with open(path) as f:
            for line in f:
                m = re.match(r"^(\w+): ?(.*)$", line.rstrip("\n"))
                if m:
                    d[m.group(1)] = m.group(2)
    except OSError:
        pass
    return d


def update_rec(path, **kv):
    d = read_rec(path)
    d.update({k: str(v).replace("\n", " ") for k, v in kv.items()})
    write_atomic(path, "".join("%s: %s\n" % i for i in d.items()))


# ---------------------------------------------------------------- paths

def path_problem(p):
    """Why a listed path is unusable, or None. p has had a leading ./ removed."""
    if not p:
        return "empty path"
    if any(ord(c) < 32 or ord(c) == 127 for c in p):
        return "control character in path"
    if p.startswith("/") or p.startswith("~"):
        return "absolute path"
    if p.endswith("/"):
        return "a directory (list each file)"
    if re.search(r"[*?\[]", p):
        return "a glob (list each file)"
    parts = p.split("/")
    if any(x in ("", ".", "..") for x in parts):
        return "not a plain relative path (., .. or //)"
    if any(x.lower() == ".git" for x in parts):
        return "inside .git"
    if p == STATE_DIR or p.startswith(STATE_DIR + "/"):
        return "verifier state (%s)" % STATE_DIR
    return None


def norm(p):
    while p.startswith("./"):
        p = p[2:]
    return p


def ancestors(p):
    parts = p.split("/")
    return ["/".join(parts[:i]) for i in range(1, len(parts))]


def symlinked_ancestor(base, p):
    for a in ancestors(p):
        try:
            st = os.lstat(os.path.join(base, a))
        except (FileNotFoundError, NotADirectoryError):
            return None
        if stat.S_ISLNK(st.st_mode):
            return a
        if not stat.S_ISDIR(st.st_mode):
            return None
    return None


# ---------------------------------------------------------------- documents

FENCE = re.compile(r"^( {0,3})(`{3,}|~{3,})(.*)$")


def header_field(text, key):
    m = re.search(r"^%s:[ \t]*(.*)$" % re.escape(key), text, re.M)
    return m.group(1).split()[0] if m and m.group(1).split() else ""


def closes(m, mark):
    return m and m.group(2)[0] == mark[0] and len(m.group(2)) >= len(mark) and not m.group(3).strip()


def sections(lines, title):
    """[(start, end)] line ranges of the level-two sections named title, fences respected."""
    out, cur, fence = [], None, None
    for i, line in enumerate(lines):
        m = FENCE.match(line)
        if fence:
            if closes(m, fence):
                fence = None
            continue
        if m:
            fence = m.group(2)
            continue
        if line.startswith("## "):
            if cur is not None:
                out.append((cur, i))
                cur = None
            if line[3:].strip() == title:
                cur = i + 1
    if fence:
        raise Fail(2, "unclosed ``` fence")
    if cur is not None:
        out.append((cur, len(lines)))
    return out


def parse_checks(text, brief, max_sec):
    """The ```bash verify``` blocks and the ```json verify-inputs``` block under ## Checks."""
    lines = text.split("\n")
    try:
        secs = sections(lines, "Checks")
    except Fail as e:
        raise Fail(2, "%s: %s" % (brief, e.msg))
    if len(secs) > 1:
        raise Fail(2, "%s has %d ## Checks sections; keep one" % (brief, len(secs)))
    blocks, inputs = [], None
    if secs:
        a, b = secs[0]
        i = a
        while i < b:
            m = FENCE.match(lines[i])
            if not m:
                i += 1
                continue
            indent, mark, info = m.group(1), m.group(2), m.group(3).strip()
            j = i + 1
            while j < b and not closes(FENCE.match(lines[j]), mark):
                j += 1
            if j >= b:
                raise Fail(2, "%s: unclosed ``` fence in ## Checks (line %d)" % (brief, i + 1))
            body = "\n".join(lines[i + 1:j])
            words = info.split()
            where = "%s line %d" % (brief, i + 1)
            if words[:2] == ["bash", "verify"]:
                if indent:
                    raise Fail(2, "%s: an indented bash verify block; verify blocks start in column 1" % where)
                attrs = {}
                for w in words[2:]:
                    k, eq, v = w.partition("=")
                    if not eq or k not in ("class", "timeout", "reuse"):
                        raise Fail(2, "%s: unknown verify attribute '%s' (class=, timeout=, reuse=)" % (where, w))
                    if k in attrs:
                        raise Fail(2, "%s: %s= given twice" % (where, k))
                    attrs[k] = v
                if "class" not in attrs or "timeout" not in attrs:
                    raise Fail(2, "%s: a verify block needs class=<name> and timeout=<seconds>" % where)
                if not re.match(r"^[a-z0-9_]+$", attrs["class"]):
                    raise Fail(2, "%s: class names are a-z, 0-9 and _, not '%s'" % (where, attrs["class"]))
                if not re.match(r"^[1-9][0-9]*$", attrs["timeout"]):
                    raise Fail(2, "%s: timeout= takes whole seconds above 0, not '%s'" % (where, attrs["timeout"]))
                if int(attrs["timeout"]) > max_sec:
                    raise Fail(2, "%s: timeout=%s is over NAYO_VERIFY_MAX_SEC=%d" % (where, attrs["timeout"], max_sec))
                if attrs.get("reuse", "tree") not in ("tree", "never"):
                    raise Fail(2, "%s: reuse= takes tree or never" % where)
                if not body.strip():
                    raise Fail(2, "%s: an empty verify block" % where)
                blocks.append({"n": len(blocks) + 1, "line": i + 1, "class": attrs["class"],
                               "timeout": int(attrs["timeout"]), "reuse": attrs.get("reuse", "tree"),
                               "body": body + "\n"})
            elif words == ["json", "verify-inputs"]:
                if indent:
                    raise Fail(2, "%s: an indented verify-inputs block" % where)
                if inputs is not None:
                    raise Fail(2, "%s: a second verify-inputs block; keep one" % where)
                inputs = parse_inputs(body, where)
            elif "verify" in words or "verify-inputs" in words:
                raise Fail(2, "%s: only ```bash verify``` and ```json verify-inputs``` blocks run, not '%s'" % (where, info))
            i = j + 1
    if not blocks:
        raise Fail(2, "no executable Checks blocks; add a bash verify block to %s\n\n%s" % (brief, CONVERT))
    return blocks, inputs or {"requires": [], "copy": []}


def parse_inputs(body, where):
    try:
        d = json.loads(body)
    except ValueError as e:
        raise Fail(2, "%s: verify-inputs isn't valid JSON: %s" % (where, e))
    if not isinstance(d, dict) or set(d) - {"requires", "copy"}:
        raise Fail(2, "%s: verify-inputs is an object with requires and copy only (a dependency such as "
                      "node_modules is installed by a setup block with reuse=never)" % where)
    out = {"requires": [], "copy": []}
    for k in ("requires", "copy"):
        v = d.get(k, [])
        if not isinstance(v, list) or not all(isinstance(x, str) for x in v):
            raise Fail(2, "%s: verify-inputs %s is a list of paths" % (where, k))
        for x in v:
            p = norm(x)
            why = path_problem(p)
            if why:
                raise Fail(2, "%s: verify-inputs %s '%s': %s" % (where, k, x, why))
            if p not in out[k]:
                out[k].append(p)
    return out


def parse_files(text, handoff_rel):
    """The ## Files entries: [[path, action or None]], the handoff's own entry left out."""
    lines = text.split("\n")
    secs = sections(lines, "Files")
    if not secs:
        raise Fail(1, "the handoff has no ## Files section")
    if len(secs) > 1:
        raise Fail(2, "the handoff has %d ## Files sections; keep one" % len(secs))
    a, b = secs[0]
    entries, seen, fence = [], {}, None
    for i in range(a, b):
        line = lines[i]
        m = FENCE.match(line)
        if fence:
            if closes(m, fence):
                fence = None
            continue
        if m:
            fence = m.group(2)
            continue
        if re.match(r"^\s+[-*+] ", line):
            raise Fail(2, "## Files line %d: a nested list item; list each file at the top level" % (i + 1))
        if not re.match(r"^[-*+] ", line):
            continue
        item = line[2:].strip()
        if item.startswith("`"):
            end = item.find("`", 1)
            if end < 0:
                raise Fail(2, "## Files line %d: unclosed backtick" % (i + 1))
            path, rest = item[1:end], item[end + 1:]
        else:
            m = re.match(r"^(\S+)(.*)$", item)
            path, rest = (m.group(1), m.group(2)) if m else ("", "")
        path = norm(path)
        if path.startswith("path/relative"):
            continue
        action = None
        if rest.strip():
            r = re.match(r"^\s+(?:—|–|--|-|:)\s*(.*)$", rest) or re.match(r"^\s+(\(.*)$", rest)
            if not r:
                raise Fail(2, "## Files line %d: can't tell the path from the rest: %s" % (i + 1, line.strip()))
            w = re.match(r"^\(?([A-Za-z]+)", r.group(1))
            if w and w.group(1).lower() in ACTIONS:
                action = w.group(1).lower()
        why = path_problem(path)
        if why:
            raise Fail(2, "## Files line %d: %s: %s" % (i + 1, why, path))
        if path == handoff_rel:
            continue
        if path in seen:
            if seen[path] != action and seen[path] and action:
                raise Fail(2, "## Files lists %s as both %s and %s" % (path, seen[path], action))
            continue
        seen[path] = action
        entries.append([path, action])
    return entries


# ---------------------------------------------------------------- the attempt

class Verify:
    def __init__(self, a):
        self.a = a
        self.root = os.path.realpath(a.root)
        self.src = os.path.realpath(a.source) if a.source else self.root   # where the listed changes are
        self.state = os.path.join(self.root, STATE_DIR)
        self.attempt = self.results = self.tree = None
        self.watchdog = self.wd_w = self.lease_fd = None
        self.child = None
        self.cleaned = False
        self.sig = None
        self.key = self.reused = None
        self.snaps, self.copies, self.unlisted = [], {}, []
        self.tree_id = ""

    def on_signal(self, signum, frame):
        if self.sig is None:
            self.sig = signum
        if not self.cleaned:
            raise Interrupted()

    def quiet_signals(self):
        for s in SIGCODE:
            signal.signal(s, lambda n, f: setattr(self, "sig", self.sig or n))

    # ---- preflight: nothing written yet

    def preflight(self):
        a = self.a
        hpath = os.path.realpath(a.handoff)
        if not os.path.isfile(hpath):
            raise Fail(2, "no handoff %s" % a.handoff)
        self.handoff_rel = os.path.relpath(hpath, self.root)
        if self.handoff_rel.startswith(".."):
            raise Fail(2, "the handoff isn't inside this checkout")
        self.hbytes = open(hpath, "rb").read()
        try:
            htext = self.hbytes.decode("utf-8")
        except UnicodeDecodeError:
            raise Fail(2, "the handoff isn't UTF-8")
        self.status = header_field(htext, "status")
        if self.status == "blocked":
            raise Fail(2, "status is blocked — answer its questions first; nothing run")
        brief = header_field(htext, "brief")
        if not brief:
            raise Fail(2, "the handoff names no brief: (its brief's ## Checks are what --verify runs)")
        self.brief_rel = norm(brief)
        bpath = os.path.join(self.root, self.brief_rel)
        if path_problem(self.brief_rel):
            raise Fail(2, "brief: %s isn't a path inside this checkout" % brief)
        if not os.path.isfile(bpath) or os.path.islink(bpath):
            raise Fail(2, "brief: %s isn't a file here" % brief)
        self.bbytes = open(bpath, "rb").read()
        try:
            btext = self.bbytes.decode("utf-8")
        except UnicodeDecodeError:
            raise Fail(2, "%s isn't UTF-8" % self.brief_rel)
        self.blocks, self.inputs = parse_checks(btext, self.brief_rel, a.max_sec)

        p = git(self.root, "rev-parse", "--verify", "-q", "HEAD^{commit}", ok=(0, 1))
        if p.returncode:
            raise Fail(2, "HEAD has no commit yet; verify needs one to start from")
        self.head = p.stdout.decode().strip()
        if git(self.root, "ls-files", "-u", "-z").stdout:
            raise Fail(2, "the checkout has unmerged paths; resolve them first")
        heavy = sorted({b["class"] for b in self.blocks if b["class"] != "light"})
        self.can_lock = False
        if heavy:
            try:
                runner = open(a.runner, encoding="utf-8", errors="replace").read()
            except OSError:
                runner = ""
            self.can_lock = re.search(r"^\s*(?:[\w-]+\|)*lock(?:\|[\w-]+)*\)", runner, re.M) is not None
            if not self.can_lock:
                say("verify: this kit has no `nayo lock`, so class %s runs without a lease" % ", ".join(heavy))
        self.entries = parse_files(htext, self.handoff_rel)
        self.classify()
        self.check_inputs()

    def head_entries(self, paths):
        """{path: (mode, type, oid)} for the paths HEAD has."""
        out = {}
        if not paths:
            return out
        raw = git(self.root, "ls-tree", "-z", "--full-tree", self.head, "--", *paths).stdout
        for rec in raw.split(b"\0"):
            if rec:
                meta, _, name = rec.partition(b"\t")
                mode, typ, oid = meta.decode().split()
                out[name.decode("utf-8", "surrogateescape")] = (mode, typ, oid)
        return out

    def changed_set(self):
        """The paths changed in the source: against HEAD, or against --base for a worktree."""
        if self.a.base:
            out = set()
            for args in (("diff", "--name-only", "-z", "--no-renames", self.a.base),
                         ("ls-files", "--others", "--exclude-standard", "-z")):
                out |= {x.decode("utf-8", "surrogateescape") for x in git(self.src, *args).stdout.split(b"\0") if x}
            return out
        raw = git(self.src, "status", "--porcelain=v1", "-z", "-uall").stdout.split(b"\0")
        out, i = set(), 0
        while i < len(raw):
            rec = raw[i]
            i += 1
            if len(rec) < 4:
                continue
            out.add(rec[3:].decode("utf-8", "surrogateescape"))
            if rec[0:1] in (b"R", b"C"):
                if i < len(raw):
                    out.add(raw[i].decode("utf-8", "surrogateescape"))
                i += 1
        return out

    def classify(self):
        paths = [e[0] for e in self.entries]
        anc = sorted({x for p in paths for x in ancestors(p)})
        head = self.head_entries(paths + anc)
        for x in anc:
            if x in head and head[x][0] == "160000":
                raise Fail(2, "%s is a submodule; changes inside one can't be verified" % x)
        changed = self.changed_set()
        bad, created = [], []
        for e in self.entries:
            p, action = e
            if p in head and head[p][1] == "tree":
                raise Fail(2, "## Files lists a directory: %s (list each file)" % p)
            if p in head and head[p][0] == "160000":
                raise Fail(2, "## Files lists a submodule: %s (not supported)" % p)
            link = symlinked_ancestor(self.src, p)
            if link:
                raise Fail(2, "## Files: %s is under a symlinked directory (%s)" % (p, link))
            try:
                st = os.lstat(os.path.join(self.src, p))
            except (FileNotFoundError, NotADirectoryError):
                st = None
            if st is not None and not (stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode)):
                raise Fail(2, "## Files: %s is %s, not a file or a symlink" %
                           (p, "a directory" if stat.S_ISDIR(st.st_mode) else "a special file"))
            in_head, here = p in head, st is not None
            want = action or ("modified" if in_head and here else "created" if here else "deleted" if in_head else None)
            if want is None:
                bad.append("  ✗ listed but not changed: %s (not at HEAD, not here)" % p)
                continue
            if want == "created" and in_head:
                bad.append("  ✗ listed as created, but HEAD has it: %s" % p)
            elif want == "modified" and not in_head:
                bad.append("  ✗ listed as modified, but HEAD doesn't have it: %s" % p)
            elif want in ("created", "modified") and not here:
                bad.append("  ✗ listed as %s, but it isn't here: %s" % (want, p))
            elif want == "deleted" and here:
                bad.append("  ✗ listed as deleted, but it's still here: %s" % p)
            elif want == "deleted" and not in_head:
                bad.append("  ✗ listed as deleted, but HEAD doesn't have it: %s" % p)
            elif p not in changed:
                bad.append("  ✗ listed but not changed: %s" % p)
            e[1] = want
            if want == "created":
                created.append(p)
        if created:
            p = git(self.src, "check-ignore", "-z", "--stdin", inp="".join("./%s\0" % x for x in created).encode(),
                    ok=(0, 1), literal=False)
            ign = [norm(x.decode()) for x in p.stdout.split(b"\0") if x]
            if ign:
                raise Fail(2, "listed source is gitignored; make it commit-eligible or declare it a "
                              "verify-inputs copy: %s" % ", ".join(ign[:5]))
        if bad:
            say("\n".join(bad))
            raise Fail(1, "file list doesn't match the checkout — nothing run")
        self.listed = set(paths)
        self.unlisted = sorted(x for x in changed
                               if x not in self.listed and x != self.handoff_rel and not x.startswith("handoffs/"))

    def check_inputs(self):
        head = self.head_entries(self.inputs["copy"])
        for p in self.inputs["copy"]:
            if p in self.listed or p in head:
                raise Fail(2, "verify-inputs copy %s is source (tracked or listed); copy is for untracked inputs" % p)
            full = os.path.join(self.src, p)
            if symlinked_ancestor(self.src, p) or os.path.islink(full):
                raise Fail(2, "verify-inputs copy %s is or is under a symlink; copy takes files" % p)
            if not os.path.isfile(full):
                raise Fail(1, "verification input missing: %s (verify-inputs copy)" % p)

    # ---- side effects start here

    def take_lease(self):
        """One verification per checkout: a flock held until this process exits."""
        os.makedirs(self.state, 0o700, exist_ok=True)
        gi = os.path.join(self.state, ".gitignore")   # never show up in git status, whatever .gitignore says
        if not os.path.exists(gi):
            write_atomic(gi, "*\n", 0o644)
        self.lease_fd = os.open(os.path.join(self.state, "verify.lease"), os.O_RDWR | os.O_CREAT, 0o600)
        end = time.time() + self.a.lock_wait
        said = False
        while True:
            try:
                fcntl.flock(self.lease_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return
            except BlockingIOError:
                if time.time() >= end:
                    raise Fail(75, "another verification of this checkout held its lease for %ds "
                                   "(NAYO_LOCK_WAIT); rerun later" % self.a.lock_wait)
                if not said:
                    say("verify: waiting for another verification of this checkout to finish")
                    said = True
                time.sleep(0.5)

    def sweep(self):
        """Under the lease: remove attempts whose verifier is gone (killed with its watchdog)."""
        vroot = os.path.join(self.state, "verify")
        for n in os.listdir(vroot) if os.path.isdir(vroot) else []:
            att = os.path.join(vroot, n)
            o = read_rec(os.path.join(att, "owner"))
            if o.get("owner") and o.get("owner_start") and lstart_of(o["owner"]) == o["owner_start"]:
                continue
            stop_group(o.get("pgid"), o.get("pgid_start"), self.a.grace, direct=False)
            if remove_attempt(self.root, att, os.path.join(att, "tree")):
                say("verify: removed a verification worktree left behind: %s" % os.path.relpath(att, self.root))

    def start(self):
        self.sweep()
        self.attempt_id = "%s-%d" % (time.strftime("%Y%m%d-%H%M%S"), os.getpid())
        vroot = os.path.join(self.state, "verify")
        os.makedirs(vroot, 0o700, exist_ok=True)
        self.attempt = os.path.join(vroot, self.attempt_id)
        os.mkdir(self.attempt, 0o700)
        self.tree = os.path.join(self.attempt, "tree")
        self.results = os.path.join(self.state, "verify-results", self.attempt_id)
        os.makedirs(self.results, 0o700)
        self.results_rel = os.path.relpath(self.results, self.root)
        self.save_owner(owner=os.getpid(), owner_start=lstart_of(os.getpid()), root=self.root, tree=self.tree)
        self.save_result(handoff=self.handoff_rel, brief=self.brief_rel, head=self.head, status="running",
                         started=int(time.time()), bash_version=self.bash_version())
        self.start_watchdog()

    def bash_version(self):
        p = subprocess.run([self.a.bash, "--noprofile", "--norc", "-c", 'printf %s "$BASH_VERSION"'],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        return p.stdout.decode("utf-8", "replace").strip()

    def save_owner(self, **kv):
        update_rec(os.path.join(self.attempt, "owner"), **kv)

    def save_result(self, **kv):
        update_rec(os.path.join(self.results, "result"), **kv)

    def start_watchdog(self):
        r, w = os.pipe()
        pid = os.fork()
        if pid == 0:
            try:
                os.close(w)
                os.setsid()
                for s in SIGCODE:
                    signal.signal(s, signal.SIG_IGN)
                devnull = os.open(os.devnull, os.O_RDWR)
                os.dup2(devnull, 0)
                os.dup2(devnull, 1)
                data = b""
                while True:
                    chunk = os.read(r, 64)
                    if not chunk:
                        break
                    data += chunk
                if b"done" not in data:   # the verifier died without cleaning up
                    o = read_rec(os.path.join(self.attempt, "owner"))
                    stop_group(o.get("pgid"), o.get("pgid_start"), self.a.grace, direct=False)
                    remove_attempt(self.root, self.attempt, self.tree)
                    self.save_result(status="interrupted", finished=int(time.time()),
                                     note="the verifier died; its watchdog cleaned up")
            finally:
                os._exit(0)
        os.close(r)
        self.watchdog, self.wd_w = pid, w

    def end_watchdog(self):
        if self.wd_w is not None:
            try:
                os.write(self.wd_w, b"done")
                os.close(self.wd_w)
            except OSError:
                pass
            self.wd_w = None
        if self.watchdog:
            for _ in range(50):
                try:
                    if os.waitpid(self.watchdog, os.WNOHANG)[0]:
                        break
                except ChildProcessError:
                    break
                time.sleep(0.02)
            self.watchdog = None

    # ---- the candidate tree

    def read_stable(self, full, p):
        for _ in range(2):
            try:
                st1 = os.lstat(full)
                if stat.S_ISLNK(st1.st_mode):
                    data = os.fsencode(os.readlink(full))
                else:
                    with open(full, "rb") as f:
                        data = f.read()
                st2 = os.lstat(full)
            except OSError as e:
                raise Fail(75, "inputs changed during verification; rerun (%s: %s)" % (p, e.strerror))
            if (st1.st_ino, st1.st_size, st1.st_mtime_ns, st1.st_mode) == \
                    (st2.st_ino, st2.st_size, st2.st_mtime_ns, st2.st_mode):
                return data, st1.st_mode, stat.S_ISLNK(st1.st_mode)
            time.sleep(0.05)
        raise Fail(75, "inputs changed during verification; rerun (%s kept changing while read)" % p)

    def dest(self, p):
        """A path in the tree, its parent directories real directories inside it."""
        cur = self.tree
        for part in p.split("/")[:-1]:
            cur = os.path.join(cur, part)
            try:
                st = os.lstat(cur)
            except FileNotFoundError:
                os.mkdir(cur)
                continue
            if not stat.S_ISDIR(st.st_mode):
                raise Fail(2, "%s: %s in the candidate isn't a directory" % (p, os.path.relpath(cur, self.tree)))
        return os.path.join(self.tree, p)

    def link_inside(self, p):
        tree = os.path.realpath(self.tree)
        real = os.path.realpath(os.path.join(self.tree, p))
        if real != tree and not real.startswith(tree + os.sep):
            raise Fail(2, "## Files: %s is a symlink that leaves the checkout" % p)

    def materialize(self):
        g = git(self.root, "worktree", "add", "--detach", "-q", self.tree, self.head, ok=(0, 1, 128))
        if g.returncode:
            raise Fail(2, "git worktree add failed: %s" % g.stderr.decode("utf-8", "replace").strip()[:400])
        self.save_owner(phase="tree")
        snap = os.path.join(self.attempt, "snapshot")
        os.mkdir(snap, 0o700)
        for p, action in self.entries:
            if action == "deleted":
                full = os.path.join(self.tree, p)
                if os.path.isdir(full) and not os.path.islink(full):
                    raise Fail(2, "%s is a directory in the worktree; can't delete it as a file" % p)
                if os.path.lexists(full):
                    os.unlink(full)
                continue
            data, mode, link = self.read_stable(os.path.join(self.src, p), p)
            f = os.path.join(snap, str(len(self.snaps)))
            with open(f, "wb") as out:
                out.write(data)
            self.snaps.append({"path": p, "file": f, "link": link, "perm": mode & 0o777, "sha": sha(data),
                               "mode": "120000" if link else ("100755" if mode & 0o111 else "100644")})
        for s in self.snaps:
            dest = self.dest(s["path"])
            if os.path.lexists(dest):
                if os.path.isdir(dest) and not os.path.islink(dest):
                    raise Fail(2, "%s is a directory in the candidate" % s["path"])
                os.unlink(dest)
            if s["link"]:
                target = open(s["file"], "rb").read()
                if target.startswith(b"/"):
                    raise Fail(2, "## Files: %s is a symlink to an absolute path; only relative links inside "
                                  "the checkout are verified" % s["path"])
                os.symlink(os.fsdecode(target), dest)
            else:
                shutil.copyfile(s["file"], dest)
                os.chmod(dest, s["perm"])
        for s in self.snaps:     # with everything placed: a link may leave through one placed after it
            if s["link"]:
                self.link_inside(s["path"])
        for p in self.inputs["copy"]:
            data, mode, _ = self.read_stable(os.path.join(self.src, p), p)
            dest = self.dest(p)
            if os.path.lexists(dest):
                raise Fail(2, "verify-inputs copy %s would replace a file in the candidate" % p)
            with open(dest, "wb") as f:
                f.write(data)
            os.chmod(dest, mode & 0o777)
            self.copies[p] = sha(data)
        self.tree_id = self.write_tree()
        self.key = self.verify_key()
        self.save_result(tree=self.tree_id, key=self.key, sources=len(self.entries))

    def write_tree(self):
        """The tree object of HEAD plus the listed changes, through a private index (HEAD's index untouched)."""
        env = git_env()
        env["GIT_INDEX_FILE"] = os.path.join(self.attempt, "index")
        git(self.root, "read-tree", self.head, env=env)
        info = []
        if self.snaps:
            oids = git(self.root, "hash-object", "-w", "--no-filters", "--stdin-paths",
                       inp="".join(s["file"] + "\n" for s in self.snaps).encode(), env=env).stdout.decode().split()
            info += ["%s %s\t%s" % (s["mode"], oid, s["path"]) for s, oid in zip(self.snaps, oids)]
        zero = "0" * len(self.head)
        info += ["0 %s\t%s" % (zero, p) for p, action in self.entries if action == "deleted"]
        if info:
            git(self.root, "update-index", "-z", "--index-info", inp=("\0".join(info) + "\0").encode(), env=env)
        return git(self.root, "write-tree", env=env).stdout.decode().strip()

    def check_env(self):
        env = {k: v for k, v in os.environ.items() if k not in SCRUB}
        env["PWD"] = self.tree
        env["NAYO_VERIFY"] = "1"
        env["NAYO_VERIFY_ROOT"] = self.root
        return env

    def verify_key(self):
        a = self.a
        env = self.check_env()
        names = sorted(set(a.reuse_env.split()) | set(KEY_ENV) | {k for k in env if k.startswith("LC_")})
        u = os.uname()
        m = {
            "schema": KEY_SCHEMA, "head": self.head, "tree": self.tree_id, "handoff": self.handoff_rel,
            "sources": [[s["path"], s["mode"], s["sha"]] for s in self.snaps],
            "actions": [[p, act] for p, act in self.entries],
            "brief": sha(b"".join(x for x in self.bbytes.splitlines(True) if not x.startswith(b"started:"))),
            "blocks": [[b["n"], b["class"], b["timeout"], b["reuse"], b["body"]] for b in self.blocks],
            "inputs": self.inputs, "copies": self.copies, "lock": self.can_lock,
            "runner": fsha(a.runner), "helper": fsha(os.path.abspath(__file__)),
            "bash": [os.path.realpath(a.bash), read_rec(os.path.join(self.results, "result")).get("bash_version", "")],
            "os": [u.sysname, u.release, u.machine],
            "env": sha(json.dumps([[n, env.get(n)] for n in names]).encode()),
        }
        return sha(json.dumps(m, sort_keys=True, separators=(",", ":")).encode())

    def find_pass(self):
        """(attempt id, its result) of a reusable pass of this exact candidate, or (None, why not)."""
        a = self.a
        if a.max_age <= 0:
            return None, "NAYO_REUSE_MAX_AGE=0"
        never = [b["n"] for b in self.blocks if b["reuse"] == "never"]
        if never:
            return None, "check %d says reuse=never" % never[0]
        base = os.path.dirname(self.results)
        now = time.time()
        newest = None
        for n in sorted(os.listdir(base)):
            if n == self.attempt_id:
                continue
            r = read_rec(os.path.join(base, n, "result"))
            if r.get("key") != self.key or r.get("handoff") != self.handoff_rel or r.get("status") == "reused":
                continue
            fin = r.get("finished", "")
            if not fin.isdigit():
                continue
            if int(fin) > now + SKEW:
                return None, "attempt %s finished in the future" % n
            if newest is None or (int(fin), n) > newest[0]:
                newest = ((int(fin), n), n, r)
        if newest is None:
            return None, "no earlier attempt on this exact candidate"
        _, n, r = newest
        if r.get("status") != "passed" or r.get("exit") != "0" or r.get("cleanup") != "ok":
            return None, "the latest attempt on this exact candidate ended %s (%s)" % (r.get("status") or "unfinished", n)
        age = now - int(r["finished"])
        if age >= a.max_age:
            return None, "its pass is %ds old (NAYO_REUSE_MAX_AGE=%d)" % (age, a.max_age)
        return (n, r), None

    # ---- checks

    def requires(self):
        for p in self.inputs["requires"]:
            if os.path.lexists(os.path.join(self.tree, p)):
                continue
            if os.path.lexists(os.path.join(self.src, p)):
                raise Fail(1, "depends on an unlisted file: %s (required by Checks); add the change to "
                              "## Files or declare it a verify-inputs copy" % p)
            raise Fail(1, "required input missing: %s" % p)

    def run_checks(self):
        cdir = os.path.join(self.attempt, "checks")
        os.mkdir(cdir, 0o700)
        n = len(self.blocks)
        env = self.check_env()
        bash = self.a.bash
        for b in self.blocks:
            script = os.path.join(cdir, "block-%d.sh" % b["n"])
            with open(script, "w", encoding="utf-8", newline="") as f:
                f.write(b["body"])
            marker = os.path.join(cdir, "started-%d" % b["n"])
            # the marker starts the timer: a leased check's wait for its lease doesn't count
            argv = [bash, "--noprofile", "--norc", "-c", ': > "$1"; cd "$2" || exit 2; shift 2; exec "$@"',
                    "nayo-verify", marker, self.tree, bash, "--noprofile", "--norc", "-e", "-o", "pipefail", script]
            leased = b["class"] != "light" and self.can_lock
            if leased:   # run from the original checkout, so a checkout-wide class is that checkout's lease
                argv = [self.a.runner, "lock", b["class"], "--wait", str(self.a.lock_wait), "--"] + argv
            log = os.path.join(self.results, "check-%d.log" % b["n"])
            label = "  check %d/%d · %s · %ds" % (b["n"], n, b["class"], b["timeout"])
            code, how, ran = self.supervise(argv, env, log, marker, b, leased)
            self.save_result(check=b["n"])
            if how == "ok" and code == 0:
                say("%s · passed (%ds)" % (label, ran))
                continue
            if how == "queue":
                say("%s · lease wait ran out (exit %s)" % (label, code))
                self.show_tail(log)
                raise Fail(75, "the %s lease wait ran out before check %d/%d started (NAYO_LOCK_WAIT); "
                               "rerun later" % (b["class"], b["n"], n))
            if how == "nolease":
                say("%s · `nayo lock %s` failed before the check started (exit %s)" % (label, b["class"], code))
                self.show_tail(log)
                raise Fail(2, "check %d/%d: `nayo lock %s` failed before the check started" % (b["n"], n, b["class"]))
            if how == "timeout":
                say("%s · TIMED OUT after %ds; its process group was stopped" % (label, b["timeout"]))
                self.show_tail(log)
                raise Fail(124, "check %d/%d timed out (timeout=%d)" % (b["n"], n, b["timeout"]))
            say("%s · FAILED (exit %d, %ds) — last %d lines:" % (label, code, ran, TAIL))
            tail = self.show_tail(log)
            self.dependency_hints(tail)
            raise Fail(1, "check %d/%d failed (exit %d)" % (b["n"], n, code))

    def supervise(self, argv, env, log, marker, b, leased):
        """(exit code, ok | timeout | queue | nolease, seconds run) of one check in its own process group."""
        with open(log, "wb") as out:
            p = subprocess.Popen(argv, cwd=self.root if leased else self.tree, env=env, stdin=subprocess.DEVNULL,
                                 stdout=out, stderr=subprocess.STDOUT, start_new_session=True)
        self.child = (p, p.pid)
        self.save_owner(phase="check %d" % b["n"], pgid=p.pid, pgid_start=lstart_of(p.pid))
        started = None
        queue_limit = time.time() + self.a.lock_wait + 30
        while p.poll() is None:
            if started is None and os.path.exists(marker):
                started = time.time()
            now = time.time()
            if started is not None and now - started >= b["timeout"]:
                stop_group(p.pid, None, self.a.grace)
                self.reap()
                return None, "timeout", int(now - started)
            if started is None and now > queue_limit:
                stop_group(p.pid, None, self.a.grace)
                self.reap()
                return 75, "queue", 0
            time.sleep(0.05)
        if started is None and os.path.exists(marker):
            started = time.time()
        ran = int(time.time() - started) if started else 0
        left = group_members(p.pid)   # the check is over: whatever it left running in its group goes with it
        if left:
            stop_group(p.pid, None, self.a.grace)
            say("  (stopped %d process%s check %d left running)" % (len(left), "" if len(left) == 1 else "es", b["n"]))
        code = self.reap()
        if started is None and leased:
            return code, ("queue" if code == 75 else "nolease"), 0
        return code, "ok", ran

    def reap(self):
        if not self.child:
            return None
        p = self.child[0]
        p.wait()
        self.child = None
        self.save_owner(phase="between checks", pgid="", pgid_start="")
        rc = p.returncode
        return 128 - rc if rc < 0 else rc

    def show_tail(self, log):
        try:
            with open(log, "rb") as f:
                lines = f.read().decode("utf-8", "replace").splitlines()
        except OSError:
            lines = []
        tail = lines[-TAIL:]
        for line in tail:
            say("    " + line[:400])
        say("  full log: %s" % os.path.relpath(log, self.root))
        return "\n".join(tail)

    def dependency_hints(self, tail):
        hints = [p for p in self.unlisted[:200] if p in tail and not os.path.lexists(os.path.join(self.tree, p))]
        for p in hints[:12]:
            say("  possible dependency on an unlisted file: %s" % p)
        rest = [p for p in self.unlisted if p not in hints]
        if rest:
            say("  changed here but not listed (possible dependencies, not proven causes): %s%s"
                % (", ".join(rest[:12]), " …" if len(rest) > 12 else ""))

    # ---- after the checks

    def recheck(self):
        moved = []
        if git(self.root, "rev-parse", "--verify", "-q", "HEAD^{commit}", ok=(0, 1)).stdout.decode().strip() != self.head:
            moved.append("HEAD")

        def digest(base, rel):
            full = os.path.join(base, rel)
            try:
                if os.path.islink(full):
                    return sha(os.fsencode(os.readlink(full)))
                with open(full, "rb") as f:
                    return sha(f.read())
            except OSError:
                return None
        moved += [s["path"] for s in self.snaps if digest(self.src, s["path"]) != s["sha"]]
        moved += [q for q, act in self.entries if act == "deleted" and os.path.lexists(os.path.join(self.src, q))]
        moved += [q for q, h in self.copies.items() if digest(self.src, q) != h]
        if digest(self.root, self.brief_rel) != sha(self.bbytes):
            moved.append(self.brief_rel)
        if digest(self.root, self.handoff_rel) != sha(self.hbytes):
            moved.append(self.handoff_rel)
        if moved:
            raise Fail(75, "inputs changed during verification; rerun (%s)" % ", ".join(moved[:8]))

    # ---- cleanup: the one path out

    def cleanup(self):
        if self.cleaned:
            return True
        self.quiet_signals()
        if self.child:
            stop_group(self.child[1], None, self.a.grace)
            self.reap()
        ok = remove_attempt(self.root, self.attempt, self.tree) if self.attempt else True
        self.cleaned = True
        self.end_watchdog()
        try:
            os.rmdir(os.path.join(self.state, "verify"))   # only when no other attempt is there
        except OSError:
            pass
        return ok


def ago(s):
    s = int(s)
    return "%ds" % s if s < 60 else "%dm" % (s // 60) if s < 3600 else "%dh%02dm" % (s // 3600, s % 3600 // 60)


def main():
    ap = argparse.ArgumentParser(prog="nayo-verify.py")
    ap.add_argument("--root", required=True)
    ap.add_argument("--handoff", required=True)
    ap.add_argument("--runner", required=True)
    ap.add_argument("--bash", required=True)
    ap.add_argument("--source", default="")
    ap.add_argument("--base", default="")
    ap.add_argument("--max-sec", type=int, default=7200)
    ap.add_argument("--lock-wait", type=int, default=3600)
    ap.add_argument("--grace", type=int, default=10)
    ap.add_argument("--reuse", choices=["0", "1"], default="0")
    ap.add_argument("--max-age", type=int, default=7200)
    ap.add_argument("--reuse-env", default="")
    a = ap.parse_args()
    if bool(a.source) != bool(a.base):
        ap.error("--source and --base go together")
    v = Verify(a)
    for s in SIGCODE:
        signal.signal(s, v.on_signal)
    code, msg = 0, ""
    try:
        v.preflight()
        v.take_lease()
        v.start()
        v.materialize()
        v.requires()
        say("verify: HEAD %s · %d listed change%s · %d input%s%s" % (
            v.head[:7], len(v.entries), "" if len(v.entries) == 1 else "s",
            len(v.inputs["copy"]) + len(v.inputs["requires"]),
            "" if len(v.inputs["copy"]) + len(v.inputs["requires"]) == 1 else "s",
            " · changes from %s" % a.source if a.source else ""))
        if a.reuse == "1":
            v.reused, why = v.find_pass()
            if not v.reused:
                say("verify: not reusing: %s; running the checks" % why)
        if not v.reused:
            v.run_checks()
        v.recheck()
    except Fail as e:
        code, msg = e.code, e.msg
    except Interrupted:
        code = SIGCODE.get(v.sig, 130)
        msg = "interrupted (%s); the check's processes were stopped" % signal.Signals(v.sig).name
    except Exception as e:  # a bug or an OS error: still clean up
        code, msg = 2, "verification error: %s: %s" % (type(e).__name__, e)
    clean = v.cleanup()
    if v.sig is not None and code not in SIGCODE.values():
        code = SIGCODE.get(v.sig, 130)
        msg = "interrupted (%s) during cleanup" % signal.Signals(v.sig).name
    if not clean:
        say("verify: cleanup FAILED; left behind: %s" % os.path.relpath(v.attempt, v.root))
        if code in (0, 1, 75, 124):
            code, msg = 2, msg or "cleanup failed"
    status = {0: "passed", 1: "failed", 124: "timeout", 75: "error"}.get(
        code, "interrupted" if code in SIGCODE.values() else "error")
    reused = v.reused if code == 0 else None
    if v.results and os.path.isdir(v.results):
        extra = {"reused_from": reused[0]} if reused else {}
        v.save_result(status="reused" if reused else status, exit=code, finished=int(time.time()),
                      cleanup="ok" if clean else "failed", message=msg.split("\n")[0], **extra)
    where = (" · " + v.results_rel) if v.results else ""
    if reused:
        orig, r = reused
        say("verify: reused pass from %s (%s ago) · tree %s · %s" % (
            time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(int(r["finished"]))),
            ago(time.time() - int(r["finished"])), v.tree_id[:7], os.path.join(STATE_DIR, "verify-results", orig)))
        say("  not re-run: HEAD, the listed changes, the brief, inputs, runner and environment are the same as "
            "that pass's; run without --reuse to run the checks again")
    elif code == 0:
        say("verify: passed %d/%d checks at HEAD %s · tree %s · isolated listed changes%s" % (
            len(v.blocks), len(v.blocks), v.head[:7], v.tree_id[:7], where))
        say("  ## Checks prose outside the verify blocks isn't run: that review is still yours")
    else:
        print("verify: %s%s" % (msg, where), file=sys.stdout if code in (1, 124, 75) else sys.stderr, flush=True)
    if code == 0 and getattr(v, "status", "") == "partial":
        say("  the handoff says partial: checked, not done")
    sys.exit(code)


if __name__ == "__main__":
    main()
