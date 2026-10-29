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

# The bodies this repo merged BEFORE the `ellipsis` arm existed, and the elisions each
# one carries.  They are history — the arm cannot un-merge them — and the corpus is this
# rule's calibration, so they are NAMED here rather than silently tolerated.  Every one
# of the eighteen was read and judged an authorial elision (thirteen elided command
# lines, five dropped lines); none is a program's own token.
LEGACY_ELLIPSIS_BODIES = {
    "2026.241.0244.md": {"command": 1},
    "2026.241.0736.md": {"command": 4},
    "2026.241.1633.md": {"dropped": 1},
    "2026.241.1700.md": {"command": 1},
    "2026.241.1743.md": {"command": 1},
    "2026.241.1752.md": {"command": 2},
    "2026.243.0624.md": {"dropped": 1},
    "2026.269.1156.md": {"dropped": 1},
    "2026.270.0840.md": {"command": 1},
    "2026.277.2007.md": {"command": 1},
    "2026.279.0741.md": {"command": 1},
    "2026.290.1200.md": {"command": 1},
    "2026.297.0006.md": {"dropped": 2},
}


def body(how="x", rules=OK_RULES, footer=FOOTER, classification="x"):
    return f"## Summary\nx\n## How tested\n{how}\n## Rulebook compliance\n{rules}\n## Change classification\n{classification}\n\n{footer}\n"


