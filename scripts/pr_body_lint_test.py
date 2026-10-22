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
        # Use the canonical merged PR body instead of a duplicate historical fixture.
        self.assertEqual(run((HERE.parent / "CHANGELOG/2026.275.0418.md").read_text()), [])


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

    def test_sweep_claim_needs_its_backing_in_its_own_bullet(self):
        """opencharly/marketplace#493 — the class-6 arm's `backed_later` accepted ANY later fence.

        A sweep claim asserts an EXHAUSTIVE SEARCH, so only a command can support it, and the
        command belongs to the bullet asserting it. Measured against four consecutive successful
        daily corpus refreshes: a claim in a `## Rulebook compliance` bullet was exempted by an
        unrelated fence further down the section, so the same claim fired in `## Summary` and
        passed one section later.
        """
        sweep = "R5 was swept by grep over the org, and only older copies retain it."
        # In a Rules bullet, with an UNRELATED fence later in the same section: must STILL fire.
        # The bullet AFTER the claim matters: a fence belongs to the bullet it follows, so the
        # unrelated fence must sit under a LATER bullet for the claim above it to be unbacked.
        unrelated = OK_RULES + (
            "\n- **R5:** " + sweep
            + "\n- **R7:** answered with how."
            + "\n\n```\n$ gh pr list\n#1\n```"
        )
        self.assertTrue(
            any(x.startswith("claims:") for x in run(body(rules=unrelated))),
            "a sweep claim backed only by a fence under a LATER bullet must be flagged",
        )
        # The same claim with its command INSIDE its own bullet: must NOT fire.
        own = OK_RULES + "\n- **R5:** " + sweep + "\n\n```\n$ rg -n 'x' .\n```" + "\n- **R8:** answered with how."
        self.assertEqual(run(body(rules=own)), [])
        # An ordinary rule assertion keeps the section-wide rule: a later fence still backs it.
        self.assertEqual(
            run(body(rules=OK_RULES + "\n- **R6:** `git status` was checked first.\n\n```\n$ git status\n```")),
            [],
        )

    def test_no_match_grep_claim_requires_pasted_command_and_exit_status(self):
        claim = "The claim-keyed legacy-command grep has no matches."
        self.assertTrue(any("no-match grep/rg claim" in x for x in run(body(how=claim))))
        self.assertTrue(any(
            "no-match grep/rg claim" in x
            for x in run(body(how=claim + "\n\n```\n$ rg -n old README.md\n(no matches)\n```"))
        ))
        proof = claim + "\n\n```\n$ rg -n old README.md\nrg exit=1 (no matches)\n```"
        self.assertEqual(run(body(how=proof)), [])
        self.assertTrue(any("no-match grep/rg claim" in x for x in run(body(how=claim + " (output above)."))))

    def test_ellipsis_in_fence_fails(self):
        self.assertTrue(any(x.startswith("ellipsis:") for x in run(body(how="```\n$ cmd\nline … cut\n```"))))

    def test_body_must_not_contradict_itself_about_a_file(self):
        """opencharly/marketplace#526, round 2 — the body-only BLOCK the linter could not see.

        The Summary said the `strict-policy` skill "c[arries] the new grammar" while the
        body's own detail paragraph said that file "touches no coordination label". Every
        other check here passed that body: the structure was right, the claims were backed,
        and each statement was TRUE of the file on its own. Only a comparison of the two
        finds it — and the comparison is mechanical.
        """
        f = run((DATA / "blocked-marketplace-526.md").read_text())
        self.assertTrue(any(x.startswith("files:") and "strict-policy" in x for x in f), f)

    def test_one_way_claims_about_a_file_pass(self):
        text = body(how="The `internals/skills/cutover-policy/SKILL.md` file carries the new grammar.")
        self.assertEqual(run(text), [])

    def test_a_claim_about_something_else_is_not_comparable(self):
        """A claim about a DIFFERENT proposition is not a claim about the change."""
        text = body(how="The `internals/skills/cutover-policy/SKILL.md` file carries authoring prose.")
        self.assertEqual(run(text), [])

    def test_narration_of_a_past_state_is_not_a_claim(self):
        """The Summary LISTED the file among the grammar-bearing ones — that is about the
        Summary, not about the file, and a generic subject says so."""
        text = body(
            how="The Summary listed the `internals/skills/cutover-policy/SKILL.md` file among "
            "the files that carry the new grammar."
        )
        self.assertEqual(run(text), [])

    def test_body_must_not_contradict_the_count_table_it_carries(self):
        """opencharly/marketplace#526, round 3 — the body-only BLOCK, one class further on.

        The Summary said "Two of those hunks are carried prose" and named two of the three
        generated projections that carry none; the third was never named. Nothing in the body
        contradicted ITSELF — the `files` rule is clean on it — and every count was TRUE of
        the two files it named. A count that disagrees with the body's own classification
        table is the same defect one step further, and it is mechanical.
        """
        f = run((DATA / "blocked-marketplace-526-counts.md").read_text())
        self.assertTrue(any(x.startswith("counts:") and "prose" in x for x in f), f)

    def test_a_count_that_matches_its_table_passes(self):
        text = (DATA / "blocked-marketplace-526-counts.md").read_text()
        fixed = text.replace("Two of those hunks", "Three of those hunks")
        self.assertEqual([x for x in run(fixed) if x.startswith("counts:")], [])

    def test_a_count_that_does_not_govern_the_class_word_is_not_comparable(self):
        """A number that FOLLOWS a class word quantifies something else: "the coordination
        grammar's closed set is nine labels" counts labels, not grammars."""
        text = body(how="The coordination grammar's closed set is nine labels.")
        self.assertEqual(run(text), [])
        with_table = body(
            how="The coordination grammar's closed set is nine labels.\n\n"
            "```\ngrammar  internals/skills/cutover-policy/SKILL.md\n"
            "grammar  internals/skills/git-workflow/SKILL.md\n```"
        )
        self.assertEqual([x for x in run(with_table) if x.startswith("counts:")], [])

    def test_a_narrated_count_is_not_an_asserted_one(self):
        """A body that narrates its own history quotes a count; it does not assert one."""
        text = body(
            how="The Summary said 'Two of those hunks are carried prose' and named two of them.\n\n"
            "```\ngrammar  internals/skills/cutover-policy/SKILL.md\n"
            "grammar  internals/skills/git-workflow/SKILL.md\n"
            "prose    internals/skills/skills/SKILL.md\n```"
        )
        self.assertEqual([x for x in run(text) if x.startswith("counts:")], [])

    def test_merged_bodies_stay_clean(self):
        """The rule must not fire on bodies that were MERGED — a noisy lint teaches authors
        to ignore it. Calibrated against 944 merged bodies (the org's CHANGELOG entries),
        zero findings. Only THESE rules are asserted here: an older body may miss another
        check (an unanswered rule, an older footer grammar) and still be a valid body."""
        logs = sorted((HERE.parent / "CHANGELOG").glob("*.md"))[-25:]
        self.assertTrue(logs)
        for lg in logs:
            fired = [x for x in run(lg.read_text()) if x.startswith(("files:", "counts:"))]
            self.assertEqual(fired, [], f"{lg.name} must not trip the files or counts rule")

    def test_head_mismatch_fails(self):
        sha = "a" * 40
        text = body(how=f"Head `{sha}`")
        self.assertEqual(run(text, head=sha), [])
        self.assertTrue(any(x.startswith("head:") for x in run(text, head="b" * 40)))


if __name__ == "__main__":
    unittest.main(verbosity=2)
