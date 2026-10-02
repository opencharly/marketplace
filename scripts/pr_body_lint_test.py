#!/usr/bin/env python3
"""Regression tests for pr_body_lint.py (opencharly/marketplace#404).

The two `blocked-*` fixtures are the REAL first-push bodies of PRs the charly/pr-validator
BLOCKed on the body alone (recovered from GitHub's userContentEdits history); each must fail on
the finding the validator named. `clean-*` is a body the validator PASSed and must lint clean.
Run: python3 scripts/pr_body_lint_test.py
"""

import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from pr_body_lint import DEFAULT_RULES, lint  # noqa: E402

DATA = HERE / "testdata" / "pr_body_lint"
FOOTER = "*Assisted-by: Claude Code Anthropic Claude Opus 5.5 (documentation reviewed)*"
OK_RULES = "\n".join(f"- **{r}:** answered with how." for r in DEFAULT_RULES)


def body(how="x", rules=OK_RULES, footer=FOOTER):
    return f"## Summary\nx\n## How tested\n{how}\n## Rulebook compliance\n{rules}\n## Change classification\nx\n\n{footer}\n"


def run(text, head=None):
    return lint(text, head, DEFAULT_RULES)


class Fixtures(unittest.TestCase):
    def test_distro_fedora_79_only_occurrence_claim(self):
        f = run((DATA / "blocked-distro-fedora-79.md").read_text())
        self.assertTrue(any("only occurrence" in x for x in f), f)

    def test_docs_142_asserted_check_and_missing_rules(self):
        f = run((DATA / "blocked-docs-142.md").read_text())
        self.assertTrue(any("were checked" in x for x in f), f)
        self.assertTrue(any("does not answer R1" in x for x in f), f)

    def test_clean_body_passes(self):
        self.assertEqual(run((DATA / "clean-marketplace-405.md").read_text()), [])


class Rules(unittest.TestCase):
    def test_minimal_valid_body_is_clean(self):
        self.assertEqual(run(body()), [])

    def test_missing_section(self):
        self.assertTrue(any("missing `## How tested`" in x for x in run(body().replace("## How tested\n", ""))))

    def test_footer_must_be_last(self):
        self.assertTrue(any(x.startswith("footer:") for x in run(body() + "trailing prose\n")))

    def test_agent_line_must_precede_trailer(self):
        f = run(body(footer="*Agent: `s` · session `x`*\n\nprose\n" + FOOTER))
        self.assertTrue(any("`Agent:` line" in x for x in f), f)

    def test_bare_na_fails_reasoned_na_passes(self):
        self.assertTrue(any("bare N/A" in x for x in run(body(rules=OK_RULES.replace("R9:** answered with how.", "R9:** N/A")))))
        self.assertEqual(run(body(rules=OK_RULES.replace("R9:** answered with how.", "R9:** N/A — no binary"))), [])

    def test_unbacked_claim_fails_backed_or_pointed_passes(self):
        claim = "The open PRs were checked."
        self.assertTrue(any(x.startswith("claims:") for x in run(body(how=claim))))
        self.assertEqual(run(body(how=claim + "\n\n```\n$ gh pr list\n#1\n```")), [])
        self.assertEqual(run(body(how="The open PRs were checked (output above).")), [])

    def test_ellipsis_in_fence_fails(self):
        self.assertTrue(any(x.startswith("ellipsis:") for x in run(body(how="```\n$ cmd\nline … cut\n```"))))

    def test_head_mismatch_fails(self):
        sha = "a" * 40
        text = body(how=f"Head `{sha}`")
        self.assertEqual(run(text, head=sha), [])
        self.assertTrue(any(x.startswith("head:") for x in run(text, head="b" * 40)))


if __name__ == "__main__":
    unittest.main(verbosity=2)
