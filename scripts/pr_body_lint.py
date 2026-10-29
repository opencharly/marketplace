#!/usr/bin/env python3
"""Lint a PR body BEFORE the push — the mechanical half of the pre-validator self-audit.

The `charly/pr-validator` reviews the diff AND the body on every run, and a body-only BLOCK is
an ORCHESTRATOR VALIDATION FAILURE (AGENTS.md): it spends a verdict on something a deterministic
check could have caught. This linter fails closed on the body defects that measurably reached
the validator (opencharly/marketplace#404 — distro-fedora#79 and docs#142, both first-push
BLOCKs on the body alone):

  sections   the four required `## ` sections are present;
  footer     OPTIONAL for a human-authored body: a body with no trailer passes. REQUIRED when
             the body carries an `Agent:` line (the mechanical agent marker): the italic
             `Assisted-by` trailer must then be the LAST line, with the `Agent:` line directly
             preceding it. A trailer buried mid-text always fails. The trailer grammar is
             squash_body.py's (one definition);
  rules      `## Rulebook compliance` answers EVERY rule id in --rules, each with a HOW or an
             `N/A — <reason>` (a bare `N/A` fails);
  claims     an asserted check — a sweep result ("only occurrence"), a no-match grep/rg result,
             a check reported as done
             ("… were checked"), an equivalence to a named source ("match(es) `…`") — is backed IN
             ITS SECTION by a later fenced block carrying a `$ ` command, or points at its evidence
             ("above"/"below");
  head       a pasted `Head `<sha>`` equals the commit being pushed, and a `git rev-parse HEAD`
             fence that prints a 40-hex sha names the same commit — the body's TWO anchor
             forms are one claim about one commit;
  evidence   the two head findings print the FULL sha, so a body can paste the linter's own
             output verbatim (the `ellipsis` rule refuses the AUTHOR's elision of a command
             line, of a head command's output, or of a whole line);
  ellipsis   the author's elision of the EVIDENCE: an elided command line (`$ `), an elided
             head command's output, or a dropped line. A `…` in a program's OWN output is
             ALLOWED — the body pastes it verbatim, and the product, not the body, is what
             a program's `…` is about (opencharly/marketplace#537);
  files      the body does not contradict ITSELF about a file: within one section, a file the
             body says CARRIES the change and a file the body says does NOT carry it are the
             same file — that is a defect no other check here can see (opencharly/marketplace#526
             round 2: the Summary said the `strict-policy` skill "c[arries] the new grammar"
             while the body's own detail paragraph said that file "touches no coordination
             label"; the validator BLOCKed on exactly that contradiction);
  counts     a count the body states about a class of files must equal the count of that class
             in the table the body PASTES (a row of `<tag> [<tag>] <path>`) — a count typed by
             hand drifts from the diff it describes (opencharly/marketplace#526 round 3: the
             Summary said "Two of those hunks are carried prose" while the diff carried three,
             and the validator BLOCKed on the undercount);
  diffstat   a diffstat the body's HEADLINE states ("2 files, +33 −8") equals the DIFF's own
             totals — the same drift, one step out: a hand-written count of the change's own
             size goes stale the moment the next commit changes the line totals
             (opencharly/marketplace#548 round 2: the body said "2 files, +33 −8" and the diff
             was "2 files, +32 −5"; the validator BLOCKed on it). The scope is the paragraph
             that carries the pasted `Head` sha — that paragraph is the body's statement about
             THIS commit — so a diffstat quoted about ANOTHER diff, in another paragraph, is
             left alone, and a diffstat inside a fenced block is pasted evidence, not a claim;
  bang       the head's SUBJECT and the body's ANSWER are two halves of ONE question. The
             Conventional Commits `!` marker says "this change is a hard cutover — it breaks a
             consumer"; the body's `## Change classification` says what breaks for THIS repo's
             consumers and how to roll it back. So under a `!` the body MUST carry a
             `**Breaking change + rollback:**` line, and a bare `none` is not an answer: a
             cutover that breaks nothing HERE must say WHY it breaks nothing here (the org
             rulebook, "Commit, push, land"; opencharly/opencharly#802). Without a `!` the
             line is optional, and a body that declares a breakage without the marker is
             judged on its own merits.

It cannot judge whether evidence is SUFFICIENT — that stays the validator's job. It removes the
classes that need no judgment.

usage: pr_body_lint.py <body.md> [--head <sha>] [--repo <dir>] [--base <ref>] [--rules R0,R1,…]
exit:  0 clean · 1 findings · 2 usage
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from squash_body import TRAILER  # noqa: E402  (the ONE Assisted-by grammar)

REQUIRED_SECTIONS = ("Summary", "How tested", "Rulebook compliance", "Change classification")
DEFAULT_RULES = tuple(f"R{i}" for i in range(11))
# The ASSERTED-CHECK shapes the validator measurably BLOCKed (opencharly/marketplace#404): a sweep
# result stated as fact ("this was their only occurrence in the repo", distro-fedora#79), a check
# reported as done without its output ("the open docs PRs were checked", docs#142), and an
# equivalence asserted against a named source ("lists match `packaging/charly.yml`", docs#142).
# Deliberately narrow — a generic "every"/"none" in prose is not a check claim, and a noisy lint
# teaches authors to ignore it.
CLAIM = re.compile(
    r"\bonly occurrence|\b(was|were|been) (checked|verified|swept|confirmed)\b|\bmatch(es)?\s+`",
    re.IGNORECASE,
)
NO_MATCH_SWEEP = re.compile(
    r"\b(?:grep|rg)\b.*\bno matches?\b|\bno matches?\b.*\b(?:grep|rg)\b",
    re.IGNORECASE,
)
SWEEP_COMMAND = re.compile(r"^\s*\$ .*\b(?:grep|rg)\b", re.IGNORECASE)
NO_MATCH_STATUS = re.compile(r"\b(?:exit|rg exit|grep exit)\s*[:=]\s*1\b", re.IGNORECASE)
POINTER = re.compile(r"\b(above|below)\b", re.IGNORECASE)
NA = re.compile(r"\bN/A\b(?P<rest>.*)$")
HEAD = re.compile(r"\bHead\s+`([0-9a-f]{40})`")
# The body's SECOND anchor form: a fence that runs `git rev-parse HEAD` and prints the commit
# it names. The headline `Head:` line and this fence are the SAME claim about the same commit —
# "the evidence I am pasting belongs to this head" — and the linter compared only the first.
# Measured: opencharly/charly#1039 round 1 — the head moved when the commit was amended, the
# headline was re-pasted and the fence was carried over verbatim, the linter reported 0 findings
# and the validator BLOCKed on that mismatch alone (opencharly/marketplace#551).
#
# The command is matched NARROWLY, so the rule stays silent on the legitimate cases: a bare
# `git rev-parse HEAD` only. A `git rev-parse HEAD^{tree}` prints a TREE, a `git -C <dir>
# rev-parse HEAD` prints ANOTHER repo's head, and a fence that quotes some other commit (an
# upstream, a predecessor) is not this PR's anchor at all.
REV_PARSE_HEAD = re.compile(r"^\s*\$\s*git\s+rev-parse\s+HEAD\s*$")
COMMIT_SHA = re.compile(r"^[0-9a-f]{40}$")

# --- the DIFFSTAT rule -------------------------------------------------------
# The body's headline states how big the change is: "2 files, +33 −8". That is a claim about
# the DIFF, and it is a HAND-WRITTEN one: the body is rewritten for each new head, and the
# number is the part that gets forgotten. Measured: opencharly/marketplace#548 round 2 — the
# body said "2 files, +33 −8", the diff was "2 files, +32 −5", and the validator BLOCKed on
# the body's own headline. The diff is the authority and it is readable, so the claim is
# checkable — the same drift the `counts` rule catches one step in, one step out.
#
# TWO shapes, because the house writes both: the inline "N files, +A −B" and git's own
# "N files changed, A insertions(+), B deletions(-)".
DIFFSTAT_INLINE = re.compile(
    r"(?P<files>\d+)\s+files?\b[^0-9\n]{0,24}?\+(?P<ins>\d+)\s*[−–—-]\s*(?P<del>\d+)\b"
)
DIFFSTAT_GIT = re.compile(
    r"(?P<files>\d+)\s+files? changed,\s*(?P<ins>\d+)\s+insertions?\(\+\),\s*"
    r"(?P<del>\d+)\s+deletions?\(-\)"
)

# --- the BANG-MARKER rule ----------------------------------------------------
# The head's SUBJECT carries the Conventional Commits breaking-change marker, and the body's
# `## Change classification` carries the ANSWER to the question the marker asks. They are two
# halves of ONE question — "does this change break a consumer?" — and the merged changelog
# holds them side by side, so a marker with a silent answer leaves the reader holding two
# signals and one of them missing (opencharly/opencharly#802).
#
# Only the Conventional Commits HEADER is read — the part before the first colon — because a
# subject's PROSE may carry a colon and a bang of its own: `docs: correct the 2026.299.0822
# entry's false clause about the FAIL: marker` is a documentation fix, not a cutover. The
# marker sits at the END of the header, where Conventional Commits puts it: `feat(scope)!: …`.
#
# The answer's KEY is the org's own — `**Breaking change + rollback:**` — the form the org
# rulebook names. It is read from a line that OPENS with the key, so a prose mention of the
# words is not read as an answer, and the value is what follows the first colon after it.
BREAKING_ANSWER = re.compile(r"^\s*(?:[-*+]\s+)?\**\s*breaking change\b", re.IGNORECASE)
# A "none" answer with nothing after it is BARE: the merged changelog then holds a `!` beside
# a `none`, which is exactly the sentence a reader cannot resolve. "none — this change only
# carries another repo's cutover" is an ANSWER, because it names the reason.
NONE_ANSWER = re.compile(r"^(none|no|nothing)\b", re.IGNORECASE)
NONE_ANSWER_REST = re.compile(r"^[\s.,:;—–-]+")

# --- the FILE-CLAIM CONSISTENCY rule ------------------------------------------
# A body states, per file, what the diff does to it. Two statements about the SAME file can
# contradict each other, and the contradiction is invisible to every other check in this file:
# the structure is fine, the claims are backed, and each statement is TRUE of the file on its
# own. Only a comparison of the two finds it. Measured: opencharly/marketplace#526, round 2 —
# the Summary said the `strict-policy` skill "c[arries] the new grammar" while the body's own
# detail paragraph said that file "touches no coordination label". The validator BLOCKed the
# body on exactly that contradiction, and no mechanical check here had seen it.
#
# The comparison is mechanical, and deliberately narrow:
#   * a CLAIM needs a PREDICATE ("carries", "touches", "contains", "converts") and an OBJECT
#     that names THE CHANGE ("the new grammar", "a coordination label", "the closed set", …).
#     A claim about anything else — "carries authoring prose", "contains no runtime
#     dependency" — names a different proposition and is not comparable, so it is left alone;
#   * a FILE is named by its path, or by prose ("the `strict-policy` skill", "its
#     multi-repo-coordination reference"). Both normalize to the same key, so the Summary's
#     prose name and the detail paragraph's path are recognised as the same file;
#   * the comparison happens WITHIN ONE SECTION. Across sections the body narrates its own
#     history ("the Summary listed the `strict-policy` skill among the files that carry the
#     new grammar"), and a past-tense narration is not a claim about the file. A contradiction
#     inside one section has no such excuse.
CHANGE_OBJECT = re.compile(
    r"\b(?:the new grammar|the grammar|a coordination label|coordination labels?|"
    r"the closed set|the new closed set|the new set|the new labels?|the new verbs?|"
    r"the new vocabulary|the rename|the renamed set)\b",
    re.IGNORECASE,
)
CARRY = re.compile(r"\b(carries|carry|touches|touch|contains|contain|converts|convert)\b", re.IGNORECASE)
# The words that make a claim NEGATIVE. The vocabulary decides the polarity, so a missing
# entry turns a negative claim into a positive one: a body that says "X carries none of the
# new grammar" in one paragraph and "X does not carry the new grammar" in another was read
# as claiming BOTH, and the `files` rule fired on a body that was telling the truth.
# Measured: opencharly/marketplace#526, round 4 — the validator's non-blocking observation.
#
# ONE vocabulary, read in TWO positions: before the predicate (a negative subject — "X does
# not carry the new grammar") and immediately after it (a negative object — "X carries none
# of the new grammar"). The two positions differ in WHERE they look, not in WHICH words they
# recognise: a second, narrower copy of the list is how the two drift apart, and the drift is
# the defect this change was written for.
NEGATION_WORDS = r"no|not|neither|nor|zero|without|never|lacks?|lack|none|nothing"
NEGATION = re.compile(r"\b(?:" + NEGATION_WORDS + r")\b", re.IGNORECASE)
NEGATION_LEAD = re.compile(r"\s*(?:" + NEGATION_WORDS + r")\b", re.IGNORECASE)
PATH_TOKEN = re.compile(
    r"\b[\w][\w./-]*\.(?:md|sh|py|mjs|cjs|ts|tsx|yml|yaml|json|txt|cue|toml|js)\b"
)
TICKED = re.compile(r"`([^`\n]+)`")
KIND = re.compile(
    r"\b(skills?|references?|agents?|files?|docs?|pages?|guides?)\b", re.IGNORECASE
)
PROSE_NAME = re.compile(
    r"\b([a-z][\w-]*(?:[ ][a-z][\w-]+){0,2})[ ]+(?:skills?|references?|agents?|files?|docs?|pages?|guides?)\b"
)
SLUG = re.compile(r"^[a-z0-9][\w-]*(?:[ ][\w-]+){0,2}$")
LEADING = re.compile(r"^(?:the|its|a|an|that|this|these|those|each|every|our|their)\b[ ]*")


def _stem(path: str) -> str:
    """The key of a path: the file's own name, or its directory for SKILL.md/index.md."""
    base = path.rsplit("/", 1)[-1]
    parent = path.rsplit("/", 2)[-2] if "/" in path else ""
    if base.lower() in ("skill.md", "index.md", "readme.md"):
        return parent
    return base.rsplit(".", 1)[0]


