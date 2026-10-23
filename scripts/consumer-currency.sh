#!/usr/bin/env bash
# consumer-currency.sh — REPORT each RECORDED consumer's recorded corpus pin, and whether
# that pin is behind this repo's merged main. It never fails.
#
# WHY. The corpus advances by producer-first landings; each consumer's pin is advanced by a
# MANUAL act in the consumer's own repo, one PR per consumer, after the corpus lands. Nothing
# in the chain asks whether a consumer's recorded pin is still current, so a corpus can land
# and the consumer keeps publishing a projection of the corpus it already replaced — the
# measured case: opencharly/docs's recorded marketplace gitlink stayed 14 commits behind the
# corpus's merged main, and every published recipe page was a projection of the older corpus.
#
# The consumer's own drift gate CANNOT see this: it asks "does the committed content match
# what the PINNED inputs generate?" and the pinned corpus generates its own (old) pages
# perfectly, so a stale corpus is invisible to it. This asks the OTHER question — "is the
# pin itself current?" — from the producer's side, so it fires when the CORPUS moves.
#
# The answer is REPORTED, never failed. A consumer that is behind is an advance available NOW
# — the same shape the pin contract calls `behind`: a reportable state, not a broken edge.
# A gate that FAILED on it would be red on every run until somebody ran the consumer's
# pin-bump PR, and the remedy is that PR, not a gate.
#
# THE STATES ARE THE PIN CONTRACT'S (umbrella AGENTS.md Part II rule 3): `cur`, `behind`,
# `blocked-by` and `not-on-the-served-line`. A corpus is squash-merged, so a consumer pin
# that is off the corpus's main line is a SQUASH-ADVANCE — `not-on-the-served-line` — whose
# one remedy is the same as `behind`'s: the consumer re-pins to the tip. It is NOT a
# divergence, and this report never calls it one.
#
# THE CONSUMER SET IS THE README's "## Consumers" TABLE — one record, no second list. The
# table's first cell is the consumer repo and its second cell is the path at which the
# consumer records the corpus pin (the submodule path in its .gitmodules). A consumer is
# added by adding a row, so the record and the report cannot drift apart.
#
# THE PIN IS READ OVER THE PUBLIC API, not by cloning: GET /repos/<owner>/<repo>/contents/<path>
# answers a submodule entry with the gitlink sha the consumer records. No checkout, no fetch.
#
# THE JUDGMENT runs against THIS repo's own history: the pin is a MERGED corpus commit (Part II
# rule 3 — pin only MERGED refs), so `git merge-base --is-ancestor <pin> <merged main>` decides
# it. A SHALLOW history cannot decide it (the ancestry test answers "not an ancestor" for a
# commit it simply does not have), so a shallow repo is reported as undecidable, never as a
# divergence — a false state is worse than no report.
#
# usage: bash scripts/consumer-currency.sh [<repo-root>]
# Prints the report on stdout. Exit status is 0 in EVERY state, including a squash-advance,
# an unreadable pin and a broken consumer record: a report that could fail the build would
# be a gate, and this is not one.
set -u

ROOT="${1:-.}"
README="$ROOT/README.md"

# The corpus's merged main, as THIS repo's history sees it.
MAIN=""
MAIN_STATE="readable"
if ! MAIN="$(git -C "$ROOT" rev-parse --verify -q "origin/main^{commit}" 2>/dev/null)"; then
  MAIN_STATE="unreadable"
  MAIN="(unknown)"
fi
# A shallow history cannot decide ancestry: `merge-base --is-ancestor` answers "not an
# ancestor" for a commit the clone does not have, which is indistinguishable from a real
# squash-advance. Say so instead of guessing.
SHALLOW="no"
if [ "$MAIN_STATE" = "readable" ] && [ "$(git -C "$ROOT" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
  SHALLOW="yes"
fi

# ---- the consumer set: the README's "## Consumers" table, parsed ------------------
# One line per consumer: "<owner>/<repo>\t<path>". A malformed table yields NO lines, and
# that is reported loudly — a report that silently reads nothing is a dead control.
CONSUMERS=""
if [ -r "$README" ]; then
  CONSUMERS="$(python3 - "$README" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
inside = False
for line in lines:
    if line.startswith("## "):
        inside = line[3:].strip().lower() == "consumers"
        continue
    if not inside:
        continue
    m = re.match(r"^\|\s*`([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)`\s*\|\s*`([^`]+)`\s*\|", line)
    if m:
        print(f"{m.group(1)}\t{m.group(2)}")
PY
)"
fi

read_count=0
behind_count=0
squash_count=0
undecidable_count=0
unreadable_count=0
lines=""

while IFS=$'\t' read -r repo path; do
  [ -n "$repo" ] || continue
  read_count=$((read_count + 1))

  # The consumer's recorded pin, read over the public API.
  pin=""
  if command -v gh >/dev/null 2>&1; then
    pin="$(gh api "repos/$repo/contents/$path" --jq .sha 2>/dev/null || true)"
  fi
  if [ -z "$pin" ]; then
    unreadable_count=$((unreadable_count + 1))
    lines="$lines  $repo  $path  (no pin)  unreadable — the consumer's recorded pin could not be read"$'\n'
    continue
  fi

  if [ "$MAIN_STATE" != "readable" ]; then
    unreadable_count=$((unreadable_count + 1))
    lines="$lines  $repo  $path  ${pin:0:7}  undecidable — this repo's merged main could not be read"$'\n'
    continue
  fi
  if [ "$SHALLOW" = "yes" ]; then
    undecidable_count=$((undecidable_count + 1))
    lines="$lines  $repo  $path  ${pin:0:7}  undecidable — this repo's history is shallow, so ancestry cannot be judged"$'\n'
    continue
  fi

  if ! git -C "$ROOT" cat-file -e "$pin^{commit}" 2>/dev/null; then
    squash_count=$((squash_count + 1))
    lines="$lines  $repo  $path  ${pin:0:7}  not-on-the-served-line — the pin is not on this repo's main line; its one remedy is the same as behind's (a pin-bump PR in that consumer's repo), and it is not a divergence"$'\n'
    continue
  fi

  if git -C "$ROOT" merge-base --is-ancestor "$pin" "$MAIN" 2>/dev/null; then
    behind="$(git -C "$ROOT" rev-list --count "$pin..$MAIN" 2>/dev/null || echo 0)"
    if [ "$behind" = "0" ]; then
      state="cur — at the corpus's merged main"
    else
      behind_count=$((behind_count + 1))
      state="behind — $behind commit(s) behind the corpus's merged main; an advance available NOW (a pin-bump PR in that consumer's repo)"
    fi
  else
    squash_count=$((squash_count + 1))
    state="not-on-the-served-line — the pin is not on this repo's main line; its one remedy is the same as behind's (a pin-bump PR in that consumer's repo), and it is not a divergence"
  fi
  lines="$lines  $repo  $path  ${pin:0:7}  $state"$'\n'
done <<< "$CONSUMERS"

if [ "$read_count" -eq 0 ]; then
  # The report read NOTHING. Say so loudly: a consumer set that cannot be parsed is a broken
  # record, and a report that silently reads nothing is a control that is quietly dead.
  echo "consumer-currency: WARNING — no consumer row in README.md's '## Consumers' table; the report is EMPTY" >&2
fi

echo "consumer-currency: $read_count consumer(s) read, $behind_count behind, $squash_count not-on-the-served-line, $undecidable_count undecidable, $unreadable_count unreadable (merged main: ${MAIN:0:7})"
printf '%s' "$lines"
exit 0
