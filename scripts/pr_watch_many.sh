#!/usr/bin/env bash
# pr_watch_many.sh — watch a cross-repo PR batch and wake ONCE, on the first of
# three signals. Fully generic: the repo set, poll interval, stall window, and
# validator workflow name are all configurable; no org, repo, session, or date is
# baked in.
#
# SIGNALS
#   0  PR TERMINAL  a watched PR reaches MERGED / BLOCKED / CLOSED, delegated to
#                   the sanctioned pr_state_watch.sh (so the POISON stuck state is
#                   reported distinctly from a real verdict BLOCK).
#   1  NEW VERDICT  a new `<validator>` run COMPLETES on any watched repo. This is
#                   the PROGRESS signal. Session activity is NOT progress: a
#                   looping agent never goes quiet, and a peer waiting on a
#                   running validator looks quiet but is working.
#   2  STALL        no new verdict landed for --stallmin minutes while at least one
#                   watched PR is still open+unmerged. A re-arguing agent emits no
#                   new verdicts, so "no new verdict in the window" is the correct
#                   loop detector — never session silence.
#
# USAGE
#   pr_watch_many.sh [OPTIONS] <owner/repo> <pr> [<owner/repo> <pr> ...]
#   pr_watch_many.sh [OPTIONS] --repos <owner/repo>[,<owner/repo>...]
#
# OPTIONS
#   --repos LIST      repos to watch for validator runs, comma-separated. Default:
#                     the repos named by the PR pairs, deduped. In repo-only mode
#                     (no PR pairs) signals 0 and 2 are inactive.
#   --interval SEC    poll cadence, seconds (default 20; minimum 1).
#   --timeout SEC     overall deadline, seconds; 0 disables (default 7200).
#   --stallmin MIN    stall window, minutes; 0 disables signal 2 (default 0).
#   --validator NAME  validator workflow name (default charly/pr-validator).
#   --all             wait for EVERY PR to reach a terminal state, then report
#                     them together (signals 1-2 inactive in this mode).
#   -h, --help        print this help and exit 0.
#
# OUTPUT (stdout, one line per wake — the harness notifies on the script exiting)
#   TERMINAL <STATE> (exit <N>) <owner/repo>#<pr>   STATE in MERGED BLOCKED CLOSED
#   WAKE VERDICT  <repo>  <conclusion>  <branch>  <updatedAt>  <run-url>
#   WAKE STALL    no new verdict for >=<MIN>m while PR scopes remain open+unmerged
#   WAKE TIMEOUT  no signal within <SEC>s
#
# EXIT  0 once a wake was reported (the scope's own status is in the output line);
#       4 on timeout; 5 on usage/error. Every per-PR terminal decision is
#       pr_state_watch.sh's (which defines 0 MERGED / 2 BLOCKED / 3 CLOSED /
#       4 TIMEOUT / 5 ERROR and distinguishes POISON).
#
# WHY NOT `gh pr checks --watch` / a hand-rolled loop: the sanctioned per-PR poll is
# pr_state_watch.sh (it sees POISON, which `gh pr checks` cannot), and this wrapper
# adds the two cross-repo progress layers a batch landing needs WITHOUT
# re-implementing any polling of its own.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCH="$SELF_DIR/pr_state_watch.sh"

INTERVAL=20
TIMEOUT=7200
STALLMIN=0
VALIDATOR="${PR_WATCH_VALIDATOR:-charly/pr-validator}"
WAIT_ALL=0
REPOS_ARG=""
PAIRS=()