def _paragraphs(text_lines: list[str]) -> list[str]:
    """The prose paragraphs of a block: consecutive non-blank lines, joined."""
    out: list[str] = []
    cur: list[str] = []
    for ln in text_lines:
        if ln.strip():
            cur.append(ln.strip())
        elif cur:
            out.append(" ".join(cur))
            cur = []
    if cur:
        out.append(" ".join(cur))
    return out


def _named_files(para: str, generic: set[str]) -> set[str]:
    """The files this paragraph names, as keys.

    A path gives its stem; a prose name gives itself. A name that is a FAMILY directory of a
    named path (`agents`, `references`) is not a file, and is dropped — but the directory that
    HOLDS a SKILL.md is that file's own name, so it is kept.
    """
    found: set[str] = set()
    for m in PATH_TOKEN.finditer(para):
        stem = _stem(m.group(0))
        if stem and stem not in generic:
            found.add(stem)
    for m in TICKED.finditer(para):
        tok = m.group(1).strip()
        if SLUG.match(tok):
            key = tok.replace(" ", "-")
            if key not in generic:
                found.add(key)
    for m in PROSE_NAME.finditer(para):
        phrase = LEADING.sub("", m.group(1).strip())
        if " " in phrase and "-" not in phrase:
            continue
        key = phrase.replace(" ", "-")
        if key not in generic:
            found.add(key)
    return found


