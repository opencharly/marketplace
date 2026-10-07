#!/usr/bin/env bash
# pr_watch_many.sh — watch a cross-repo PR batch and wake ONCE, on the first of
# three signals. Fully generic: the repo set, poll interval, stall window, and
# validator workflow name are all configurable; no org, repo, session, or date is
# baked in.
#
# SELF-SUSTAINING LOOP — see the ONE canonical statement in `_watch_common.sh`
#   ("THE HARNESS CONSTRAINT", `--auto-rearm`, the single-instance lock, the rate-limit
#   discipline). This script carries only a pointer so the explanation lives ONCE.
#
# SIGNALS
#   0  PR TERMINAL  a watched PR reaches MERGED / BLOCKED / CLOSED, delegated to
#                   the sanctioned pr_state_watch.sh (so the POISON stuck state is
#                   reported distinctly from a real verdict BLOCK).
#   1  NEW VERDICT  a new `<validator>` run COMPLETES on any watched repo, and that
#                   run COMPLETED at/after arm time (a stale run never fires — see
#                   the arm-time gate below). This is the PROGRESS signal. Session
#                   activity is NOT progress: a looping agent never goes quiet, and a
#                   peer waiting on a running validator looks quiet but is working.
#                   REPO-SCOPED: it fires on ANY newer run in the watched repos,
#                   including another session's PR. To watch ONE PR, use gh_watch.sh
#                   on owner/repo#<n>.
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
#   --interval SEC    poll cadence, seconds (default 300; FLOOR 300 — sub-floor is
#                     refused, tests only via ALLOW_FAST_POLL=1).
#   --timeout SEC     overall deadline, seconds; 0 disables (default 7200).
#   --stallmin MIN    stall window, minutes; 0 disables signal 2 (default 0).
#   --validator NAME  validator workflow name (default charly/pr-validator).
#   --all             wait for EVERY PR to reach a terminal state, then report
#                     them together (signals 1-2 inactive in this mode).
#   --auto-rearm      keep the watch ALIVE: on a non-terminal fire, detach a
#                     lock-guarded successor with the SAME args (env AUTO_REARM=1).
#   --no-rearm        one-shot: exit on the fire, the agent re-arms (env AUTO_REARM=0).
#   -h, --help        print this help and exit 0.
#
# OUTPUT (stdout, one line per wake — the harness notifies on the script exiting)
#   TERMINAL <STATE> (exit <N>) <owner/repo>#<pr>   STATE in MERGED BLOCKED CLOSED
#   WAKE VERDICT  <repo>  <conclusion>|<branch>|<updatedAt>  https://github.com/<repo>/actions/runs/<id>
#   WAKE STALL  no new <validator> verdict for >=<MIN>m while PR scopes remain open+unmerged:
#     open: <owner/repo>#<pr>                        (one line per still-open scope)
#   WAKE TIMEOUT  no signal within <SEC>s
#
# EXIT  0 once a wake was reported (the scope's own status is in the output line);
#       4 on timeout; 5 on usage/error; 6 on lock error; 7 on a RATE LIMIT (a HARD
#       abort — never retried). Every per-PR terminal decision
#       is pr_state_watch.sh's (which defines 0 MERGED / 2 BLOCKED / 3 CLOSED /
#       4 TIMEOUT / 5 ERROR and distinguishes POISON).
#
# WHY NOT `gh pr checks --watch` / a hand-rolled loop: the sanctioned per-PR poll is
# pr_state_watch.sh (it sees POISON, which `gh pr checks` cannot), and this wrapper
# adds the two cross-repo progress layers a batch landing needs WITHOUT
# re-implementing any polling of its own.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCH="$SELF_DIR/pr_state_watch.sh"
# shellcheck source=scripts/_watch_common.sh
. "$SELF_DIR/_watch_common.sh"

ORIG_ARGS=("$@")
ARGV0="$SELF_DIR/$(basename "${BASH_SOURCE[0]}")"

INTERVAL=300
TIMEOUT=7200
STALLMIN=0
VALIDATOR="${PR_WATCH_VALIDATOR:-charly/pr-validator}"
WAIT_ALL=0
AUTO_REARM="${AUTO_REARM:-0}"
REPOS_ARG=""
PAIRS=()