def run(text, head=None, diffstat=None, subject=None):
    return lint(text, head, DEFAULT_RULES, diffstat, subject)


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

    def test_an_elided_command_line_fails(self):
        """The author's elision of the evidence the `claims` arm reads.

        A command line in a transcript is the author's own typing — a program never prints
        one — so a `…` there is the author shortening the very command the claim is
        backed by. This is the case opencharly/opencharly's own landed body carries
        (`$ git commit …`).
        """
        f = run(body(how="```\n$ git commit …\n```"))
        self.assertTrue(any(x.startswith("ellipsis:") and "command line" in x for x in f), f)

    def test_a_programs_own_token_is_allowed(self):
        """opencharly/marketplace#537 — the issue's own case, pasted VERBATIM.

        A program that legitimately prints `…` in its own output could not have that output
        pasted into a PR body at all, under the old character ban: the rule matched the
        character and could not see who wrote it. The command line here is clean, and the
        `…` is the PRODUCT's own token on an OUTPUT line — the body is right to paste it.
        """
        f = run(body(how="```\n$ node scripts/check-task-command-vars.mjs\n"
                          "check-task-command-vars: OK — no command step's text carries a ${…} reference\n```"))
        self.assertEqual([x for x in f if x.startswith("ellipsis:")], [])

    def test_a_dropped_line_fails(self):
        """A line that is only an ellipsis is a line dropped from the paste."""
        f = run(body(how="```\n$ cmd\noutput line\n…\n```"))
        self.assertTrue(any(x.startswith("ellipsis:") and "dropped" in x for x in f), f)

    def test_an_elided_head_output_fails(self):
        """An elision in the head command's output hides the head the `head` arm compares."""
        f = run(body(how="```\n$ git rev-parse HEAD\n3e0318aa9a0840c5…\n```"))
        self.assertTrue(any(x.startswith("ellipsis:") and "head command" in x for x in f), f)

    def test_an_ellipsis_in_a_table_is_allowed(self):
        """An abbreviation in a summary table is not a pasted transcript.

        `41bd825a…` is the author's own shorthand for a gitlink in a table of files — the
        rule's doctrine is about PASTED OUTPUT, and a table is not one.
        """
        f = run(body(how="```\n41bd825a…  .agents/skills/agents/SKILL.md\n```"))
        self.assertEqual([x for x in f if x.startswith("ellipsis:")], [])

    def test_the_ellipsis_arm_discriminates(self):
        """R7 — the fixtures' failures must DEPEND on the arm, not on the fixture.

        Mutate the arm's FORM to allow-all and the elided-command fixture must lint
        clean; mutate it to ban-all and the verbatim paste must fail. Each result proves
        its mutation APPLIED, so neither fixture can pass for a reason the arm does not
        own.
        """
        import pr_body_lint as m

        orig = m.ellipsis_kind
        try:
            m.ellipsis_kind = lambda *a, **k: None
            self.assertEqual(
                [x for x in run(body(how="```\n$ git commit …\n```")) if x.startswith("ellipsis:")], []
            )
            m.ellipsis_kind = lambda line, in_head_output=False: "command" if "…" in line else None
            self.assertTrue(
                [x for x in run(body(how="```\n$ cmd\nout … token\n```")) if x.startswith("ellipsis:")]
            )
        finally:
            m.ellipsis_kind = orig

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

    def test_the_ellipsis_arm_is_calibrated_on_the_landed_corpus(self):
        """opencharly/marketplace#537 — the arm must fire on the AUTHOR's elision and on
        nothing else, and the corpus is what says whether it does.

        The corpus is every merged body this repo carries in its own `CHANGELOG/` (each
        entry IS the body of a merged PR, written at merge time). The thirteen bodies in
        `LEGACY_ELLIPSIS_BODIES` were merged before this arm existed and carry the
        author's own elision; they are named, so the corpus is a calibration and not a
        tolerance. The other 435 stay clean, and THAT is the measurement the issue asked
        for: a program that legitimately prints `…` in its own output can have that
        output pasted into a body, verbatim, and the body is right.

        A body that starts firing is a body that reached the corpus without the arm's
        enforcement — a finding to fix, not a number to re-baseline.
        """
        from pr_body_lint import blocks, ellipsis_scan, sections

        logs = sorted((HERE.parent / "CHANGELOG").glob("2026.*.md"))
        self.assertTrue(logs)
        self.assertGreaterEqual(len(logs), 400, "the corpus this rule is calibrated against shrank")
        fired = {}
        for lg in logs:
            kinds = {}
            for _name, sec_lines in sections(lg.read_text().split("\n")).items():
                for kind_of_block, _a, text in blocks(sec_lines):
                    if kind_of_block != "fence":
                        continue
                    for kind, _line in ellipsis_scan(text):
                        kinds[kind] = kinds.get(kind, 0) + 1
            if kinds:
                fired[lg.name] = kinds
            # the arm is WIRED: the linter itself must fire exactly where the scan says
            in_linter = [x for x in run(lg.read_text()) if x.startswith("ellipsis:")]
            self.assertEqual(
                len(in_linter), sum(kinds.values()), f"{lg.name}: the arm and the linter disagree"
            )
        self.assertEqual(fired, LEGACY_ELLIPSIS_BODIES)

    def test_the_measurement_script_reports_the_calibration(self):
        """opencharly/marketplace#537 — the corpus measurement is a SHIPPED instrument, so
        it is measured too: the script must report the numbers the frozen calibration
        states, over the same corpus.

        A script that drifts from the arm it measures is a finding, not a new number:
        the arm's behaviour is the calibration, and the script is only its instrument.
        """
        import ast
        import re
        import subprocess

        script = HERE / "measure_ellipsis_corpus.py"
        self.assertTrue(script.exists(), "the measurement script is missing")
        proc = subprocess.run(
            [sys.executable, str(script)], capture_output=True, text=True, cwd=str(HERE.parent)
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        out = proc.stdout

        summary = re.search(
            r"corpus: (\d+) body/bodies; (\d+) fire the ellipsis arm; (\d+) stay clean", out
        )
        self.assertIsNotNone(summary, f"the script reported no summary:\n{out[-2000:]}")
        bodies, fired, clean = (int(x) for x in summary.groups())
        logs = sorted((HERE.parent / "CHANGELOG").glob("2026.*.md"))
        self.assertEqual(bodies, len(logs), "the script read a different corpus than the test")
        self.assertEqual(fired, len(LEGACY_ELLIPSIS_BODIES))
        self.assertEqual(clean, bodies - fired)

        by_kind = re.search(r"findings by kind: (\{.*\})", out)
        self.assertIsNotNone(by_kind, f"the script reported no kinds:\n{out[-2000:]}")
        expected = {}
        for kinds in LEGACY_ELLIPSIS_BODIES.values():
            for kind, count in kinds.items():
                expected[kind] = expected.get(kind, 0) + count
        self.assertEqual(ast.literal_eval(by_kind.group(1)), expected)

    def test_the_measurement_script_summarises_without_the_character(self):
        """opencharly/marketplace#537 — the instrument must be able to say its numbers
        WITHOUT quoting a finding, because a body cites the summary.

        The per-body lines quote the corpus's own line, and that line carries the very
        character this rule is about. A body pastes a gate's output verbatim, so quoting
        it is allowed; but a SUMMARY is what a body wants to cite, and a summary that
        carries the character invites a reader to ask whether the paste is the author's
        elision or the product's token. The `--summary` mode therefore prints the two
        summary lines and nothing else — and carries no character at all, so nothing in
        it can be read either way.

        The assertion is discriminating: without the flag the run either treats it as a
        path (and reports an empty corpus) or prints the per-body lines, and both fail
        here.
        """
        import subprocess

        script = HERE / "measure_ellipsis_corpus.py"
        full = subprocess.run(
            [sys.executable, str(script)], capture_output=True, text=True, cwd=str(HERE.parent)
        )
        self.assertEqual(full.returncode, 0, full.stderr)
        proc = subprocess.run(
            [sys.executable, str(script), "--summary"], capture_output=True, text=True, cwd=str(HERE.parent)
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        out = proc.stdout

        # the summary is the FULL run's own last two lines, unchanged
        self.assertEqual(
            out.strip().split("\n"),
            full.stdout.strip().split("\n")[-2:],
            "the summary must be the full run's own summary, verbatim",
        )
        # and it names no finding, so it quotes no corpus line
        self.assertNotIn("---", out, "the summary must not print per-body findings")
        self.assertNotIn("[command]", out)
        self.assertNotIn("[dropped]", out)
        # and it carries no character the rule is about
        self.assertNotIn("…", out, "the summary must carry no ellipsis character at all")

    def test_head_mismatch_fails(self):
        sha = "a" * 40
        text = body(how=f"Head `{sha}`")
        self.assertEqual(run(text, head=sha), [])
        self.assertTrue(any(x.startswith("head:") for x in run(text, head="b" * 40)))


class HeadFence(unittest.TestCase):
    """opencharly/marketplace#551 — the body's OTHER anchor form.

    A body has TWO ways of saying which commit its evidence belongs to: the headline
    `Head: \\`<sha>\\`` and a fence that runs `git rev-parse HEAD` and prints the sha. The
    linter compared the first against the head and never the second, so a body whose fence
    named a stale commit passed at 0 findings — and the validator BLOCKed it on exactly
    that drift (opencharly/charly#1039 round 1: the head moved when the commit was amended,
    the headline was re-pasted and the fence was carried over verbatim).

    The fixture is the REAL body of opencharly/charly#1039, the round-2 body the validator
    PASSed. The BLOCKED state is that body's two fence outputs set to the pre-amend commit
    the validator named in round 1 — the only change the fixture makes, and the drift the
    rule exists to catch.
    """

    BODY = (DATA / "charly-1039.md").read_text()
    HEAD = "f1df920c6d6db67212981eb816b69f1501339ef3"
    STALE = "6668ef08f03d693970d572dabb8e356cf8eb7324"

    @classmethod
    def stale_fence(cls, text):
        """The fixture's fence outputs set to the stale commit — the blocked state."""
        return "\n".join(
            cls.STALE if ln.strip() == cls.HEAD else ln for ln in text.split("\n")
        )

    def test_the_real_body_is_clean(self):
        self.assertEqual(run(self.BODY, head=self.HEAD), [])

    def test_a_stale_head_fence_is_a_finding(self):
        f = run(self.stale_fence(self.BODY), head=self.HEAD)
        self.assertTrue(any(x.startswith("head-fence:") for x in f), f)
        # The headline rule stays SILENT here: the drift is in the fence, and the headline
        # still names the head. The two rules see two different claims, and this is the
        # case only the second one can see.
        self.assertFalse(any(x.startswith("head: ") for x in f), f)

    def test_a_fence_that_names_the_head_is_not_a_finding(self):
        f = run(self.BODY, head=self.HEAD)
        self.assertFalse(any(x.startswith("head-fence:") for x in f), f)

    def test_a_tree_is_not_an_anchor(self):
        # `git rev-parse HEAD^{tree}` prints a TREE, not the commit under review.
        text = self.BODY.replace("$ git rev-parse HEAD\n", "$ git rev-parse HEAD^{tree}\n")
        self.assertEqual(run(text, head=self.HEAD), [])

    def test_another_repos_head_is_not_an_anchor(self):
        # `git -C <dir> rev-parse HEAD` names a DIFFERENT repository's head.
        text = self.BODY.replace("$ git rev-parse HEAD\n", "$ git -C other rev-parse HEAD\n")
        self.assertEqual(run(text, head=self.HEAD), [])

    def test_a_quoted_commit_is_not_an_anchor(self):
        # A fence that quotes some other commit (an upstream, a predecessor) is not this
        # PR's anchor: only the OUTPUT of a `git rev-parse HEAD` fence is.
        text = self.BODY.replace(
            "$ git rev-parse HEAD\n", f"$ git show {self.STALE}\n"
        )
        self.assertEqual(run(text, head=self.HEAD), [])

    def test_an_abbreviated_head_makes_no_claim(self):
        # A caller that passes an abbreviated head is not making the claim this rule
        # compares — and a rule that fires on every body is worse than no rule.
        f = run(self.stale_fence(self.BODY), head=self.HEAD[:12])
        self.assertFalse(any(x.startswith("head-fence:") for x in f), f)


class FindingEvidence(unittest.TestCase):
    """A linter finding IS evidence, and evidence is pasted into a body.

    A body that proves a rule works pastes the linter's own output — and a finding that
    truncates a sha with an ellipsis would make the finding itself unverifiable: the sha
    in it would be an elision, not a value a reader can check. The two head findings
    therefore print the FULL sha: the finding is pasteable verbatim, and the shas in it
    are the ones a reader can check.
    """

    BODY = (DATA / "charly-1039.md").read_text()
    HEAD = "f1df920c6d6db67212981eb816b69f1501339ef3"
    STALE = "6668ef08f03d693970d572dabb8e356cf8eb7324"

    def test_the_headline_finding_carries_no_ellipsis(self):
        f = run(self.BODY, head="a" * 40)
        self.assertTrue(any(x.startswith("head: ") for x in f), f)
        for x in f:
            self.assertNotIn("…", x)

    def test_the_head_fence_finding_carries_no_ellipsis(self):
        text = "\n".join(self.STALE if ln.strip() == self.HEAD else ln for ln in self.BODY.split("\n"))
        f = run(text, head=self.HEAD)
        self.assertTrue(any(x.startswith("head-fence:") for x in f), f)
        for x in f:
            self.assertNotIn("…", x)

    def test_the_finding_names_the_full_shas(self):
        text = "\n".join(self.STALE if ln.strip() == self.HEAD else ln for ln in self.BODY.split("\n"))
        f = [x for x in run(text, head=self.HEAD) if x.startswith("head-fence:")]
        self.assertTrue(f)
        for x in f:
            self.assertIn(self.STALE, x)
            self.assertIn(self.HEAD, x)


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

    def test_a_headline_at_the_very_top_of_the_body_is_judged(self):
        """The headline paragraph must not lose its FIRST character.

        `rfind` returns -1 when the headline paragraph is the body's first, and the old
        `+ 2` turned that into 1 — the paragraph then began at index 1, so a diffstat that
        OPENED the paragraph lost its leading digit and the rule matched nothing. The rule
        silently skipped a wrong headline instead of reporting it, which is the one failure
        mode a rule like this may not have.
        """
        text = f"2 files, +33 −8 — Head `{self.SHA}`\n\n## How tested\nx\n"
        f = [x for x in run(text, self.SHA, self.DIFF) if x.startswith("diffstat:")]
        self.assertTrue(f, "a headline at the very top of the body must still be judged")
        self.assertIn("+32 -5", f[0])

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


class BangMarker(unittest.TestCase):
    """The `bang` rule: the head's SUBJECT and the body's ANSWER are two halves of ONE question.

    The Conventional Commits `!` marker says "this change is a hard cutover — it breaks a
    consumer"; the body's `## Change classification` says what breaks for THIS repo's
    consumers and how to roll it back. A marker with a silent answer leaves the merged
    changelog holding two signals and one of them missing (opencharly/opencharly#802).
    """

    MARKED = "feat(scope)!: the cutover"

    def bangs(self, text, subject=MARKED):
        return [x for x in run(text, subject=subject) if x.startswith("bang:")]

    def test_a_marked_subject_without_an_answer_fails(self):
        f = self.bangs(body())
        self.assertTrue(f, "a bang-marked subject with no breaking-change answer must fail")
        self.assertIn("carries NO breaking-change answer", f[0])

    def test_a_marked_subject_with_a_bare_none_fails(self):
        f = self.bangs(body(classification="**Breaking change + rollback:** none"))
        self.assertTrue(f, "a bare `none` under a marker must fail")
        self.assertIn("bare `none`", f[0])

    def test_a_marked_subject_with_an_empty_answer_fails(self):
        """An answer line whose value is EMPTY is as silent as no line at all: the merged
        changelog then holds a `!` beside a line that says nothing (opencharly/marketplace#607).
        """
        f = self.bangs(body(classification="**Breaking change + rollback:**"))
        self.assertTrue(f, "an EMPTY answer under a marker must fail")
        self.assertIn("answer is EMPTY", f[0])

    def test_an_empty_answer_is_refused_as_silence_not_as_a_none(self):
        """The empty value is not a `none` — it is silence, and it is reported as silence, so
        the finding names the shape the author actually wrote."""
        f = self.bangs(body(classification="**Breaking change + rollback:**   "))
        self.assertTrue(f, "a whitespace-only answer must fail")
        self.assertIn("answer is EMPTY", f[0])

    def test_a_line_that_opens_a_different_key_is_not_an_answer(self):
        """The anchor is the PUBLISHED key in full. `**Breaking change policy:**` is a
        DIFFERENT key, and reading its value as the answer is a false positive waiting to
        happen (opencharly/marketplace#607)."""
        f = self.bangs(body(classification="**Breaking change policy:** none"))
        self.assertTrue(f, "a different key must not answer the question")
        self.assertIn("carries NO breaking-change answer", f[0])

    def test_a_different_key_with_a_real_answer_is_still_not_an_answer(self):
        """Tightening the anchor is not a loophole: a real answer under a different key is
        still no answer."""
        f = self.bangs(body(classification="**Breaking change policy:** the flag is gone"))
        self.assertTrue(f, "a different key must not answer the question")
        self.assertIn("carries NO breaking-change answer", f[0])

    def test_a_marked_subject_with_a_reasoned_none_passes(self):
        f = self.bangs(
            body(
                classification="**Breaking change + rollback:** none — the pointers move to "
                "commits the org has already merged"
            )
        )
        self.assertEqual(f, [])

    def test_a_marked_subject_with_a_real_answer_passes(self):
        f = self.bangs(
            body(
                classification="**Breaking change + rollback:** the `--old` flag is deleted; "
                "roll back by reverting this commit"
            )
        )
        self.assertEqual(f, [])

    def test_an_unmarked_subject_needs_no_answer(self):
        """Without a `!` the line is optional — a body that declares a breakage without the
        marker is judged on its own merits, not by this arm."""
        self.assertEqual(self.bangs(body(), subject="feat(scope): an ordinary change"), [])

    def test_a_bang_in_the_prose_after_a_colon_is_not_a_marker(self):
        """Only the Conventional Commits HEADER is read: a subject whose PROSE carries a colon
        and a bang of its own is not a cutover."""
        subject = "docs: correct the 2026.299.0822 entry's false clause about the FAIL: marker"
        self.assertEqual(self.bangs(body(), subject=subject), [])

    def test_an_answer_outside_change_classification_is_not_an_answer(self):
        """The answer belongs to `## Change classification`; the same line under another
        section does not answer the question."""
        text = body().replace(
            "## Change classification\nx",
            "## Change classification\nx\n\n## Notes\n**Breaking change + rollback:** the flag is gone",
        )
        f = self.bangs(text)
        self.assertTrue(f, "an answer outside `## Change classification` must not count")
        self.assertIn("carries NO breaking-change answer", f[0])

    def test_a_bulleted_answer_is_an_answer(self):
        """The house writes the answer as a list item too."""
        f = self.bangs(
            body(classification="- **Breaking change + rollback:** none — the pointers move")
        )
        self.assertEqual(f, [])

    def test_an_unreadable_subject_skips_the_rule(self):
        """None means the subject could not be read: the rule must skip, visibly, rather than
        judge against a fiction."""
        self.assertEqual([x for x in run(body(), subject=None) if x.startswith("bang:")], [])

    def test_the_rule_skips_visibly_when_no_repository_is_given(self):
        """A skip nobody can see is a skip nobody can trust. With no `--repo` the rule never
        RAN — it was not given a repository to read a subject from — and that is NOTICED, so
        a caller cannot mistake "the body is fine" for "the rule never looked"
        (opencharly/marketplace#607)."""
        import contextlib
        import io
        import tempfile

        from pr_body_lint import main

        tmp = tempfile.mkdtemp(prefix="pr-body-lint-")
        p = Path(tmp) / "body.md"
        p.write_text(body())
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            rc = main([str(p)])
        self.assertEqual(rc, 0)
        self.assertIn("NOTICE", err.getvalue())
        self.assertIn("bang rule is SKIPPED", err.getvalue())

    def test_the_rule_does_not_notice_a_skip_it_did_not_take(self):
        """The NOTICE names an ABSENT repository. With a repository and a readable head the
        rule RAN, so it must not claim to have skipped."""
        import contextlib
        import io
        import subprocess
        import tempfile

        from pr_body_lint import main

        tmp = tempfile.mkdtemp(prefix="pr-body-lint-")
        g = lambda *a: subprocess.run(
            ["git", "-C", tmp, *a], check=True, capture_output=True, text=True
        )
        g("init", "-q", "-b", "main")
        g("config", "user.email", "linter@example.invalid")
        g("config", "user.name", "linter")
        Path(tmp, "a.txt").write_text("one\n")
        g("add", "-A")
        g("commit", "-qm", "feat(scope): an ordinary change")
        head = g("rev-parse", "HEAD").stdout.strip()
        p = Path(tmp) / "body.md"
        p.write_text(body())
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            rc = main([str(p), "--repo", tmp, "--head", head])
        self.assertEqual(rc, 0)
        self.assertNotIn("bang rule is SKIPPED", err.getvalue())

    def test_the_rule_derives_the_head_when_only_the_repository_is_given(self):
        """The NOTICE names the argument that was MISSING, and it must name the right one.
        With `--repo` and no `--head`, the head is DERIVED from the repository, so the rule
        RAN — it must neither claim to have skipped nor skip the check it was given
        (opencharly/marketplace#607)."""
        import contextlib
        import io
        import subprocess
        import tempfile

        from pr_body_lint import main

        tmp = tempfile.mkdtemp(prefix="pr-body-lint-")
        g = lambda *a: subprocess.run(
            ["git", "-C", tmp, *a], check=True, capture_output=True, text=True
        )
        g("init", "-q", "-b", "main")
        g("config", "user.email", "linter@example.invalid")
        g("config", "user.name", "linter")
        Path(tmp, "a.txt").write_text("one\n")
        g("add", "-A")
        g("commit", "-qm", "feat(scope)!: the cutover")
        p = Path(tmp) / "body.md"
        p.write_text(body())
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stderr(err), contextlib.redirect_stdout(out):
            rc = main([str(p), "--repo", tmp])
        # The rule RAN: the marked subject and the body's missing answer are the finding.
        self.assertEqual(rc, 1)
        self.assertIn("carries NO breaking-change answer", out.getvalue())
        self.assertNotIn("bang rule is SKIPPED", err.getvalue())

    def test_the_subject_is_read_from_the_commit(self):
        """The rule's other half is the COMMIT's subject, read with git."""
        import subprocess
        import tempfile

        from pr_body_lint import head_subject

        tmp = tempfile.mkdtemp(prefix="pr-body-lint-")
        g = lambda *a: subprocess.run(
            ["git", "-C", tmp, *a], check=True, capture_output=True, text=True
        )
        g("init", "-q", "-b", "main")
        g("config", "user.email", "linter@example.invalid")
        g("config", "user.name", "linter")
        Path(tmp, "a.txt").write_text("one\n")
        g("add", "-A")
        g("commit", "-qm", "feat(scope)!: the cutover")
        head = g("rev-parse", "HEAD").stdout.strip()
        self.assertEqual(head_subject(Path(tmp), head), "feat(scope)!: the cutover")
        self.assertIsNone(head_subject(Path(tmp), "no-such-commit"))
        self.assertIsNone(head_subject(Path("/nonexistent-repo"), head))


if __name__ == "__main__":
    unittest.main(verbosity=2)