GENERIC = re.compile(
    r"\b(?:files|skills|references|agents|docs|pages|hunks|changes|ones|things|paragraphs)\b",
    re.IGNORECASE,
)


def _claim_polarity(para: str) -> list[tuple[str, int]]:
    """The comparable claims this paragraph makes: (polarity, predicate position).

    Only a predicate whose object names THE CHANGE counts; a claim about anything else —
    "carries authoring prose", "contains no runtime dependency" — names a different
    proposition and is left alone.
    """
    out: list[tuple[str, int]] = []
    for m in CARRY.finditer(para):
        after = re.split(r"[.;:\n]", para[m.end(): m.end() + 120])[0]
        if not CHANGE_OBJECT.search(after):
            continue
        neg = bool(NEGATION.search(para[max(0, m.start() - 40):m.start()]))
        if NEGATION_LEAD.match(after):
            neg = True
        out.append(("neg" if neg else "pos", m.start()))
    return out


def _file_claims(body_lines: list[str]) -> list[str]:
    """The self-contradictions about a file, one finding each.

    Compared WITHIN a section: across sections a body narrates its own history, and a
    past-tense narration is not a claim about the file.
    """
    findings: list[str] = []
    secs = sections(body_lines)
    for name, body_lines_s in secs.items():
        joined = "\n".join(body_lines_s)
        stems = {_stem(m.group(0)) for m in PATH_TOKEN.finditer(joined)}
        generic: set[str] = set()
        for m in PATH_TOKEN.finditer(joined):
            generic.update(m.group(0).split("/")[:-1])
        # a directory that HOLDS a SKILL.md is that file's own name, not a family
        generic -= stems
        pos: dict[str, str] = {}
        neg: dict[str, str] = {}
        for kind, _, text in blocks(body_lines_s):
            if kind != "text":
                continue
            for para in _paragraphs(text):
                claims = _claim_polarity(para)
                pols = {p for p, _ in claims}
                if len(pols) != 1:
                    continue
                names = _named_files(para, generic)
                for polarity, at in claims:
                    # A predicate whose subject is a GENERIC noun ("the files that carry the
                    # new grammar") says something about that noun, not about the file the
                    # paragraph mentioned. Nothing between the last named file and the
                    # predicate means the predicate is about the named files.
                    last = max(
                        (m.end() for m in PATH_TOKEN.finditer(para) if m.end() < at), default=-1
                    )
                    for m in TICKED.finditer(para):
                        if m.end() < at:
                            last = max(last, m.end())
                    if last >= 0 and GENERIC.search(para[last:at]):
                        continue
                    for key in names:
                        (pos if polarity == "pos" else neg).setdefault(key, para)
        for key in sorted(set(pos) & set(neg)):
            findings.append(
                f"files: `{name}` contradicts itself about `{key}` — the body says it carries the "
                f"change AND that it does not: {pos[key][:90]!r} / {neg[key][:90]!r}"
            )
    return findings


