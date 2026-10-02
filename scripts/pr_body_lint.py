#!/usr/bin/env python3
"""Lint a PR body BEFORE the push — the mechanical half of the pre-validator self-audit.

The `charly/pr-validator` reviews the diff AND the body on every run, and a body-only BLOCK is
an ORCHESTRATOR VALIDATION FAILURE (AGENTS.md): it spends a verdict on something a deterministic
check could have caught. This linter fails closed on the body defects that measurably reached
the validator (opencharly/marketplace#404 — distro-fedora#79 and docs#142, both first-push
BLOCKs on the body alone):

  sections   the four required `## ` sections are present;
  footer     the italic `Assisted-by` trailer is the LAST line (an `Agent:` line, when present,
             directly precedes it); the trailer grammar is squash_body.py's (one definition);
  rules      `## Rulebook compliance` answers EVERY rule id in --rules, each with a HOW or an
             `N/A — <reason>` (a bare `N/A` fails);
  claims     an asserted check — a sweep result ("only occurrence"), a check reported as done
             ("… were checked"), an equivalence to a named source ("match(es) `…`") — is backed IN
             ITS SECTION by a later fenced block carrying a `$ ` command, or points at its evidence
             ("above"/"below");
  head       a pasted `Head `<sha>`` equals the commit being pushed;
  ellipsis   no `…` inside a fenced block (pasted output is verbatim, never ellipsized).

It cannot judge whether evidence is SUFFICIENT — that stays the validator's job. It removes the
classes that need no judgment.

usage: pr_body_lint.py <body.md> [--head <sha> | --repo <dir>] [--rules R0,R1,…]
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
POINTER = re.compile(r"\b(above|below)\b", re.IGNORECASE)
NA = re.compile(r"\bN/A\b(?P<rest>.*)$")
HEAD = re.compile(r"\bHead\s+`([0-9a-f]{40})`")


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


def lint(body: str, head: str | None, rules: tuple[str, ...]) -> list[str]:
    findings: list[str] = []
    lines = body.rstrip("\n").split("\n")
    secs = sections(lines)

    for name in REQUIRED_SECTIONS:
        if name not in secs:
            findings.append(f"sections: missing `## {name}`")

    tail = [ln for ln in lines if ln.strip()]
    last = tail[-1].strip() if tail else ""
    trailer = last[1:-1] if last.startswith("*") and last.endswith("*") else ""
    if not TRAILER.match(trailer):
        findings.append(f"footer: the last line must be the italic Assisted-by trailer, got: {last[:80]!r}")
    if any(ln.lstrip().startswith("*Agent:") for ln in tail[:-1]) and not tail[-2].lstrip().startswith("*Agent:"):
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
        for k, (kind, _, text) in enumerate(bl):
            if kind == "fence":
                for ln in text:
                    if "…" in ln:
                        findings.append(f"ellipsis: fenced output in `## {name}` contains `…`: {ln.strip()[:80]!r}")
                continue
            backed_later = any(
                kk == "fence" and any(t.lstrip().startswith("$ ") for t in tt) for kk, _, tt in bl[k + 1 :]
            )
            for ln in text:
                if CLAIM.search(ln) and not POINTER.search(ln) and not backed_later:
                    findings.append(
                        f"claims: unbacked universal claim in `## {name}` (no later `$ ` command block, "
                        f"no (above)/(below) pointer): {ln.strip()[:100]!r}"
                    )

    pasted = HEAD.search(body)
    if pasted and head and pasted.group(1) != head:
        findings.append(f"head: body pastes Head `{pasted.group(1)[:12]}…` but the commit is `{head[:12]}…`")
    return findings


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("body", type=Path)
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--head", help="the commit SHA being pushed")
    g.add_argument("--repo", type=Path, help="read the head from `git -C <repo> rev-parse HEAD`")
    ap.add_argument("--rules", default=",".join(DEFAULT_RULES), help="comma-separated rule ids to require")
    a = ap.parse_args(argv)
    head = a.head
    if a.repo:
        head = subprocess.run(
            ["git", "-C", str(a.repo), "rev-parse", "HEAD"], check=True, capture_output=True, text=True
        ).stdout.strip()
    findings = lint(a.body.read_text(), head, tuple(r for r in a.rules.split(",") if r))
    for f in findings:
        print(f"FAIL  {f}")
    print(f"pr_body_lint: {len(findings)} finding(s)")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
