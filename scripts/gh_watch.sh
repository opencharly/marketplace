#!/usr/bin/env bash
# gh_watch.sh — watch a list of GitHub PRs and/or issues and wake ONCE, the moment a
# chosen EVENT fires. The harness notifies the caller when this background command
# finishes, so exiting IS the notification. Re-arm after each wake.
#
# Fully generic: no org, repo, session, or date is baked in — everything is env/args.
# Use it for anything you are waiting on: a PR that BLOCKS you (wake when it merges),
# a PR you might take over (wake on a stall), or an issue you commented on (wake when
# anyone replies).
#
# EVENTS (=comma list, default "merged,closed,stall"):
#   merged   a PR is MERGED  → you are UNBLOCKED              [state — fires if already so]
#   closed   an item is CLOSED without merging → find its successor
#   stall    SILENCE ALARM: NO progress for $STALL_MIN minutes while the item is still
#            open+unmerged → a TAKEOVER candidate (comment FIRST, wait the window,
#            then TAKING OVER — authority: window-expired, BEFORE any push)
#   verdict  a NEW $WF workflow run COMPLETED in its repo     [delta — seeded; opt-in]
#   comment  a NEW comment/review appeared on the item        [delta — seeded; opt-in]
#
# DESIGN REQUIREMENTS (not options):
#   1. SILENCE IS AN ALARM. A blocked item emits NO events, so an event-only watcher is
#      blind to the worst case. `stall` is therefore ON BY DEFAULT and every item gets
#      it. The events tell you when something HAPPENED; the stall alarm tells you when
#      something SHOULD have and did not.
#   2. WATCH THE OUTCOME, NOT EVERY EVENT. Waking on every comment of an actively
#      iterating owner is noise, so the DEFAULT set is the terminal outcomes
#      (merged,closed) plus the stall alarm. Add `comment`/`verdict` ONLY for a wait
#      that genuinely needs them — e.g. EVENTS=comment on an issue you asked a question
#      on and want the moment anyone replies.
#   3. LIVENESS IS NOT PROGRESS. Progress is judged by ARTIFACTS — a pushed branch, a
#      new commit, a new comment, a completed run, a merged tag — never by a session
#      heartbeat or "still investigating". The stall alarm keys on the item's
#      updated_at, so its silence is measured against artifacts, not activity.
#
# comment/verdict are DELTA events: the seed records the current count/run id at start, so
# a pre-existing comment or verdict never causes a false wake. merged/closed/stall are
# STATE events: they fire while the item IS in that state, including at arm time — that is
# why arming EVENTS=merged on an already-merged PR wakes immediately.
#
# USAGE
#   gh_watch.sh [OPTIONS] <item> [<item> ...]
# where each <item> is `owner/repo#num`, `owner/repo/pull/num`, `owner/repo/issues/num`,
# or a full `https://github.com/owner/repo/(pull|issues)/num` URL.
#
# OPTIONS / ENV
#   --events LIST     comma list from the set above   (env EVENTS,   default merged,closed,stall)
#   --interval SEC    poll cadence, seconds           (env INTERVAL, default 30; >= 1)
#   --stallmin MIN    stall window, minutes           (env STALL_MIN, default 60; >= 0)
#   --workflow NAME   validator run name              (env WF,       default charly/pr-validator)
#   --timeout SEC     overall deadline; 0 = none      (env TIMEOUT,  default 0)
#   -h, --help        print this help and exit 0
#
# OUTPUT (stdout; the line's first token is the event)
#   MERGED   <item>  (unblocked)
#   CLOSED   <item>  closed without merging — find its successor
#   COMMENT  <item>  new comment (<before> -> <after>)  <url>
#   VERDICT  <item>  new <WF> run <id>  <url>
#   STALL    <item>  no progress for <MIN>m (open, unmerged) — takeover candidate
#   TIMEOUT  no event within <SEC>s                      (only with --timeout > 0)
#
# EXIT  0 on an event; 4 on timeout; 5 on usage/argument/gh error.
# A watcher must never die silently: like pr_watch_many.sh, poll WITHOUT `-e` (a
# transient `gh` failure must skip this poll, not kill the watch) and keep `-uo pipefail`.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/_watch_common.sh
. "$SELF_DIR/_watch_common.sh"