# Print the leading comment block (shebang excluded) as the usage text — via the
# shared helper, so it can never drift out of range.
usage() { watch_usage "${BASH_SOURCE[0]}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --repos)      REPOS_ARG="${2:?--repos needs a comma-separated value}"; shift 2 ;;
    --interval)   INTERVAL="${2:?--interval needs a value}"; shift 2 ;;
    --timeout)    TIMEOUT="${2:?--timeout needs a value}"; shift 2 ;;
    --stallmin)   STALLMIN="${2:?--stallmin needs a value}"; shift 2 ;;
    --validator)  VALIDATOR="${2:?--validator needs a value}"; shift 2 ;;
    --all)        WAIT_ALL=1; shift ;;
    --auto-rearm) AUTO_REARM=1; shift ;;
    --no-rearm)   AUTO_REARM=0; shift ;;
    -h|--help)    usage; exit 0 ;;
    -*)           echo "pr_watch_many: unknown flag $1" >&2; usage >&2; exit 5 ;;
    *)            PAIRS+=("$1"); shift ;;
  esac
done

# --- validation (fail loud, never a silent default) ------------------------
# ONE poll per five minutes (POLL_FLOOR); sub-floor is refused unless ALLOW_FAST_POLL=1 (tests).
INTERVAL="$(watch_interval pr_watch_many "$INTERVAL" "--interval")" || exit 5
watch_is_uint "$TIMEOUT"  || { echo "pr_watch_many: --timeout must be an integer >= 0, got '$TIMEOUT'" >&2; exit 5; }
watch_is_uint "$STALLMIN" || { echo "pr_watch_many: --stallmin must be an integer >= 0, got '$STALLMIN'" >&2; exit 5; }
case "$AUTO_REARM" in 0|1) ;; *) echo "pr_watch_many: AUTO_REARM must be 0 or 1, got '$AUTO_REARM'" >&2; exit 5 ;; esac
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
command -v flock >/dev/null 2>&1 || { echo "pr_watch_many: flock not found (util-linux) — required for the single-instance lock" >&2; exit 6; }

OUT="$(mktemp -d)"
PIDS=()
cleanup() {
  rm -rf "$OUT"
  local p
  for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done
}

# --- single-instance lock (one watcher per identical invocation) ----------------
# A successor (WATCH_INHERITED_LOCK=1) INHERITS the predecessor's flock (atomic
# hand-off, it already holds the lock and never waits); a foreground arm TAKES OVER a
# live peer. The policy lives ONCE in `watch_lock_or_exit`.
watch_lock_or_exit "$ARGV0" "pr_watch_many" "${ORIG_ARGS[@]}"
watch_set_rearm "$AUTO_REARM" "$ARGV0" "${ORIG_ARGS[@]}"
# Capture $? FIRST: in `trap 'a; b $?'` the `$?` expands AFTER `a` runs, so it would be
# cleanup's status, never the script's real exit code — the guard for 5/6/143 would then
# never fire and a takeover (143) would wrongly re-arm.
trap 'rc=$?; cleanup; watch_on_exit_common "$rc"' EXIT
trap 'exit 143' TERM INT

pr_key() { printf '%s_%s' "$1" "$2" | tr -c 'A-Za-z0-9_' '_'; }
label_for() { case "$1" in 0) echo MERGED ;; 2) echo BLOCKED ;; 3) echo CLOSED ;; 4) echo TIMEOUT ;; *) echo ERROR ;; esac; }
report_pr() { # report_pr <result-file>
  local code repo pr
  IFS='|' read -r code repo pr < "$1"
  printf 'TERMINAL %s (exit %s) %s#%s\n' "$(label_for "$code")" "$code" "$repo" "$pr"
}

# Newest COMPLETED <validator> run on a repo (shared helper; see _watch_common.sh).
run_latest() { watch_run_latest "$1" "$VALIDATOR"; }

# --- seed the validator baseline so signal 1 never fires on PRE-EXISTING state -
# An EMPTY seed means UNKNOWN (no completed run yet, or a transient gh failure),
# NOT "no prior run". The PRIMARY newness gate is the run's COMPLETION epoch:
# signal 1 fires only on a run that COMPLETED at or after arm time. (Id compare is
# a secondary guard against re-reporting the SAME run.)
declare -A RUN_LAST
ARM_EPOCH="$(date +%s)"
for r in "${REPOS[@]}"; do
  seed="$(run_latest "$r")"; src_s=$?
  watch_rc_guard "$src_s"           # a rate-limit abort inside the subshell ends us too
  RUN_LAST[$r]="${seed%%|*}"        # run id only; "" means UNKNOWN, not "none yet"