# --- the COUNT-CONSISTENCY rule ------------------------------------------------
# A body that classifies files in a PASTED TABLE — a row of `<tag> [<tag>] <path>`, the shape
# this org already uses for `git status --short` output (`M  path.md`) — and then states a
# COUNT in prose must state the table's count. The two are the same fact, and a count typed by
# hand drifts from the table it describes: the author classifies nine files, then writes "two"
# because two of them were the ones they were looking at.
#
# Measured: opencharly/marketplace#526, round 3 — the Summary said "Two of those hunks are
# carried prose" and named two of the three generated projections that carry none; the third,
# `internals/skills/marketplace/SKILL.md`, was never named. Nothing in the body contradicted
# itself (the `files` rule is clean on it), every count was TRUE of the two files it named,
# and the validator BLOCKed the body on the undercount.
#
# The check is deliberately narrow:
#   * a TABLE is a fenced block with two or more rows of that shape; anything else in a fence
#     (a command, a numstat, a log) is not a table;
#   * a tag of ONE character is not a class (a `git status` code), so it is never compared —
#     otherwise "A" reads as the English article and every count in the section matches it;
#   * a tag that appears in TWO tables of the same section is ambiguous — the counts cannot be
#     attributed — and is left alone;
#   * the count must GOVERN the class word: the number comes FIRST ("Two of those hunks are
#     carried prose") and within a few words of it, because a number that FOLLOWS a class word
#     quantifies something else ("the coordination grammar's closed set is nine labels" counts
#     labels, not grammars);
#   * a numstat pair ("76/38") is not a count and is stripped before the comparison;
#   * a NARRATION is not a claim: a sentence that reports what a body said ("the Summary
#     said 'Two of those hunks are carried prose'") quotes a count, it does not assert one,
#     so a reporting verb in the sentence retires it;
#   * the comparison happens WITHIN ONE SECTION, because a table and the prose about it belong
#     to the same section.
COUNT_WORDS = {
    "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
    "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
    "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
    "nineteen": 19, "twenty": 20,
}
COUNT_PHRASE = re.compile(
    r"(?<![\w./-])(?P<n>\d{1,3}|" + "|".join(COUNT_WORDS) + r")(?![\w/])",
    re.IGNORECASE,
)
NARRATION = re.compile(
    r"\b(?:said|says|wrote|written|listed|named|stated|claimed|counted|reported|"
    r"misstated|undercounted|returned|blocked|missed|caught|quoted)\b",
    re.IGNORECASE,
)
NUMSTAT_PAIR = re.compile(r"\b\d{1,4}\s*/\s*\d{1,4}\b")
TABLE_PATH = re.compile(r"^\S+\.(?:md|sh|py|mjs|cjs|ts|tsx|yml|yaml|json|txt|cue|toml|js)$")
TABLE_TAG = re.compile(r"^[A-Za-z][A-Za-z-]*$")
COUNT_WINDOW = 6  # words between the count and the class word it governs


def _table_rows(lines: list[str]) -> list[tuple[list[str], str]]:
    """The rows of a classification table: (tags, path), lower-cased tags."""
    rows: list[tuple[list[str], str]] = []
    for ln in lines:
        toks = ln.split()
        if len(toks) < 2:
            continue
        if not TABLE_PATH.match(toks[-1]):
            continue
        tags = toks[:-1]
        if not all(TABLE_TAG.match(t) for t in tags):
            continue
        rows.append(([t.lower() for t in tags], toks[-1]))
    return rows


