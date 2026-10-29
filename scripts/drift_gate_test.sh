#!/usr/bin/env bash
# drift_gate_test.sh — prove scripts/drift-gate.sh answers the question it claims to
# answer, and that it fails CLOSED.
#
# WHAT IT PROVES, against the SHIPPED script.
#   D-CLEAN      a tree that did not move PASSES, and says so in its own words.
#   D-STAGED     a tree whose INDEX differs from HEAD — with the working tree matching
#                the index — PASSES. This is the refresh job's own situation: it stages
#                the regenerated corpus on purpose, so the index differs from HEAD by
#                design. A check built on `git status --porcelain` fails here, because
#                that command also reports the index column: a gate built on it fails on
#                the refresh job's tree shape, every time it runs there. Measured
#                2026-10-29 on the refresh's own tree — DRIFT on a tree that had not moved.
#   D-MOVED      a tracked file that differs from the index FAILS.
#   D-UNTRACKED  a file that is in no index at all FAILS too. This is the half
#                `git diff` alone misses: a generator that emits NEW artifacts recreates
#                them as untracked files, and `git diff` does not see them.
#   D-MESSAGE    the failure says DRIFT and the success says what it checked, so a reader
#                of the log can tell which side it landed on.
#
# THE RED ARMS mutate a COPY of the shipped script and require the suite to go RED on
# it: once with the wrong instrument (`git status --porcelain`, which compares the index
# with HEAD as well) and once with the untracked half dropped. Without them the suite
# would pass on a script that had lost the check it exists to make, and a test that
# cannot fail proves nothing (R7). An arm that did NOT turn the suite red is a FINDING,
# and the process exits non-zero.
#
# usage:
#   bash scripts/drift_gate_test.sh [--script FILE] [--self-test]
#
#   --script FILE  check FILE instead of the shipped script
#   --self-test    additionally run the red arms; each must turn the suite red
set -uo pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/drift-gate.sh"
SELFTEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --script) SCRIPT="${2:?--script needs a file}"; shift 2 ;;
    --self-test) SELFTEST=1; shift ;;
    -h|--help) sed -n '2,32p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "usage: bash scripts/drift_gate_test.sh [--script FILE] [--self-test]" >&2; exit 2 ;;
  esac
