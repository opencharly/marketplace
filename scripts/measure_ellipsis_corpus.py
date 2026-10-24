#!/usr/bin/env python3
"""Measure the `ellipsis` rule against a corpus of BODIES (opencharly/marketplace#537).

The `ellipsis` arm of `pr_body_lint.py` fires on the author's elision of the evidence the
other arms read. This script is the CALIBRATION instrument: it runs that arm — the shipped
one, imported, not re-implemented — over a corpus and reports, per body, what fired and
what did not.

The corpus is any set of body-shaped files. The default is this repo's own `CHANGELOG/`,
whose entries ARE the bodies of merged PRs, written at merge time: it is the corpus of
what the org actually lands, and it grows with every merge.

usage: measure_ellipsis_corpus.py [--summary] [path ...]      (default: CHANGELOG/*.md)

`--summary` prints the two summary lines and nothing else. The per-body lines quote the
FINDING, and a finding quotes the corpus's own line — which carries the character the arm
is about. A body pastes a gate's output verbatim, so the full output is the PRODUCT's and
is allowed (opencharly/marketplace#537); but a summary is what a body wants to cite, and
a summary carries no character at all, so nothing in it can be read either way.
"""
from __future__ import annotations

import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from pr_body_lint import blocks, ellipsis_scan, sections  # noqa: E402


def bodies(paths: list[Path]) -> list[Path]:
    out: list[Path] = []
    for p in paths:
        if p.is_dir():
            out.extend(sorted(p.glob("2026.*.md")))
        else:
            out.append(p)
    return out


def measure(path: Path) -> tuple[Counter, list[tuple[str, str]]]:
    """One body's tally: the kinds that fired, and the lines that fired them."""
    kinds: Counter = Counter()
    hits: list[tuple[str, str]] = []
    lines = path.read_text().rstrip("\n").split("\n")
    for _name, sec_lines in sections(lines).items():
        for kind_of_block, _a, text in blocks(sec_lines):
            if kind_of_block != "fence":
                continue
            for kind, line in ellipsis_scan(text):
                kinds[kind] += 1
                hits.append((kind, line[:100]))
    return kinds, hits


def main() -> int:
    args = sys.argv[1:]
    summary_only = False
    if "--summary" in args:
        summary_only = True
        args = [a for a in args if a != "--summary"]
    paths = bodies([Path(a) for a in args]) if args else bodies([HERE.parent / "CHANGELOG"])
    if not paths:
        print("measure_ellipsis_corpus: NOTICE - the corpus is empty", file=sys.stderr)
        return 0
    total = Counter()
    fired_bodies = 0
    allowed = 0
    for p in paths:
        kinds, hits = measure(p)
        total.update(kinds)
        if kinds:
            fired_bodies += 1
            if not summary_only:
                print(f"--- {p.name}: {sum(kinds.values())} finding(s)")
                for k, line in hits:
                    print(f"      [{k}] {line}")
        else:
            allowed += 1
    if not summary_only:
        print()
    print(f"corpus: {len(paths)} body/bodies; {fired_bodies} fire the ellipsis arm; {allowed} stay clean")
    print(f"findings by kind: {dict(total) if total else '{}'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
