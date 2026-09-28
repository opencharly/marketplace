#!/usr/bin/env python3
"""Offline unit tests for pr_takeover_watch.py.

Run:  python3 scripts/pr_takeover_watch_test.py

No network and no `gh`: the watcher's `gh_json` seam is monkeypatched with fixtures,
so the tests exercise the real event/dedupe/window logic deterministically.
"""
import argparse
import datetime as dt
import json
import os
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pr_takeover_watch as w  # noqa: E402


def iso(epoch):
    return dt.datetime.fromtimestamp(epoch, dt.timezone.utc).isoformat().replace("+00:00", "Z")


class FakeGh:
    def __init__(self, claim_epoch, pr):
        self.claim_epoch = claim_epoch
        self.pr = pr

    def __call__(self, args):
        if args[:2] == ["api", "repos/x/y/issues/comments/1"]:
            return {"created_at": iso(self.claim_epoch)}
        if args[:2] == ["pr", "view"]:
            return self.pr
        raise AssertionError(f"unexpected gh call: {args}")


class TmpWatcher:
    def __init__(self, claim_epoch, pr, window=3600, slug="myslug", validator_logins=()):
        self.dir = tempfile.mkdtemp(prefix="ptw-")
        targets = os.path.join(self.dir, "targets.tsv")
        with open(targets, "w") as fh:
            fh.write("x/y\t7\t1\tx/y#7\n")
        self.opts = argparse.Namespace(
            targets=targets,
            events=os.path.join(self.dir, "events.jsonl"),
            log=os.path.join(self.dir, "events.log"),
            state=os.path.join(self.dir, "state.json"),
            slug=slug, window=window, interval=1,
            bell=False, tty=os.path.join(self.dir, "tty"), notify_cmd="",
            validator_logins=set(validator_logins),
        )
        for path in (self.opts.events, self.opts.log):
            open(path, "a").close()
        self.gh = FakeGh(claim_epoch, pr)
        self._orig = w.gh_json
        w.gh_json = self.gh
        self.w = w.Watcher(self.opts)

    def close(self):
        w.gh_json = self._orig

    def events(self):
        with open(self.opts.events) as fh:
            return [json.loads(x) for x in fh if x.strip()]


def pr(comments=(), state="OPEN", checks=()):
    return {"state": state, "url": "u", "comments": list(comments),
            "statusCheckRollup": [{"name": n, "conclusion": c} for n, c in checks]}


class TestTakeoverWatch(unittest.TestCase):
    def setUp(self):
        self.now = int(time.time())

    def comment(self, cid, epoch, body, login):
        return {"id": cid, "createdAt": iso(epoch), "body": body, "author": {"login": login}}

    def test_parse_iso(self):
        self.assertEqual(w.parse_iso("1970-01-01T00:01:00Z"), 60.0)
        self.assertEqual(w.parse_iso(""), 0.0)

    def test_is_bot(self):
        self.assertTrue(w.is_bot("dependabot[bot]", set()))
        self.assertTrue(w.is_bot("review-bot", {"review-bot"}))
        self.assertFalse(w.is_bot("alice", set()))

    def test_load_targets_and_bad_line(self):
        d = tempfile.mkdtemp()
        p = os.path.join(d, "t.tsv")
        with open(p, "w") as fh:
            fh.write("# c\nx/y\t7\t1\tlbl\n")
        self.assertEqual(w.load_targets(p)[0]["label"], "lbl")
        with open(p, "w") as fh:
            fh.write("only-one-field\n")
        with self.assertRaises(SystemExit):
            w.load_targets(p)

    def test_comment_detected_then_deduped(self):
        tw = TmpWatcher(self.now, pr(comments=[self.comment(2, self.now + 30, "OWNING — ETA 10m", "peer")]))
        try:
            t = {"repo": "x/y", "pr": "7", "cid": "1", "label": "x/y#7"}
            tw.w.poll(t)
            self.assertEqual([e["kind"] for e in tw.events()], ["comment"])
            tw.w.poll(t)  # same comment must not re-fire
            self.assertEqual(len(tw.events()), 1)
        finally:
            tw.close()

    def test_bot_comment_classified(self):
        tw = TmpWatcher(self.now, pr(comments=[self.comment(2, self.now + 30, "## Review — BLOCK", "github-actions[bot]")]))
        try:
            tw.w.poll({"repo": "x/y", "pr": "7", "cid": "1", "label": "x/y#7"})
            self.assertEqual([e["kind"] for e in tw.events()], ["bot-comment"])
        finally:
            tw.close()

    def test_own_slug_comment_ignored(self):
        tw = TmpWatcher(self.now, pr(comments=[self.comment(2, self.now + 30, "STATUS from myslug", "me")]))
        try:
            tw.w.poll({"repo": "x/y", "pr": "7", "cid": "1", "label": "x/y#7"})
            self.assertEqual(tw.events(), [])
        finally:
            tw.close()

    def test_window_expired_fires_once(self):
        tw = TmpWatcher(self.now - 10, pr(), window=0)
        try:
            t = {"repo": "x/y", "pr": "7", "cid": "1", "label": "x/y#7"}
            tw.w.poll(t)
            tw.w.poll(t)
            self.assertEqual([e["kind"] for e in tw.events()], ["window-expired"])
        finally:
            tw.close()

    def test_state_and_checks_change(self):
        tw = TmpWatcher(self.now, pr(state="OPEN", checks=[("validate / validate", "FAILURE")]))
        try:
            t = {"repo": "x/y", "pr": "7", "cid": "1", "label": "x/y#7"}
            tw.w.poll(t)  # seed baseline
            self.assertEqual(tw.events(), [])
            tw.gh.pr = pr(state="MERGED", checks=[("validate / validate", "SUCCESS")])
            tw.w.poll(t)
            kinds = [e["kind"] for e in tw.events()]
            self.assertIn("state", kinds)
            self.assertIn("checks", kinds)
        finally:
            tw.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