def _count_claims(body_lines: list[str]) -> list[str]:
    """The counts the body states about a class it also pasted a table for."""
    findings: list[str] = []
    for name, sec in sections(body_lines).items():
        counts: dict[str, int] = {}
        ambiguous: set[str] = set()
        for kind, _i, text in blocks(sec):
            if kind != "fence":
                continue
            rows = _table_rows(text)
            if len(rows) < 2:
                continue
            seen: dict[str, int] = {}
            for tags, _p in rows:
                for t in tags:
                    seen[t] = seen.get(t, 0) + 1
            for t, c in seen.items():
                if len(t) < 2:
                    continue  # a `git status` code is not a class
                if t in counts:
                    ambiguous.add(t)
                counts[t] = c
        if not counts:
            continue
        for kind, _i, text in blocks(sec):
            if kind != "text":
                continue
            for para in _paragraphs(text):
                para = NUMSTAT_PAIR.sub(" ", para)
                for sent in re.split(r"(?<=[.!?;])\s+", para):
                    if NARRATION.search(sent):
                        continue  # a quoted count is not an asserted one
                    words = sent.split()
                    for m in COUNT_PHRASE.finditer(sent):
                        raw = m.group("n")
                        stated = int(raw) if raw.isdigit() else COUNT_WORDS[raw.lower()]
                        # the class word this count governs: the first one AFTER it
                        after = m.end()
                        candidates: list[tuple[int, str]] = []
                        for tag in counts:
                            if tag in ambiguous:
                                continue
                            tm = re.search(
                                rf"(?<![\w-]){re.escape(tag)}(?![\w-])", sent[after:], re.IGNORECASE
                            )
                            if not tm:
                                continue
                            between = len(sent[after : after + tm.start()].split())
                            if between > COUNT_WINDOW:
                                continue
                            candidates.append((between, tag))
                        if not candidates:
                            continue
                        candidates.sort()
                        if len(candidates) > 1 and candidates[0][0] == candidates[1][0]:
                            continue  # two class words at the same distance: ambiguous
                        tag = candidates[0][1]
                        if stated != counts[tag]:
                            findings.append(
                                f"counts: `{name}` says {raw} {tag} but the pasted table has "
                                f"{counts[tag]} {tag} row(s): {sent.strip()[:90]!r}"
                            )
    return findings


def blocks(lines: list[str]):
    """Yield (kind, start_index, text_lines): 'fence' for ``` blocks, 'text' for the rest."""
    i, n = 0, len(lines)
    while i < n:
        if lines[i].lstrip().startswith("```"):
            j = i + 1
            while j < n and not lines[j].lstrip().startswith("```"):
                j += 1
            yield "fence", i, lines[i + 1 : j]
            i = j + 1
        else:
            j = i
            while j < n and not lines[j].lstrip().startswith("```"):
                j += 1
            yield "text", i, lines[i:j]
            i = j


def head_fence_anchors(lines: list[str]) -> list[str]:
    """The commit shas the body's `git rev-parse HEAD` fences print — its OTHER anchor form.

    A fence that runs the bare command and prints a 40-hex sha states which commit its
    evidence belongs to. The sha on the NEXT non-empty line is the output; a line that is not
    a sha (a comment, an error) means the command printed nothing usable, and the fence is
    not an anchor.
    """
    out: list[str] = []
    for kind, _, text in blocks(lines):
        if kind != "fence":
            continue
        for i, ln in enumerate(text):
            if not REV_PARSE_HEAD.match(ln):
                continue
            for nxt in text[i + 1 :]:
                s = nxt.strip()
                if not s:
                    continue
                if COMMIT_SHA.match(s):
                    out.append(s)
                break
    return out


def sections(lines: list[str]) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    cur = None
    for ln in lines:
        m = re.match(r"^## +(.+?)\s*$", ln)
        if m:
            cur = m.group(1)
            out[cur] = []
        elif cur is not None:
            out[cur].append(ln)
    return out


# --- the DIFFSTAT rule's two halves -------------------------------------------
def _headline_diffstats(lines: list[str]) -> list[re.Match]:
    """The diffstats the body's HEADLINE states — the paragraph carrying the pasted `Head` sha.

    The PARAGRAPH, not the whole body: a diffstat in another paragraph may be about a
    DIFFERENT diff (an upstream PR, a predecessor this PR supersedes), and a rule that
    judged those would cry wolf on a true body. A fenced block is pasted evidence, not a
    claim, so a headline that opens one is not judged either.
    """
    text = "\n".join(lines)
    head = HEAD.search(text)
    if not head:
        return []
    # The paragraph starts AFTER the last blank line before the head — or at the very top of
    # the body when the headline IS the first paragraph. `rfind` returns -1 in that case, and
    # the old `-1 + 2` made the paragraph start at index 1: its first character was dropped,
    # and a diffstat that OPENED the paragraph lost its leading digit and matched nothing.
    sep = text.rfind("\n\n", 0, head.start())
    start = 0 if sep == -1 else sep + 2
    end = text.find("\n\n", head.end())
    if end == -1:
        end = len(text)
    para = text[start:end]
    # A fenced block is pasted EVIDENCE, not a claim: a `git diff --shortstat` pasted next to
    # the headline is the truth the headline is checked against, and judging it would be
    # judging the evidence. The prose around it is still judged.
    kept: list[str] = []
    in_fence = False
    for ln in para.split("\n"):
        if ln.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if not in_fence:
            kept.append(ln)
    prose = "\n".join(kept)
    found: list[re.Match] = []
    for pattern in (DIFFSTAT_INLINE, DIFFSTAT_GIT):
        found.extend(pattern.finditer(prose))
    return found