done

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
FAILS=0
ok()  { printf '  PASS  %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1" >&2; FAILS=$((FAILS + 1)); }

# A fixture repository: one committed file, nothing else.
make_repo() {
  local d="$1"
  rm -rf "$d"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email "drift-gate-test@example.invalid"
  git -C "$d" config user.name "drift-gate test"
  printf 'the committed corpus\n' > "$d/SKILL.md"
  git -C "$d" add -A
  git -C "$d" commit -q -m "the committed corpus"
}

# run_gate <script> <repo-dir> — the script's output in $OUT and its status in $RC.
run_gate() {
  local script="$1" dir="$2"
  OUT="$(bash "$script" "$dir" 2>&1)"
  RC=$?
}

check_suite() {
  local script="$1" label="$2"
  local before=$FAILS

  if [ ! -f "$script" ]; then
    bad "[$label] the gate script does not exist: $script"
    return $((FAILS - before))
  fi

  # --- D-CLEAN -----------------------------------------------------------------------
  local repo="$WORK/clean"
  make_repo "$repo"
  run_gate "$script" "$repo"
  if [ "$RC" -eq 0 ]; then
    ok "[$label] a tree that did not move passes the gate"
  else
    bad "[$label] a tree that did not move FAILED the gate (rc=$RC): $OUT"
  fi
  if printf '%s' "$OUT" | grep -qF 'corpus: committed tree matches the pinned charly (regeneration is a no-op).'; then
    ok "[$label] the passing gate says what it checked"
  else
    bad "[$label] the passing gate does not say what it checked: $OUT"
  fi

  # --- D-STAGED ----------------------------------------------------------------------
  # The refresh job's own shape: the corpus is STAGED (the index differs from HEAD) and
  # the working tree matches the index. The tree has NOT moved, so the gate must pass.
  repo="$WORK/staged"
  make_repo "$repo"
  printf 'the regenerated corpus\n' > "$repo/SKILL.md"
  git -C "$repo" add -A
  run_gate "$script" "$repo"
  if [ "$RC" -eq 0 ]; then
    ok "[$label] a STAGED corpus with an unmoved tree passes the gate (the refresh's own shape)"
  else
    bad "[$label] a STAGED corpus with an unmoved tree FAILED the gate (rc=$RC) — the gate compares the index with HEAD, and the refresh job's tree shape is STAGED by design, so a gate like that fails on every run of that job: $OUT"
  fi

  # --- D-MOVED -----------------------------------------------------------------------
  repo="$WORK/moved"
  make_repo "$repo"
  printf 'the committed corpus, CHANGED\n' > "$repo/SKILL.md"
  run_gate "$script" "$repo"
  if [ "$RC" -eq 1 ]; then
    ok "[$label] a modified tracked file fails the gate"
  else
    bad "[$label] a modified tracked file did NOT fail the gate (rc=$RC): $OUT"
  fi
  if printf '%s' "$OUT" | grep -qF 'DRIFT:'; then
    ok "[$label] the failing gate says DRIFT"
  else
    bad "[$label] the failing gate does not say DRIFT: $OUT"
  fi

  # --- D-UNTRACKED -------------------------------------------------------------------
  # The half `git diff` alone misses: `git diff` sees no change here, so a gate that
  # checks only the diff PASSES this tree, and it must not.
  repo="$WORK/untracked"
  make_repo "$repo"
  mkdir -p "$repo/newdir"
  printf 'a new artifact the generator emitted\n' > "$repo/newdir/SKILL.md"
  run_gate "$script" "$repo"
  if [ "$RC" -eq 1 ]; then
    ok "[$label] an UNTRACKED file fails the gate (the fail-closed half)"
  else
    bad "[$label] an UNTRACKED file did NOT fail the gate (rc=$RC) — the gate is not fail-closed: $OUT"
  fi

  return $((FAILS - before))
}

# The two mutations. Each removes one half of the check, and the suite must catch it.
mutate_status_instrument() {
  # The wrong instrument: `git status --porcelain` also reports the index column, so a
  # STAGED corpus (the refresh's own shape) reads as drift.
  sed -e 's#if ! git diff --quiet || \[ -n "\$UNTRACKED" \]; then#if ! git diff --exit-code || [ -n "$(git status --porcelain)" ]; then#' "$1" > "$2"
}
mutate_drop_untracked() {
  # The untracked half dropped.
  sed -e 's#if ! git diff --quiet || \[ -n "\$UNTRACKED" \]; then#if ! git diff --quiet; then#' "$1" > "$2"
}

printf 'drift_gate_test.sh — gate: %s\n' "$SCRIPT"
check_suite "$SCRIPT" "shipped" || true

if [ "$SELFTEST" -eq 1 ]; then
  printf '\nred arms — each mutation must turn the suite RED\n'
  for arm in status_instrument drop_untracked; do
    mutant="$WORK/mutant-$arm.sh"
    "mutate_$arm" "$SCRIPT" "$mutant"
    fails_before=$FAILS
    check_suite "$mutant" "arm:$arm" > "$WORK/mutant-$arm.log" 2>&1
    arm_fails=$((FAILS - fails_before))
    # The mutant's findings are the ARM's expected outcome, not the suite's own findings:
    # they are rolled back, so only a mutation that did NOT turn the suite red is a
    # finding.
    FAILS=$fails_before
    if [ "$arm_fails" -gt 0 ]; then
      ok "red arm '$arm' turns the suite red ($arm_fails finding(s) on the mutant)"
      grep -m 3 'FAIL' "$WORK/mutant-$arm.log" | sed 's/^/      /'
    else
      printf '  FAIL  red arm %s did NOT turn the suite red\n' "'$arm'" >&2
      FAILS=$((FAILS + 1))
    fi
  done
fi

if [ "$FAILS" -gt 0 ]; then
  printf '\nFAILED: %d finding(s)\n' "$FAILS" >&2
  exit 1
fi
printf '\nOK\n'
exit 0
