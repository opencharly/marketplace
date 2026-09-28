#!/usr/bin/env bash
# pr_watch_many.sh — watch SEVERAL pull requests (across repos) with the sanctioned
# pr_state_watch.sh and exit the instant ANY of them reaches a terminal state.
#
# WHY THIS EXISTS
#   `pr_state_watch.sh` is the ONE sanctioned poll for a PR's terminal state (MERGED /
#   BLOCKED / CLOSED), and it exists so "keep polling" is never the answer. But it
#   watches ONE PR. A producer-first landing is a CHAIN of PRs across repos, so watching
#   the whole batch by hand means a per-PR `while`/`sleep` loop — exactly the R4 band-aid
#   the skill forbids. This script wraps the sanctioned watcher N times, in parallel, and
#   STOPS on the first terminal state, so one command (and one harness notification)
#   covers a whole cross-repo batch.
#
#   It adds NO polling logic of its own: every per-PR decision is pr_state_watch.sh's,
#   including its ability to tell a real verdict BLOCK from the POISON stuck state that
#   `gh pr checks --watch` cannot see.
#
# Usage:
#   pr_watch_many.sh [--interval SECONDS] [--timeout SECONDS] [--all] \
#                    <owner/repo> <pr> [<owner/repo> <pr> ...]
#
#   Default: exit as soon as the FIRST PR reaches a terminal state (fast feedback on a
#   batch — usually you only need to act on one red verdict at a time).
#   --all:   wait for EVERY PR to reach a terminal state, then report them together.
#
# Output (stdout), one line per terminal PR:
#   TERMINAL <STATE> (exit <N>) <owner/repo>#<pr>
# where <STATE> ∈ MERGED(0) BLOCKED(2) CLOSED(3) TIMEOUT(4) ERROR(5) — the exit codes
# pr_state_watch.sh defines. Exit 0 once reported (the per-PR code is in the output).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCH="$SELF_DIR/pr_state_watch.sh"
if [ ! -x "$WATCH" ]; then
  echo "ERROR: $WATCH not found or not executable (pr_watch_many.sh wraps it)" >&2
  exit 5
fi

INTERVAL=20
TIMEOUT=7200
WAIT_ALL=0
PAIRS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --interval) INTERVAL="${2:?}"; shift 2 ;;
    --timeout)  TIMEOUT="${2:?}";  shift 2 ;;
    --all)      WAIT_ALL=1; shift ;;
    -h|--help)  sed -n '2,40p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)          PAIRS+=("$1"); shift ;;
  esac
done
if [ "${#PAIRS[@]}" -lt 2 ] || [ $(( ${#PAIRS[@]} % 2 )) -ne 0 ]; then
  echo "usage: pr_watch_many.sh [--interval S] [--timeout S] [--all] <owner/repo> <pr> ..." >&2
  exit 5
fi

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"; kill $PIDS 2>/dev/null' EXIT
PIDS=""

label_for() {
  case "$1" in
    0) echo MERGED ;; 2) echo BLOCKED ;; 3) echo CLOSED ;; 4) echo TIMEOUT ;; *) echo ERROR ;;
  esac
}

report() { # $1 = result file
  local code repo pr
  IFS='|' read -r code repo pr < "$1"
  printf 'TERMINAL %s (exit %s) %s#%s\n' "$(label_for "$code")" "$code" "$repo" "$pr"
}

i=0
while [ "$i" -lt "${#PAIRS[@]}" ]; do
  repo="${PAIRS[$i]}"; pr="${PAIRS[$((i+1))]}"; i=$((i+2))
  key="$(printf '%s#%s' "$repo" "$pr" | tr '/#' '__')"
  ( "$WATCH" "$repo" "$pr" --interval "$INTERVAL" --timeout "$TIMEOUT" >/dev/null 2>&1
    printf '%s|%s|%s\n' "$?" "$repo" "$pr" > "$OUT/$key" ) &
  PIDS="$PIDS $!"
done

if [ "$WAIT_ALL" -eq 1 ]; then
  wait
  for f in "$OUT"/*; do [ -e "$f" ] && report "$f"; done
  exit 0
fi

# First terminal state wins: block until one watcher finishes, then report every
# result that has already landed (usually exactly one).
wait -n
sleep 2   # let the finisher's result file flush to disk
for f in "$OUT"/*; do [ -e "$f" ] && report "$f"; done
exit 0