def diff_totals(repo: Path, base: str, head: str) -> tuple[int, int, int] | None:
    """The diff's own totals — (files, insertions, deletions) — against `base`.

    None when the diff cannot be read: an unresolvable base, a missing repository, a git
    that fails. The rule then SKIPS, visibly, rather than guessing — a lint that invents
    the truth is worse than a lint that stays quiet.
    """

    def git(*args: str) -> str:
        return subprocess.run(
            ["git", "-C", str(repo), *args], check=True, capture_output=True, text=True
        ).stdout

    try:
        merge_base = git("merge-base", base, head).strip()
        numstat = git("diff", "--numstat", merge_base, head)
    except (subprocess.CalledProcessError, OSError):
        return None
    if not merge_base:
        return None
    files = insertions = deletions = 0
    for line in numstat.splitlines():
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        files += 1
        if parts[0].isdigit():
            insertions += int(parts[0])
        if parts[1].isdigit():
            deletions += int(parts[1])
    return files, insertions, deletions


# --- the BANG-MARKER rule's three halves --------------------------------------
def subject_carries_marker(subject: str) -> bool:
    """Does the head's SUBJECT carry the Conventional Commits breaking-change marker?

    Only the HEADER is read — the part before the first colon — because a subject's prose may
    carry a colon and a bang of its own. The marker sits at the END of the header, where
    Conventional Commits puts it: `feat(scope)!: …`.
    """
    header = subject.split(":")[0]
    return bool(re.search(r"!\s*$", header))


def breaking_change_answer(section_lines: list[str]) -> dict | None:
    """The body's breaking-change ANSWER: the line under `## Change classification` that
    OPENS with the key, so a prose mention of the words is not read as an answer.

    The key is the org's own — `**Breaking change + rollback:**`. The value is what follows
    the first colon after the key. Returns the line's 1-based number within the section, the
    value, and the whole text, or None when the section carries no answer at all.
    """
    for i, ln in enumerate(section_lines):
        m = BREAKING_ANSWER.match(ln)
        if not m:
            continue
        after = ln[m.end() :]
        colon = after.find(":")
        value = (after if colon == -1 else after[colon + 1 :]).strip()
        return {"line": i + 1, "value": value, "text": ln.strip()}
    return None


def none_answer(plain: str) -> str | None:
    """Is the answer a "none", and does it say WHY?

    "none" alone is not an answer under a marker: the merged changelog carries the subject and
    the body side by side, and a bare "none" next to a `!` is exactly the sentence a reader
    cannot resolve. "none — this change only carries another repo's cutover" is an answer,
    because it names the reason. Returns "bare", "reasoned", or None when the answer is not a
    "none" at all.
    """
    m = NONE_ANSWER.match(plain)
    if not m:
        return None
    rest = NONE_ANSWER_REST.sub("", plain[m.end() :]).strip()
    return "bare" if not rest else "reasoned"


def bang_findings(section_lines: list[str], subject: str) -> list[str]:
    """The `bang` findings: the head's subject marker and the body's answer must agree.

    `section_lines` is the body's `## Change classification` section — empty when the body
    carries no such section, which is the `sections` rule's own finding; this arm reports the
    missing ANSWER, which is a different statement.
    """
    if not subject_carries_marker(subject):
        return []
    answer = breaking_change_answer(section_lines)
    if answer is None:
        return [
            f"bang: the head's subject carries the breaking-change marker (`{subject}`) and the "
            f"body's `## Change classification` carries NO breaking-change answer — the marker says "
            f"this change is part of a hard cutover, so the body must say what breaks for this "
            f"repo's consumers and how to roll it back"
        ]
    plain = re.sub(r"[*_`]", "", answer["value"]).strip()
    if none_answer(plain) == "bare":
        return [
            f"bang: the head's subject carries the breaking-change marker (`{subject}`) and the "
            f"body's answer is a bare `none` (line {answer['line']}) — a cutover that breaks "
            f"nothing HERE must say WHY it breaks nothing here (for example: this change only "
            f"carries another repo's cutover)"
        ]
    return []