done

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
    # 9>&- is ESSENTIAL: the per-PR watcher is LONG-LIVED — if it inherited our flock fd
    # (fd 9) it would hold the lock after we exit, blocking our successor.
    #
    # The watcher runs in the BACKGROUND of the subshell, not the foreground, so the subshell
    # can WAIT on it and FORWARD our teardown signal. Without the forward, cleanup() kills the
    # subshell and the watcher — its CHILD — survives as an orphan reparented to systemd
    # --user: the pid recorded in PIDS is the subshell's, `wait` waits on subshells, and no
    # exit path of this script (the first-wake exit, the --all exit, the timeout exit, the
    # TERM/INT trap) ever reaches the watcher. Measured, twice, on the same PR
    # (opencharly/marketplace#417). The forward also makes the pid in PIDS the correct
    # LIVENESS proxy: the subshell is alive exactly while its watcher runs, which is what
    # any_pr_alive asserts.
    ( "$WATCH" "$repo" "$pr" --interval "$INTERVAL" --timeout "$TIMEOUT" >/dev/null 2>&1 &
      wp=$!
      # TERM carries teardown (our INT path re-raises as `exit 143`, so cleanup always sends
      # TERM); INT is set alongside it for the direct-signal case.
      trap 'kill "$wp" 2>/dev/null; exit 143' TERM INT
      wait "$wp"
      code=$?
      printf '%s|%s|%s\n' "$code" "$repo" "$pr" > "$rp.tmp"
      mv "$rp.tmp" "$rp" ) 9>&- &
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
  # OVERALL DEADLINE FIRST — checked before the rate gate so a rate-limit backoff can
  # never starve the timeout (a `continue` past a bottom-of-loop check would).
  if [ "$TIMEOUT" -gt 0 ] && [ $(( $(date +%s) - start )) -ge "$TIMEOUT" ]; then
    printf 'WAKE TIMEOUT  no signal within %ss\n' "$TIMEOUT"; exit 4
  fi
  # RATE-LIMIT DISCIPLINE: never poll when the core quota is nearly exhausted; a
  # genuine EXHAUSTION aborts via watch_rate_gate (exit 7), never a silent retry.
  watch_rate_gate "$INTERVAL" "pr_watch_many" || continue

  # signal 0 — a PR reached a terminal state (atomic "<key>.done" file present).
  # TERMINAL: nothing is left to watch, so set WATCH_DONE (no successor is spawned).
  for f in "$OUT"/*.done; do [ -e "$f" ] && { WATCH_DONE=1; report_pr "$f"; exit 0; }; done

  # signal 1 — a new validator run COMPLETED on any watched repo.
  # PRIMARY gate: the run must have COMPLETED at/after arm time. An id compare alone
  # is NOT enough — the "newest completed" run can change to a DIFFERENT but still-old
  # run (a seed/poll ordering shift or a transient seed failure) and would false-fire.
  # DELTA fire: re-arm a successor BEFORE printing+exiting, so a watch stays alive.
  # `watch_rearm_now` is the ORDERING guarantee (successor ALIVE before the wake). The
  # EXIT trap re-arms as a BACKSTOP for any path that did not reach here, so the two
  # both spawn a successor here and the `WATCH_REARMED` latch de-dupes them — the
  # committed `... re-arms BEFORE printing the WAKE` assertion pins this ordering.
  for r in "${REPOS[@]}"; do
    cur="$(run_latest "$r")"; crc=$?
    watch_rc_guard "$crc"           # a rate-limit abort inside the subshell ends us too
    if [ -n "$cur" ]; then
      cid="${cur%%|*}"; cepoch="${cur##*|}"
      prev="${RUN_LAST[$r]:-}"
      if [ "$cid" != "$prev" ]; then
        if [ -n "$cepoch" ] && [ "$cepoch" -ge "$ARM_EPOCH" ]; then
          RUN_LAST[$r]="$cid"
          last_verdict="$(date +%s)"
          rest="${cur#*|}"; rest="${rest%|*}"   # conclusion|branch|updatedAt (drop epoch)
          watch_rearm_now
          printf 'WAKE VERDICT  %s  %s  https://github.com/%s/actions/runs/%s\n' \
            "$r" "$rest" "$r" "$cid"
          exit 0
        fi
        RUN_LAST[$r]="$cid"   # stale run (completed before arm) → adopt as baseline, no fire
      fi
    fi
  done

  now="$(date +%s)"

  # signal 2 — no new verdict within the window while scopes remain open+unmerged.
  # STATE fire: the item is still stalled, so a successor would immediately re-fire it
  # → WATCH_DONE=1 (no re-arm; the agent acts and re-arms with a fresh window).
  if [ "$STALLMIN" -gt 0 ] && [ "${#PAIRS[@]}" -gt 0 ] && any_pr_alive; then
    if [ $(( (now - last_verdict) / 60 )) -ge "$STALLMIN" ]; then
      WATCH_DONE=1
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

  watch_sleep "$INTERVAL"
done
