#!/usr/bin/env python3
"""pr_takeover_watch.py — a generic PR coordination watcher.

Watch an arbitrary set of pull requests and notify when any of the events a formal
cross-session takeover depends on happens:

  * a new **comment** after a claim (a reviewer, another agent, or a bot),
  * a **state** change (the PR is merged or closed),
  * a **check verdict** change (the required-check rollup moves),
  * the end of an **ownership window** ("ended notification timer").

Nothing here is specific to a repository, an organisation, an agent harness, a
session, or a login: every input is passed on the command line / in the targets
file. It is the sanctioned alternative to a hand-rolled `while`/`sleep` polling
loop (R4) for the cross-session coordination protocol.

A "claim" is anchored to a COMMENT (the GitHub comment id that started the formal
takeover procedure — an ownership-board `STATUS`/`BLOCKS` comment). The window is
measured from that comment's `created_at`; the default is 3600 s (the coordination
protocol's 60-minute floor).

Targets file (TSV, one claim per line; blank lines and `#` comments ignored):

    <owner>/<repo>\t<pr-number>\t<claim-comment-id>\t<label>

`<claim-comment-id>` is the numeric id of a GitHub issue/PR comment. `<label>` is
any opaque string used to identify the target in events (e.g. `acme/widget#12`).

Modes
-----

    (default)            poll until interrupted, appending each event
    --once               a single pass (seed state / smoke test)
    --next TIMEOUT       block until the events file grows past its current size,
                         print the new event and exit 0; exit 4 on timeout. A cheap
                         local-file poll (no GitHub calls) so a parent process can
                         be woken by ONE bounded call.

Events are appended as JSONL to `--events` and as a human line to `--log`.
Notification on every event is best-effort and opt-in:

    --bell --tty <dev>   ring the terminal (e.g. /dev/pts/0) on each event
    --notify-cmd <cmd>   run <cmd> with the event line on stdin (webhook, desktop,
                         `notify-send`, …). Also read from $PR_WATCH_NOTIFY_CMD.

Exit codes: 0 ok · 4 --next timeout · 5 usage / fatal error.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import shlex
import subprocess
import sys
import time

DEFAULT_WINDOW = 3600  # seconds; the coordination protocol's 60-minute floor


def default_dir() -> str:
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return os.path.join(base, "pr-takeover-watch")


def sh(args):
    r = subprocess.run(args, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip() or f"command failed: {args}")
    return r.stdout


def gh_json(args):
    return json.loads(sh(["gh"] + args) or "{}")


def parse_iso(ts: str) -> float:
    """Parse a GitHub ISO-8601 timestamp to epoch seconds (0.0 for empty)."""
    return dt.datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp() if ts else 0.0


def now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def is_bot(login: str, extra_logins) -> bool:
    return login.endswith("[bot]") or login in extra_logins


def load_targets(path):
    out = []
    with open(path) as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line or line.lstrip().startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) != 4:
                raise SystemExit(f"bad targets line (want 4 tab-separated fields): {line!r}")
            repo, pr, cid, label = parts
            out.append({"repo": repo, "pr": pr, "cid": cid, "label": label})
    return out


class Watcher:
    def __init__(self, opts):
        self.o = opts
        self.state = self._load_state()

    def _load_state(self):
        if os.path.exists(self.o.state):
            try:
                with open(self.o.state) as fh:
                    return json.load(fh)
            except Exception:
                return {}
        return {}

    def _save_state(self):
        tmp = self.o.state + ".tmp"
        with open(tmp, "w") as fh:
            json.dump(self.state, fh, indent=2)
        os.replace(tmp, self.o.state)

    def notify(self, line):
        if self.o.bell and self.o.tty:
            try:
                with open(self.o.tty, "w") as t:
                    t.write("\a")
                    t.flush()
            except Exception:
                pass
        if self.o.notify_cmd:
            try:
                subprocess.run(shlex.split(self.o.notify_cmd), input=line, text=True, timeout=30)
            except Exception as e:
                print(f"[warn] notify-cmd failed: {e}", file=sys.stderr)

    def emit(self, rec):
        with open(self.o.events, "a") as fh:
            fh.write(json.dumps(rec) + "\n")
        line = f"{rec['ts'][:19]}  {rec['label']:<30} {rec['kind']:<16} {rec['detail']}"
        with open(self.o.log, "a") as fh:
            fh.write(line + "\n")
        print(line, flush=True)
        self.notify(line)

    def poll(self, target):
        key = target["label"]
        s = self.state.setdefault(key, {})
        repo, pr = target["repo"], target["pr"]
        if "claim_ts" not in s:
            s["claim_ts"] = gh_json(
                ["api", f"repos/{repo}/issues/comments/{target['cid']}"]).get("created_at", "")
        claim = parse_iso(s["claim_ts"])
        d = gh_json(["pr", "view", pr, "--repo", repo, "--json",
                     "state,mergeStateStatus,headRefOid,url,comments,statusCheckRollup"])
        url = d.get("url", f"https://github.com/{repo}/pull/{pr}")
        ts = now_iso()

        # 1. new comments after the claim (skip our own slug's coordination comments)
        for c in d.get("comments", []) or []:
            cid = str(c.get("id", ""))
            if parse_iso(c.get("createdAt", "")) <= claim:
                continue
            body = c.get("body", "") or ""
            if self.o.slug and self.o.slug in body:
                continue
            seen = s.setdefault("seen_comment_ids", [])
            if cid in seen:
                continue
            seen.append(cid)
            author = (c.get("author") or {}).get("login", "?")
            kind = "bot-comment" if is_bot(author, self.o.validator_logins) else "comment"
            self.emit({"ts": ts, "label": key, "kind": kind, "author": author,
                       "detail": " ".join(body.split())[:180], "url": url, "comment_id": cid})

        # 2. PR state
        if s.get("last_state") not in (None, d.get("state")):
            self.emit({"ts": ts, "label": key, "kind": "state",
                       "detail": f"state {s.get('last_state')} -> {d.get('state')}", "url": url})
        s["last_state"] = d.get("state")

        # 3. required-check rollup
        sig = ";".join(sorted(f"{c.get('name')}={c.get('conclusion') or c.get('status')}"
                              for c in (d.get("statusCheckRollup") or [])))
        if s.get("last_checks") not in (None, sig):
            self.emit({"ts": ts, "label": key, "kind": "checks",
                       "detail": f"check rollup: {sig or 'none'}", "url": url})
        s["last_checks"] = sig

        # 4. the ownership window
        if claim and not s.get("timer_fired") and time.time() >= claim + self.o.window:
            replied = bool(s.get("seen_comment_ids"))
            s["timer_fired"] = True
            detail = ("ownership window expired; a comment was seen during it"
                      if replied else
                      "ownership window expired with NO comment -> eligible for TAKING OVER")
            self.emit({"ts": ts, "label": key, "kind": "window-expired",
                       "detail": detail, "url": url})

    def run(self, interval, once):
        while True:
            for t in load_targets(self.o.targets):
                try:
                    self.poll(t)
                except Exception as e:
                    print(f"[warn] {t.get('label')}: {e}", file=sys.stderr)
            self._save_state()
            if once:
                return 0
            time.sleep(interval)


def mode_next(events_path, timeout):
    os.makedirs(os.path.dirname(events_path) or ".", exist_ok=True)
    open(events_path, "a").close()
    start = os.path.getsize(events_path)
    end = time.time() + timeout
    while True:
        if os.path.getsize(events_path) > start:
            with open(events_path) as fh:
                fh.seek(start)
                print(fh.readline().strip())
            return 0
        if time.time() >= end:
            print("PR_WATCH_TIMEOUT: no new events", file=sys.stderr)
            return 4
        time.sleep(5)


def main(argv=None):
    d = default_dir()
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--targets", help="TSV file of claims (required except with --next)")
    p.add_argument("--dir", default=d, help=f"state directory (default {d})")
    p.add_argument("--events", help="events JSONL path (default <dir>/events.jsonl)")
    p.add_argument("--log", help="human log path (default <dir>/events.log)")
    p.add_argument("--state", help="state JSON path (default <dir>/state.json)")
    p.add_argument("--slug", default="", help="this session's agent slug; its own comments are ignored")
    p.add_argument("--window", type=int, default=DEFAULT_WINDOW,
                   help=f"ownership window seconds (default {DEFAULT_WINDOW})")
    p.add_argument("--interval", type=int, default=60, help="poll interval seconds (default 60)")
    p.add_argument("--bell", action="store_true", help="ring --tty on each event")
    p.add_argument("--tty", default="", help="terminal device for --bell (e.g. /dev/pts/0)")
    p.add_argument("--notify-cmd", default=os.environ.get("PR_WATCH_NOTIFY_CMD", ""),
                   help="command run with the event line on stdin (also $PR_WATCH_NOTIFY_CMD)")
    p.add_argument("--validator-logins", default="",
                   help="extra comma-separated bot logins to classify as bot-comment")
    p.add_argument("--once", action="store_true")
    p.add_argument("--next", type=int, metavar="TIMEOUT", default=None,
                   help="block until the next new event, then exit (seconds)")
    o = p.parse_args(argv)

    o.events = o.events or os.path.join(o.dir, "events.jsonl")
    o.log = o.log or os.path.join(o.dir, "events.log")
    o.state = o.state or os.path.join(o.dir, "state.json")
    o.validator_logins = {x.strip() for x in o.validator_logins.split(",") if x.strip()}

    for path in (o.events, o.log):
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        open(path, "a").close()

    if o.next is not None:
        return mode_next(o.events, o.next)
    if not o.targets:
        p.error("--targets is required")
    return Watcher(o).run(o.interval, o.once)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
