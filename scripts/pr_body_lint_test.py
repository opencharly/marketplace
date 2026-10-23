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
AGENT = "*Agent: containerd-crabbox-program/w10 · session 8b1c01cf-7f79-4a75-bff8-240415a06208*"
OK_RULES = "\n".join(f"- **{r}:** answered with how." for r in DEFAULT_RULES)


def body(how="x", rules=OK_RULES, footer=FOOTER):
    return f"## Summary\nx\n## How tested\n{how}\n## Rulebook compliance\n{rules}\n## Change classification\nx\n\n{footer}\n"


def run(text, head=None, diffstat=None):
    return lint(text, head, DEFAULT_RULES, diffstat)


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

    def test_body_without_footer_is_clean(self):
        # Coverage arm 1: the footer is OPTIONAL for a human body — no `Agent:` line, no trailer,
        # passes.
        self.assertEqual(run(body(footer="")), [])
        # ...and an unrelated italic line is not a trailer, so it does not have to be last.
        self.assertEqual(run(body(footer="*Note: no attribution here*")), [])

    def test_footer_last_is_clean(self):
        # Coverage arm 2: a human body whose footer IS present and sits last passes.
        self.assertEqual(run(body()), [])

    def test_agent_body_requires_the_trailer(self):
        # Coverage arm 3 (the new rule): the `Agent:` line marks an agent-authored body, so the
        # Assisted-by trailer is REQUIRED even though it is optional for a human body.
        f = run(body(footer=AGENT))
        self.assertTrue(any("must end with the italic Assisted-by trailer" in x for x in f), f)
        # ...even with prose after the marker, and in the plain (non-emphasis) form.
        f = run(body(footer=AGENT + "\n\ntrailing prose"))
        self.assertTrue(any("must end with the italic Assisted-by trailer" in x for x in f), f)
        f = run(body(footer="Agent: containerd-crabbox-program/w10"))
        self.assertTrue(any("must end with the italic Assisted-by trailer" in x for x in f), f)

    def test_agent_body_with_trailer_last_is_clean(self):
        # Coverage arm 4: the correct agent form — `Agent:` then the trailer as the last line.
        self.assertEqual(run(body(footer=AGENT + "\n" + FOOTER)), [])
        self.assertEqual(run(body(footer="Agent: containerd-crabbox-program/w10\n" + FOOTER)), [])

    def test_agent_body_with_trailer_not_last_fails(self):
        # Coverage arm 5: the agent body's trailer must be LAST, not merely present.
        f = run(body(footer=AGENT + "\n" + FOOTER + "\ntrailing prose\n"))
        self.assertTrue(any("the last line must be the italic Assisted-by trailer" in x for x in f), f)

    def test_missing_section(self):
        self.assertTrue(any("missing `## How tested`" in x for x in run(body().replace("## How tested\n", ""))))

    def test_footer_must_be_last(self):
        # The unchanged control (#531): a HUMAN body's trailer that is present but not last still
        # FAILS, so making the trailer optional did not remove the never-buried rule.
        self.assertTrue(any(x.startswith("footer:") for x in run(body() + "trailing prose\n")))
        # A second trailer cannot hide earlier in the body beside a final one either.
        self.assertTrue(
            any(x.startswith("footer:") for x in run(body(footer=FOOTER + "\n\nprose\n\n" + FOOTER)))
        )

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

    def test_a_negative_claim_written_as_none_is_a_negative_claim(self):
        """opencharly/marketplace#526, round 4 — the validator's non-blocking observation.

        The negation vocabulary decided the polarity, and `none`/`nothing` were missing from
        it: "X carries none of the new grammar" was read as a POSITIVE claim, so a body that
        said that in one paragraph and "X does not carry the new grammar" in another was read
        as claiming BOTH — and the rule fired on a body that was telling the truth. A lint
        that cries wolf on a true body teaches authors to ignore it.
        """
        f = "The `internals/skills/cutover-policy/SKILL.md` file carries none of the new grammar."
        self.assertEqual(run(body(how=f)), [])
        both_negative = body(how=f + "\n\n" + f.replace("carries none", "does not carry"))
        self.assertEqual([x for x in run(both_negative) if x.startswith("files:")], [])
        contradiction = body(
            how="The `internals/skills/cutover-policy/SKILL.md` file carries the new grammar."
            "\n\nThe `internals/skills/cutover-policy/SKILL.md` file does not carry the new grammar."
        )
        self.assertTrue(any(x.startswith("files:") for x in run(contradiction)))

    def test_the_negation_vocabulary_is_one_list_read_in_both_positions(self):
        """R2 — the words that decide a claim's polarity are ONE list, read before the
        predicate and immediately after it.

        The two positions differ in WHERE they look, not in WHICH words they recognise. A
        second, narrower copy of the list is how the two drift apart, and the drift is the
        defect this change was written for: "carries none of the new grammar" was read as a
        positive claim while "does not carry the new grammar" was read as a negative one.
        """
        from pr_body_lint import NEGATION, NEGATION_LEAD

        for word in (
            "no", "not", "neither", "nor", "zero", "without", "never", "lack", "lacks",
            "none", "nothing",
        ):
            self.assertTrue(NEGATION.search(f"the file {word} the grammar"), word)
            self.assertTrue(NEGATION_LEAD.match(f" {word} the grammar"), word)

    def test_a_negative_claim_about_a_different_object_is_not_comparable(self):
        """A negation does not make a claim about a DIFFERENT object comparable.

        The `files` rule compares a body's two statements about one FILE. It compares the
        CLAIMS, and a claim is comparable only when its object names THE CHANGE: "X
        carries the new grammar" and "X carries none of the old grammar" are two statements
        about one file, but only the first names the change, so the second is not a claim
        about it and the pair is not a contradiction. The whole-corpus calibration is the
        evidence that the boundary holds; this test pins the boundary itself, so widening
        the change-object vocabulary would turn it RED.
        """
        both = body(
            how="The `internals/skills/cutover-policy/SKILL.md` file carries the new grammar."
            "\n\nThe `internals/skills/cutover-policy/SKILL.md` file carries none of the old grammar."
        )
        self.assertEqual([x for x in run(both) if x.startswith("files:")], [])

    def test_merged_bodies_stay_clean(self):
        """The rule must not fire on bodies that were MERGED — a noisy lint teaches authors
        to ignore it. Calibrated against EVERY merged body this repo carries in its own
        CHANGELOG (each entry is the body of a merged PR, written at merge time), zero
        findings; the wider 944-body run across the five repos of the coordination cutover
        is the same calibration over the whole cutover, and it is pasted in that PR's body.
        Only THESE rules are asserted here: an older body may miss another check (an
        unanswered rule, an older footer grammar) and still be a valid body."""
        logs = sorted((HERE.parent / "CHANGELOG").glob("2026.*.md"))
        self.assertTrue(logs)
        self.assertGreaterEqual(len(logs), 400, "the corpus this rule is calibrated against shrank")
        for lg in logs:
            fired = [x for x in run(lg.read_text()) if x.startswith(("files:", "counts:"))]
            self.assertEqual(fired, [], f"{lg.name} must not trip the files or counts rule")

    def test_head_mismatch_fails(self):
        sha = "a" * 40
        text = body(how=f"Head `{sha}`")
        self.assertEqual(run(text, head=sha), [])
        self.assertTrue(any(x.startswith("head:") for x in run(text, head="b" * 40)))


