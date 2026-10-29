#!/usr/bin/env bash
# drift-gate.sh — the ONE implementation of the corpus drift check.
#
# WHY IT IS A SCRIPT, AND NOT A STEP IN EACH WORKFLOW. Two callers need this check, and
# it must be ONE implementation:
#
#   * `.github/workflows/deploy.yml` — the repo's gate: the corpus that is committed must
#     match what the pinned charly generates. A refs bump that does not ship its
#     regenerated corpus fails here.
#   * `.github/workflows/refresh.yml` — the daily refresh, which RUNS the gate in the job
#     that assembles the PR body, so the body can carry the gate's OWN RESULT and not only
#     its source. The opencharly/marketplace#588 validator BLOCKed that body for asserting
#     a tier the gate had not yet backed ("the supplied PR state contains no drift-gate run
#     result or check status").
#
# A copy of the check in each workflow would be a second implementation of one rule, and
# two implementations of a gate drift apart silently: the copy nobody runs is the one that
# goes stale. So the check lives HERE, and both workflows run this file.
#
# THE QUESTION IT ASKS. "The tree did not move since the index was set." The caller stages
# what it wants committed FIRST — the refresh job stages the first generation — and then
# runs this, so the gate answers for the STAGED tree: the corpus this PR would commit is
# exactly what the generator produces.
#
# TWO COMPONENTS, and the second is the one a diff alone misses:
#
#   1. the WORKING TREE against the INDEX — `git diff --quiet`. A tracked file the
#      regeneration changed.
#   2. the files that are in NO index at all — `git ls-files --others --exclude-standard`.
#      A generator that emits NEW artifacts (a new skill/family/manifest) creates them as
#      untracked files, and `git diff` does not see them.
#
# WHAT IT DOES NOT ASK. It does NOT compare the index with HEAD — and that is why it does
# not use `git status --porcelain`, which reports the index column as well as the worktree
# column. The refresh job stages the regenerated corpus on purpose, so the index differs
# from HEAD by design and `git status --porcelain` is non-empty by CONSTRUCTION: a gate
# built on it fails every refresh run and no PR is ever opened. Measured 2026-10-29 on the
# refresh's own tree: the check aborted with DRIFT and listed the whole staged corpus,
# while the tree had not moved at all (no unstaged change, no untracked file).
# `scripts/drift_gate_test.sh` holds the arm that catches it.
#
# usage: drift-gate.sh [work-dir]
# exit 0 — the tree did not move: a regeneration is a no-op
# exit 1 — DRIFT: the tree moved; the committed corpus and the generator disagree
# exit 2 — usage error
set -uo pipefail
export LC_ALL=C

DIR="${1:-}"
if [ -z "$DIR" ]; then
  DIR="."
elif [ "$#" -gt 1 ]; then
  echo "usage: drift-gate.sh [work-dir]" >&2
  exit 2
fi

cd "$DIR" || exit 2

UNTRACKED="$(git ls-files --others --exclude-standard)"
if ! git diff --quiet || [ -n "$UNTRACKED" ]; then
  echo "DRIFT: the committed corpus does not match this repo's refs list."
  echo "Regenerate and commit the corpus in the same marketplace PR"
  echo "(the drift gate is scripts/drift-gate.sh)."
  echo "--- the working tree against the index:"
  git diff --stat | head -20
  echo "--- the files that are in no index:"
  printf '%s\n' "$UNTRACKED" | head -20
  exit 1
fi
echo "corpus: committed tree matches the pinned charly (regeneration is a no-op)."