# Print the leading comment block (shebang excluded) as the usage text. Derived
# from the file itself, so it can never drift out of range the way a hardcoded
# `sed -n 'a,bp'` does.
usage() {
  awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repos)     REPOS_ARG="${2:?--repos needs a comma-separated value}"; shift 2 ;;
    --interval)  INTERVAL="${2:?--interval needs a value}"; shift 2 ;;
    --timeout)   TIMEOUT="${2:?--timeout needs a value}"; shift 2 ;;
    --stallmin)  STALLMIN="${2:?--stallmin needs a value}"; shift 2 ;;
    --validator) VALIDATOR="${2:?--validator needs a value}"; shift 2 ;;
    --all)       WAIT_ALL=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    -*)          echo "pr_watch_many: unknown flag $1" >&2; usage >&2; exit 5 ;;
    *)           PAIRS+=("$1"); shift ;;
  esac
done

# --- validation (fail loud, never a silent default) ------------------------
numeric() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
numeric "$INTERVAL" && [ "$INTERVAL" -ge 1 ] || { echo "pr_watch_many: --interval must be an integer >= 1, got '$INTERVAL'" >&2; exit 5; }
numeric "$TIMEOUT"  || { echo "pr_watch_many: --timeout must be an integer >= 0, got '$TIMEOUT'" >&2; exit 5; }
numeric "$STALLMIN" || { echo "pr_watch_many: --stallmin must be an integer >= 0, got '$STALLMIN'" >&2; exit 5; }
[ $(( ${#PAIRS[@]} % 2 )) -eq 0 ] || { echo "pr_watch_many: PR arguments must be <owner/repo> <pr> pairs" >&2; exit 5; }

# --- resolve the watched repo set (explicit --repos, else derived from pairs) ---
REPOS=()
add_repo() {
  local r
  for r in "${REPOS[@]}"; do [ "$r" = "$1" ] && return 0; done
  REPOS+=("$1")
}

if [ -n "$REPOS_ARG" ]; then
  IFS=',' read -r -a _explicit <<< "$REPOS_ARG"
  for r in "${_explicit[@]}"; do [ -n "$r" ] && add_repo "$r"; done
fi
i=0
while [ "$i" -lt "${#PAIRS[@]}" ]; do add_repo "${PAIRS[$i]}"; i=$((i+2)); done

if [ "${#REPOS[@]}" -eq 0 ]; then
  echo "pr_watch_many: nothing to watch — pass PR pairs and/or --repos" >&2
  exit 5
fi
if [ "${#PAIRS[@]}" -gt 0 ] && [ ! -x "$WATCH" ]; then
  echo "ERROR: $WATCH not found or not executable (pr_watch_many.sh wraps it)" >&2
  exit 5
fi
command -v gh >/dev/null 2>&1 || { echo "pr_watch_many: gh not found" >&2; exit 5; }
command -v jq >/dev/null 2>&1 || { echo "pr_watch_many: jq not found" >&2; exit 5; }

OUT="$(mktemp -d)"
PIDS=()
cleanup() {
  rm -rf "$OUT"
  local p
  for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done
}
trap cleanup EXIT

pr_key() { printf '%s_%s' "$1" "$2" | tr -c 'A-Za-z0-9_' '_'; }
label_for() { case "$1" in 0) echo MERGED ;; 2) echo BLOCKED ;; 3) echo CLOSED ;; 4) echo TIMEOUT ;; *) echo ERROR ;; esac; }
report_pr() { # report_pr <result-file>
  local code repo pr
  IFS='|' read -r code repo pr < "$1"
  printf 'TERMINAL %s (exit %s) %s#%s\n' "$(label_for "$code")" "$code" "$repo" "$pr"
}

# Newest COMPLETED <validator> run on a repo, as "id|conclusion|branch|updatedAt"
# or "" when there is none. gh's own --jq takes no --arg, so pipe to jq.
run_latest() {
  gh run list -R "$1" --limit 30 \
    --json databaseId,name,status,conclusion,headBranch,updatedAt 2>/dev/null \
    | jq -r --arg n "$VALIDATOR" '
        [.[] | select(.name==$n and .status=="completed")][0]
        | if .==null then "" else "\(.databaseId)|\(.conclusion)|\(.headBranch)|\(.updatedAt)" end' 2>/dev/null
}