class Diffstat(unittest.TestCase):
    """opencharly/marketplace#548, round 2 — the body's own headline count of the diff.

    The body said "2 files, +33 −8" and the diff was "2 files, +32 −5". Nothing else in
    that body was wrong: the sections were there, the claims were backed, the head was
    right, and every number the body pasted was true. Only the headline's own number was
    false, and the validator BLOCKed on it — a body-only BLOCK, which the linter's own
    docstring calls an ORCHESTRATOR VALIDATION FAILURE: a verdict spent on something a
    deterministic check could have caught.
    """

    DIFF = (2, 32, 5)          # files, insertions, deletions
    SHA = "a" * 40

    def headline(self, stat, extra=""):
        return body(how=f"Head `{self.SHA}`, {stat}{extra}")

    def findings(self, text):
        return [x for x in run(text, self.SHA, self.DIFF) if x.startswith("diffstat:")]

    def test_a_headline_diffstat_that_matches_the_diff_passes(self):
        self.assertEqual(self.findings(self.headline("**2 files, +32 −5**")), [])

    def test_a_headline_diffstat_that_does_not_match_the_diff_fails(self):
        f = self.findings(self.headline("**2 files, +33 −8**"))
        self.assertTrue(f, "a headline that contradicts the diff must be reported")
        self.assertIn("+32 -5", f[0])

    def test_gits_own_shape_is_checked_too(self):
        """The house writes the diffstat two ways; the rule must read both."""
        self.assertTrue(self.findings(self.headline("2 files changed, 33 insertions(+), 8 deletions(-)")))
        self.assertEqual(self.findings(self.headline("2 files changed, 32 insertions(+), 5 deletions(-)")), [])

    def test_a_file_count_that_is_right_but_the_line_counts_are_wrong_fails(self):
        self.assertTrue(self.findings(self.headline("**2 files, +32 −8**")))
        self.assertTrue(self.findings(self.headline("**3 files, +32 −5**")))

    def test_a_diffstat_about_another_diff_is_not_judged(self):
        """A diffstat in ANOTHER paragraph may be about a different diff — an upstream PR, a
        predecessor this PR supersedes. Judging it would cry wolf on a true body."""
        text = self.headline("**2 files, +32 −5**", extra="\n\nThe upstream PR carried 3 files, +40 −10.")
        self.assertEqual(self.findings(text), [])

    def test_a_diffstat_in_a_fence_is_pasted_evidence_not_a_claim(self):
        text = self.headline(
            "**2 files, +32 −5**",
            extra="\n```\n$ git diff --shortstat\n 2 files changed, 30 insertions(+), 5 deletions(-)\n```",
        )
        self.assertEqual(self.findings(text), [])

    def test_a_body_without_a_head_is_not_judged(self):
        """The headline is the anchor; a body that states no head states no claim to check."""
        self.assertEqual([x for x in run(body(how="**2 files, +33 −8**"), None, self.DIFF) if x.startswith("diffstat:")], [])

    def test_an_unreadable_diff_skips_visibly_rather_than_guessing(self):
        """`diffstat=None` means the diff could not be read: the rule must not fire."""
        self.assertEqual([x for x in run(self.headline("**2 files, +33 −8**"), self.SHA, None) if x.startswith("diffstat:")], [])