INTERVAL="${INTERVAL:-30}"
STALL_MIN="${STALL_MIN:-60}"
EVENTS="${EVENTS:-merged,closed,stall}"
WF="${WF:-charly/pr-validator}"
TIMEOUT="${TIMEOUT:-0}"
ITEMS=()

usage() { watch_usage "${BASH_SOURCE[0]}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --events)   EVENTS="${2:?--events needs a value}"; shift 2 ;;
    --interval) INTERVAL="${2:?--interval needs a value}"; shift 2 ;;
    --stallmin) STALL_MIN="${2:?--stallmin needs a value}"; shift 2 ;;
    --workflow) WF="${2:?--workflow needs a value}"; shift 2 ;;
    --timeout)  TIMEOUT="${2:?--timeout needs a value}"; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    -*)         echo "gh_watch: unknown flag $1" >&2; usage >&2; exit 5 ;;
    *)          ITEMS+=("$1"); shift ;;
  esac
done

numeric() { watch_is_uint "$1"; }
numeric "$INTERVAL" && [ "$INTERVAL" -ge 1 ] || { echo "gh_watch: --interval must be an integer >= 1, got '$INTERVAL'" >&2; exit 5; }
numeric "$STALL_MIN" || { echo "gh_watch: --stallmin must be an integer >= 0, got '$STALL_MIN'" >&2; exit 5; }
numeric "$TIMEOUT" || { echo "gh_watch: --timeout must be an integer >= 0, got '$TIMEOUT'" >&2; exit 5; }
[ "${#ITEMS[@]}" -gt 0 ] || { echo "gh_watch: no items — pass one or more owner/repo#num (or --help)" >&2; exit 5; }
command -v gh >/dev/null 2>&1 || { echo "gh_watch: gh not found" >&2; exit 5; }
command -v jq >/dev/null 2>&1 || { echo "gh_watch: jq not found" >&2; exit 5; }