# --- seed the validator baseline so signal 1 never fires on PRE-EXISTING state -
declare -A RUN_LAST
for r in "${REPOS[@]}"; do RUN_LAST[$r]="$(run_latest "$r")"; done

# --- spawn one sanctioned per-PR terminal watcher (signal 0) -------------------
# Each watcher writes its outcome to a hidden tmp file and RENAMES it to "<key>.done",
# so a completed result is published atomically and the main loop can glob
# "*.done" without ever seeing a half-written file. There is NO sleep after any
# wait and no timing window: a ".done" file's presence IS a complete result.
result_path() { printf '%s/%s.done' "$OUT" "$(pr_key "$1" "$2")"; }
if [ "${#PAIRS[@]}" -gt 0 ]; then
  i=0
  while [ "$i" -lt "${#PAIRS[@]}" ]; do
    repo="${PAIRS[$i]}"; pr="${PAIRS[$((i+1))]}"; i=$((i+2))
    rp="$(result_path "$repo" "$pr")"
    ( "$WATCH" "$repo" "$pr" --interval "$INTERVAL" --timeout "$TIMEOUT" >/dev/null 2>&1
      code=$?
      printf '%s|%s|%s\n' "$code" "$repo" "$pr" > "$rp.tmp"
      mv "$rp.tmp" "$rp" ) &
    PIDS+=($!)
  done
fi

# --- --all: wait for EVERY PR, report together (signals 1-2 inactive) ----------
if [ "$WAIT_ALL" -eq 1 ]; then
  wait
  for f in "$OUT"/*.done; do [ -e "$f" ] && report_pr "$f"; done
  exit 0
fi

any_pr_alive() {
  local p
  for p in "${PIDS[@]}"; do kill -0 "$p" 2>/dev/null && return 0; done
  return 1
}

# --- default: first wake wins across the three signals -------------------------
start="$(date +%s)"
last_verdict="$start"
while :; do
  # signal 0 — a PR reached a terminal state (atomic "<key>.done" file present)
  for f in "$OUT"/*.done; do [ -e "$f" ] && { report_pr "$f"; exit 0; }; done

  # signal 1 — a new validator run COMPLETED on any watched repo
  for r in "${REPOS[@]}"; do
    cur="$(run_latest "$r")"
    if [ -n "$cur" ] && [ "$cur" != "${RUN_LAST[$r]:-}" ]; then
      RUN_LAST[$r]="$cur"
      last_verdict="$(date +%s)"
      printf 'WAKE VERDICT  %s  %s  https://github.com/%s/actions/runs/%s\n' \
        "$r" "${cur#*|}" "$r" "${cur%%|*}"
      exit 0
    fi
  done

  now="$(date +%s)"

  # signal 2 — no new verdict within the window while scopes remain open+unmerged
  if [ "$STALLMIN" -gt 0 ] && [ "${#PAIRS[@]}" -gt 0 ] && any_pr_alive; then
    if [ $(( (now - last_verdict) / 60 )) -ge "$STALLMIN" ]; then
      printf 'WAKE STALL  no new %s verdict for >=%sm while PR scopes remain open+unmerged:\n' \
        "$VALIDATOR" "$STALLMIN"
      j=0
      while [ "$j" -lt "${#PAIRS[@]}" ]; do
        repo="${PAIRS[$j]}"; pr="${PAIRS[$((j+1))]}"; j=$((j+2))
        [ -e "$(result_path "$repo" "$pr")" ] || printf '  open: %s#%s\n' "$repo" "$pr"
      done
      exit 0
    fi
  fi

  # overall deadline
  if [ "$TIMEOUT" -gt 0 ] && [ $(( now - start )) -ge "$TIMEOUT" ]; then
    printf 'WAKE TIMEOUT  no signal within %ss\n' "$TIMEOUT"
    exit 4
  fi

  sleep "$INTERVAL"
done