class DiffTotals(unittest.TestCase):
    """The diffstat rule's own truth: the diff, read with git."""

    def repo(self):
        import subprocess
        import tempfile

        tmp = tempfile.mkdtemp(prefix="pr-body-lint-")
        run = lambda *a: subprocess.run(["git", "-C", tmp, *a], check=True, capture_output=True, text=True)
        run("init", "-q", "-b", "main")
        run("config", "user.email", "linter@example.invalid")
        run("config", "user.name", "linter")
        Path(tmp, "a.txt").write_text("one\ntwo\n")
        run("add", "-A")
        run("commit", "-qm", "first")
        base = run("rev-parse", "HEAD").stdout.strip()
        Path(tmp, "a.txt").write_text("one\nthree\n")
        Path(tmp, "b.txt").write_text("new\n")
        run("add", "-A")
        run("commit", "-qm", "second")
        head = run("rev-parse", "HEAD").stdout.strip()
        return Path(tmp), base, head

    def test_the_totals_are_the_diff_own_numbers(self):
        from pr_body_lint import diff_totals

        tmp, base, head = self.repo()
        self.assertEqual(diff_totals(tmp, base, head), (2, 2, 1))

    def test_an_unresolvable_base_reads_as_no_totals(self):
        """None, not a guess: the rule skips, visibly, rather than judging against a fiction."""
        from pr_body_lint import diff_totals

        tmp, _base, head = self.repo()
        self.assertIsNone(diff_totals(tmp, "no-such-ref", head))
        self.assertIsNone(diff_totals(Path("/nonexistent-repo"), "main", head))


if __name__ == "__main__":
    unittest.main(verbosity=2)