def head_subject(repo: Path, head: str) -> str | None:
    """The head's SUBJECT — the half of the bang relation that lives in the commit.

    None when it cannot be read: an unresolvable commit, a missing repository, a git that
    fails. The rule then SKIPS, visibly, rather than guessing — a lint that invents the truth
    is worse than a lint that stays quiet.
    """
    try:
        out = subprocess.run(
            ["git", "-C", str(repo), "log", "-1", "--format=%s", head],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    except (subprocess.CalledProcessError, OSError):
        return None
    return out.strip() or None


# The SWEEP subset of CLAIM: claims about an EXHAUSTIVE SEARCH, where only a command can
# support the assertion. Ordinary rule bullets ("git status was checked", "the artifact was
# verified after the build") assert that a STEP WAS DONE, and `## Rulebook compliance` is
# designed to back those with the evidence of the section -- measured: requiring bullet-local
# backing for the whole CLAIM regex fires on 7 of 36 merged bodies, every one a false
# positive. So the bullet-local requirement is scoped to this subset alone.
SWEEP_CLAIM = re.compile(r"\bonly occurrence\b|\b(?:was|were|been) swept\b", re.IGNORECASE)

BULLET = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s")


def own_bullet_has_command(section_lines: list[str], start: int) -> bool:
    """Is there a `$ ` fence in the claim's OWN bullet (up to the next bullet marker)?

    This is what "pasted with the claim" means for a sweep claim: the exhaustive search's
    command belongs to the bullet asserting it, not to some unrelated fence further down.
    """
    for ln in section_lines[start + 1:]:
        if BULLET.match(ln):
            return False
        if ln.lstrip().startswith("$ "):
            return True
    return False


HEAD_BEARING = "rev-parse HEAD"

# The `ellipsis` rule's three findings, by the KIND of elision they name.  A command line
# is the author's own typing; a head command's output is what the `head` arm compares; a
# line that is only an ellipsis is a line dropped from the paste.
ELLIPSIS_KINDS = {
    "command": "the command line is elided",
    "head": "the head command's output is elided",
    "dropped": "a line of the paste is dropped",
}


def ellipsis_kind(line: str, *, in_head_output: bool = False) -> str | None:
    """Classify one fenced line's `…` under the `ellipsis` rule's FORM (marketplace#537).

    The rule bans the AUTHOR's elision of the evidence the other arms read, and ALLOWS a
    program's own token, which the body pastes verbatim:

      "command"  the line is a command line (it starts with `$ `).  A command line in a
                  transcript is the author's own typing — a program never prints one — so
                  a `…` there is the author eliding the very evidence the `claims` arm
                  reads ("a later pasted `$ ` command").
      "head"     the line is the output of a head-bearing command in the same fence.  An
                  elision there hides the head the `head` arm has to compare.
      "dropped"  the line's whole content is `…` — a line dropped from the paste.

    Everything else is a program's own token (`${…}`, `retrying…`, a path the product
    abbreviates): the paste is verbatim, the body is right, and if anything is defective
    it is the PRODUCT that printed the character — not this body.  The validator is the
    judge there; this is a tool, and a tool that cannot see authorship must not guess.
    """
    if "…" not in line:
        return None
    stripped = line.strip()
    if stripped.startswith("$ "):
        return "command"
    if stripped == "…":
        return "dropped"
    if in_head_output:
        return "head"
    return None


def ellipsis_scan(text: list[str]) -> list[tuple[str, str]]:
    """Every `…` in one fenced block that the rule's FORM fires on, as (kind, line).

    The block is walked ONCE, here, and the head-bearing flag is carried across the
    lines: a command line's output is the output of THAT command, until the next
    command line. The linter and the corpus measurement both read this, so the
    classification has one owner.
    """
    hits: list[tuple[str, str]] = []
    in_head_output = False
    for ln in text:
        stripped = ln.strip()
        if stripped.startswith("$ "):
            kind = ellipsis_kind(ln)
            in_head_output = HEAD_BEARING in stripped
        else:
            kind = ellipsis_kind(ln, in_head_output=in_head_output)
        if kind:
            hits.append((kind, stripped))
    return hits


def ellipsis_findings(section: str, text: list[str]) -> list[str]:
    """Every `ellipsis` finding in one fenced block, under the rule's FORM."""
    return [
        f"ellipsis: {ELLIPSIS_KINDS[kind]} in `## {section}`: {line[:80]!r}"
        for kind, line in ellipsis_scan(text)
    ]


def lint(
    body: str,
    head: str | None,
    rules: tuple[str, ...],
    diffstat: tuple[int, int, int] | None = None,
    subject: str | None = None,
) -> list[str]:
    findings: list[str] = []
    lines = body.rstrip("\n").split("\n")
    secs = sections(lines)

    for name in REQUIRED_SECTIONS:
        if name not in secs:
            findings.append(f"sections: missing `## {name}`")

    tail = [ln for ln in lines if ln.strip()]
    last = tail[-1].strip() if tail else ""

    def is_trailer(ln: str) -> bool:
        s = ln.strip()
        return len(s) > 2 and s.startswith("*") and s.endswith("*") and bool(TRAILER.match(s[1:-1]))

    def is_agent_line(ln: str) -> bool:
        # The mechanical agent marker: `Agent:` opens the line, in its plain or emphasis-wrapped
        # form (`Agent: …`, `*Agent: …*`, `**Agent:** …`). A mention mid-line is not a marker.
        return ln.strip().lstrip("*").startswith("Agent:")

    has_trailer = any(is_trailer(ln) for ln in tail)
    has_agent = any(is_agent_line(ln) for ln in tail)

    # The footer is OPTIONAL for a body with no `Agent:` line (as far as the linter can tell, a
    # human author). A body that carries the agent marker REQUIRES the trailer, and a trailer
    # that IS present must be the last non-empty line, so it cannot be buried mid-text (and a
    # second, earlier trailer cannot pass alongside a final one). The message shape is unchanged
    # for the misplaced arm.
    if any(i != len(tail) - 1 for i, ln in enumerate(tail) if is_trailer(ln)):
        findings.append(f"footer: the last line must be the italic Assisted-by trailer, got: {last[:80]!r}")
    if has_agent and not has_trailer:
        findings.append("footer: a body carrying an `Agent:` line must end with the italic Assisted-by trailer")
    if has_trailer and any(is_agent_line(ln) for ln in tail[:-1]) and not is_agent_line(tail[-2]):
        findings.append("footer: the `Agent:` line must directly precede the Assisted-by trailer")

    rc = secs.get("Rulebook compliance", [])
    for rule in rules:
        hit = [ln for ln in rc if re.search(rf"\b{re.escape(rule)}\b", ln)]
        if not hit:
            findings.append(f"rules: `## Rulebook compliance` does not answer {rule}")
            continue
        for ln in hit:
            m = NA.search(ln)
            if m and len(re.findall(r"[A-Za-z0-9_`]+", m.group("rest"))) < 2:
                findings.append(f"rules: {rule} is a bare N/A — give `N/A — <reason>`")

    for name, body_lines in secs.items():
        bl = list(blocks(body_lines))
        _starts, _pos = [], 0
        for _kind, _, _text in bl:
            _starts.append(_pos)
            _pos += len(_text)
        for k, (kind, _, text) in enumerate(bl):
            if kind == "fence":
                findings.extend(ellipsis_findings(name, text))
                continue
            backed_later = any(
                kk == "fence" and any(t.lstrip().startswith("$ ") for t in tt) for kk, _, tt in bl[k + 1 :]
            )
            for _i, ln in enumerate(text):
                if NO_MATCH_SWEEP.search(ln):
                    sweep_backed = any(
                        kk == "fence"
                        and any(SWEEP_COMMAND.search(t) for t in tt)
                        and any(NO_MATCH_STATUS.search(t) for t in tt)
                        for kk, _, tt in bl[k + 1 :]
                    )
                    if not sweep_backed:
                        findings.append(
                            f"claims: no-match grep/rg claim in `## {name}` needs a later pasted "
                            f"grep/rg command and exit=1 result: {ln.strip()[:100]!r}"
                        )
                    continue
                # NARROW shape: only a SWEEP claim must be backed inside its own bullet.
                # An ordinary rule assertion keeps the section-wide `backed_later` rule.
                _sweep_unbacked = SWEEP_CLAIM.search(ln) and not own_bullet_has_command(
                    body_lines, _starts[k] + _i
                )
                if CLAIM.search(ln) and not POINTER.search(ln) and (_sweep_unbacked or not backed_later):
                    findings.append(
                        f"claims: unbacked universal claim in `## {name}` (no later `$ ` command block, "
                        f"no (above)/(below) pointer): {ln.strip()[:100]!r}"
                    )

    pasted = HEAD.search(body)
    if pasted and head and pasted.group(1) != head:
        # The sha is printed in FULL, in both head findings below. A finding is EVIDENCE: a
        # body that proves a rule works pastes the linter's own output, and the house's
        # `ellipsis` rule refuses a `…` inside a fence — a truncated sha would make the
        # linter's own output un-pasteable in the one form a body is allowed to show it.
        findings.append(f"head: body pastes Head `{pasted.group(1)}` but the commit is `{head}`")

    # The body's OTHER anchor form: a `git rev-parse HEAD` fence that prints a commit which is
    # not the head being pushed (opencharly/marketplace#551). The headline and the fence are
    # one claim about one commit, and a body can carry both in the same paste.
    # The head must be a FULL sha: a caller that passes an abbreviated one is not making the
    # claim this rule compares, and a rule that fires on every body is worse than no rule.
    if head and COMMIT_SHA.match(head):
        for anchor in head_fence_anchors(lines):
            if anchor != head:
                findings.append(
                    f"head-fence: body pastes `git rev-parse HEAD` output `{anchor}` "
                    f"but the commit is `{head}`"
                )

    # The body's own headline count of the diff, against the diff. `diffstat` is None when
    # the diff could not be read — the rule then SKIPS (visibly, in main()), because a
    # lint that invents the truth is worse than a lint that stays quiet.
    if diffstat is not None:
        for m in _headline_diffstats(lines):
            stated = (int(m.group("files")), int(m.group("ins")), int(m.group("del")))
            if stated != diffstat:
                findings.append(
                    f"diffstat: the body states \"{m.group(0).strip()}\" but the diff is "
                    f"{diffstat[0]} files, +{diffstat[1]} -{diffstat[2]}"
                )

    findings.extend(_file_claims(lines))
    findings.extend(_count_claims(lines))

    # The head's SUBJECT and the body's ANSWER are two halves of ONE question. The subject is
    # None when it could not be read: the rule then SKIPS, visibly (in main()), rather than
    # guessing — a lint that invents the truth is worse than a lint that stays quiet.
    if subject is not None:
        classification = next(
            (v for k, v in secs.items() if k.strip().lower() == "change classification"), []
        )
        findings.extend(bang_findings(classification, subject))

    return findings


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("body", type=Path)
    ap.add_argument("--head", help="the commit SHA being pushed (default: the repository's HEAD)")
    ap.add_argument("--repo", type=Path, help="the repository the diff is read from")
    ap.add_argument("--base", default="origin/main", help="the ref the diff is measured against")
    ap.add_argument("--rules", default=",".join(DEFAULT_RULES), help="comma-separated rule ids to require")
    a = ap.parse_args(argv)
    head = a.head
    if head is None and a.repo:
        head = subprocess.run(
            ["git", "-C", str(a.repo), "rev-parse", "HEAD"], check=True, capture_output=True, text=True
        ).stdout.strip()
    diffstat = None
    if a.repo and head:
        diffstat = diff_totals(a.repo, a.base, head)
        if diffstat is None:
            print(
                f"pr_body_lint: NOTICE - the diff against {a.base!r} could not be read, so the "
                f"diffstat rule is SKIPPED",
                file=sys.stderr,
            )
    subject = None
    if a.repo and head:
        subject = head_subject(a.repo, head)
        if subject is None:
            print(
                f"pr_body_lint: NOTICE - the head's subject could not be read, so the bang rule "
                f"is SKIPPED",
                file=sys.stderr,
            )
    findings = lint(
        a.body.read_text(),
        head,
        tuple(r for r in a.rules.split(",") if r),
        diffstat,
        subject,
    )
    for f in findings:
        print(f"FAIL  {f}")
    print(f"pr_body_lint: {len(findings)} finding(s)")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