# Normalize ONE item to "owner/repo#num"; return 1 on anything malformed.
parse_item() {
  local s="$1" o r n
  s="${s#https://github.com/}"; s="${s#http://github.com/}"; s="${s#github.com/}"
  s="${s%%\?*}"
  case "$s" in
    */pull/*|*/issues/*)
      s="${s%%#*}"; s="${s%/}"
      o="${s%%/*}"; s="${s#*/}"; r="${s%%/*}"; s="${s#*/}"; n="${s##*/}"
      ;;
    */*"#"*)
      n="${s##*#}"; s="${s%%#*}"
      o="${s%%/*}"; r="${s#*/}"; r="${r%%/*}"
      ;;
    *) return 1 ;;
  esac
  [ -n "$o" ] && [ -n "$r" ] || return 1
  case "$n" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s/%s#%s' "$o" "$r" "$n"
}

NORM=()
for raw in "${ITEMS[@]}"; do
  if ! norm="$(parse_item "$raw")"; then
    echo "gh_watch: malformed item '$raw' — want owner/repo#123 or a GitHub PR/issue URL" >&2
    exit 5
  fi
  NORM+=("$norm")
done

has() { watch_has "$1" "$EVENTS"; }

# snapshot <owner> <repo> <num> -> "type|state|merged|comments|verdictId|updEpoch|verdictEpoch"
# Every gh call is guarded (|| echo …) AND the script polls without `-e`, so a transient
# failure skips a poll instead of killing the watcher.
snapshot() {
  local o="$1" r="$2" n="$3" type state merged cc run v ve up e
  if gh api "/repos/$o/$r/pulls/$n" >/dev/null 2>&1; then type=pr; else type=issue; fi
  state="$(gh api "/repos/$o/$r/issues/$n" --jq '.state' 2>/dev/null || echo unknown)"
  merged="$(gh api "/repos/$o/$r/pulls/$n" --jq '.merged' 2>/dev/null || echo "")"
  cc="$(gh api "/repos/$o/$r/issues/$n/comments" --paginate --jq 'length' 2>/dev/null || echo "")"
  run="$(watch_run_latest "$o/$r" "$WF" || echo "")"
  v="${run%%|*}"; ve="${run##*|}"
  [ "$run" = "$v" ] && ve=""          # no run at all (run was empty)
  up="$(gh api "/repos/$o/$r/issues/$n" --jq '.updated_at' 2>/dev/null || echo "")"
  if [ -n "$up" ]; then e="$(date -u -d "$up" +%s 2>/dev/null || date -u +%s)"; else e="$(date -u +%s)"; fi
  printf '%s|%s|%s|%s|%s|%s|%s' "$type" "$state" "$merged" "$cc" "$v" "$e" "$ve"
}

# A "new" event must be genuinely newer than ARM_EPOCH — never merely different from an
# empty seed, and never a pre-existing comment. An EMPTY seed is UNKNOWN (transient gh
# failure / no run yet), so an item with no seed adopts its first observation as the
# baseline WITHOUT firing. A `verdict` fires ONLY on a run that COMPLETED at/after
# ARM_EPOCH — an id compare alone is not enough (the newest completed run can change to
# a DIFFERENT but still-old run). merged/closed are STATE events and intentionally fire
# from the baseline.
ARM_EPOCH="$(date -u +%s)"
declare -A SEED
for tok in "${NORM[@]}"; do
  o="${tok%%/*}"; rest="${tok#*/}"; r="${rest%%#*}"; n="${tok##*#}"
  SEED[$tok]="$(snapshot "$o" "$r" "$n")"
done

start="$(date -u +%s)"
while :; do
  now="$(date -u +%s)"
  for tok in "${NORM[@]}"; do
    o="${tok%%/*}"; rest="${tok#*/}"; r="${rest%%#*}"; n="${tok##*#}"
    cur="$(snapshot "$o" "$r" "$n")"
    IFS='|' read -r type state merged cc v up ve <<<"$cur"
    IFS='|' read -r _ _ _ pcc pv _ _ <<<"${SEED[$tok]}"
    url="https://github.com/$o/$r"

    # merged/closed/comment/verdict all key on an exact per-FIELD value, so an UNKNOWN
    # field (empty from a transient failure) never fires: merged/closed need an exact
    # "true"/"closed"; comment needs both counts known; verdict needs a run that
    # COMPLETED at/after arm time. No whole-line "empty" guard is needed (snapshot
    # always prints).
    if has merged && [ "$merged" = "true" ]; then
      printf 'MERGED   %s  (unblocked)\n' "$tok"; exit 0; fi
    if has closed && [ "$state" = "closed" ] && [ "$merged" != "true" ]; then
      printf 'CLOSED   %s  closed without merging — find its successor\n' "$tok"; exit 0; fi
    if has comment && [ -n "$cc" ] && [ -n "$pcc" ] && [ "$cc" != "$pcc" ]; then
      printf 'COMMENT  %s  new comment (%s -> %s)  %s/%s/%s\n' \
        "$tok" "$pcc" "$cc" "$url" "$([ "$type" = pr ] && echo pull || echo issues)" "$n"; exit 0; fi
    if has verdict && [ -n "$v" ] && [ "$v" != "$pv" ] \
       && [ -n "$ve" ] && [ "$ve" -ge "$ARM_EPOCH" ]; then
      printf 'VERDICT  %s  new %s run %s  %s/actions/runs/%s\n' "$tok" "$WF" "$v" "$url" "$v"; exit 0; fi
    # stall requires an OBSERVED open state — never alarm on an unknown state.
    if has stall && [ "$merged" != "true" ] && [ "$state" != "closed" ] \
       && [ -n "$state" ] && [ "$state" != "unknown" ] \
       && [ $(( (now - up) / 60 )) -ge "$STALL_MIN" ]; then
      printf 'STALL    %s  no progress for %sm (open, unmerged) — takeover candidate\n' "$tok" "$STALL_MIN"; exit 0; fi

    SEED[$tok]="$cur"
  done

  if [ "$TIMEOUT" -gt 0 ] && [ $(( now - start )) -ge "$TIMEOUT" ]; then
    printf 'TIMEOUT  no event within %ss\n' "$TIMEOUT"; exit 4
  fi
  command sleep "$INTERVAL"
done
