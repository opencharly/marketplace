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
# EVENTS (=comma list, default "comment,verdict,merged,closed,stall"):
#   comment  a NEW comment/review appeared on the item        [delta — seeded]
#   verdict  a NEW $WF workflow run COMPLETED in its repo     [delta — seeded]
#   merged   a PR is MERGED  → you are UNBLOCKED              [state — fires if already so]
#   closed   an item is CLOSED without merging → find its successor
#   stall    NO progress for $STALL_MIN minutes while the item is still open
#            → a TAKEOVER candidate (comment FIRST, wait the window,
#              then TAKING OVER — authority: window-expired, BEFORE any push)
#
# Progress = a new comment, a new verdict, or a state change — NEVER session activity.
# comment/verdict are DELTA events: the seed records the current count/run id at start,
# so a pre-existing comment or verdict never causes a false wake. merged/closed/stall are
# STATE events: they fire while the item IS in that state, including at arm time — that
# is why arming EVENTS=merged on an already-merged PR wakes immediately.
#
# USAGE
#   gh_watch.sh [OPTIONS] <item> [<item> ...]
# where each <item> is `owner/repo#num`, `owner/repo/pull/num`, `owner/repo/issues/num`,
# or a full `https://github.com/owner/repo/(pull|issues)/num` URL.
#
# OPTIONS / ENV
#   --events LIST     comma list from the set above   (env EVENTS,   default all five)
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
set -euo pipefail

INTERVAL="${INTERVAL:-30}"
STALL_MIN="${STALL_MIN:-60}"
EVENTS="${EVENTS:-comment,verdict,merged,closed,stall}"
WF="${WF:-charly/pr-validator}"
TIMEOUT="${TIMEOUT:-0}"
ITEMS=()

usage() {
  awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

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

numeric() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
numeric "$INTERVAL" && [ "$INTERVAL" -ge 1 ] || { echo "gh_watch: --interval must be an integer >= 1, got '$INTERVAL'" >&2; exit 5; }
numeric "$STALL_MIN" || { echo "gh_watch: --stallmin must be an integer >= 0, got '$STALL_MIN'" >&2; exit 5; }
numeric "$TIMEOUT" || { echo "gh_watch: --timeout must be an integer >= 0, got '$TIMEOUT'" >&2; exit 5; }
[ "${#ITEMS[@]}" -gt 0 ] || { echo "gh_watch: no items — pass one or more owner/repo#num (or --help)" >&2; exit 5; }
command -v gh >/dev/null 2>&1 || { echo "gh_watch: gh not found" >&2; exit 5; }

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

has() { case ",$EVENTS," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

# snapshot <owner> <repo> <num> -> "type|state|merged|comments|verdict|updated_epoch"
snapshot() {
  local o="$1" r="$2" n="$3" type state merged cc v up e
  if gh api "/repos/$o/$r/pulls/$n" >/dev/null 2>&1; then type=pr; else type=issue; fi
  state="$(gh api "/repos/$o/$r/issues/$n" --jq '.state' 2>/dev/null || echo unknown)"
  merged="$(gh api "/repos/$o/$r/pulls/$n" --jq '.merged' 2>/dev/null || echo "")"
  cc="$(gh api "/repos/$o/$r/issues/$n/comments" --paginate --jq 'length' 2>/dev/null || echo 0)"
  v="$(gh run list -R "$o/$r" --limit 30 --json name,status,databaseId \
        --jq "[.[]|select(.name==\"$WF\" and .status==\"completed\")][0].databaseId // \"\"" 2>/dev/null || echo "")"
  up="$(gh api "/repos/$o/$r/issues/$n" --jq '.updated_at' 2>/dev/null || echo "")"
  if [ -n "$up" ]; then e="$(date -u -d "$up" +%s 2>/dev/null || date -u +%s)"; else e="$(date -u +%s)"; fi
  printf '%s|%s|%s|%s|%s|%s' "$type" "$state" "$merged" "$cc" "$v" "$e"
}

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
    if [ -z "$cur" ]; then continue; fi
    IFS='|' read -r type state merged cc v up <<<"$cur"
    IFS='|' read -r ptype pstate pmerged pcc pv pup <<<"${SEED[$tok]}"
    base="$o/$r"; url="https://github.com/$o/$r"

    if has merged && [ "$merged" = "true" ]; then
      printf 'MERGED   %s  (unblocked)\n' "$tok"; exit 0; fi
    if has closed && [ "$state" = "closed" ] && [ "$merged" != "true" ]; then
      printf 'CLOSED   %s  closed without merging — find its successor\n' "$tok"; exit 0; fi
    if has comment && [ "$cc" != "$pcc" ]; then
      printf 'COMMENT  %s  new comment (%s -> %s)  %s/%s/%s\n' \
        "$tok" "$pcc" "$cc" "$url" "$([ "$type" = pr ] && echo pull || echo issues)" "$n"; exit 0; fi
    if has verdict && [ -n "$v" ] && [ "$v" != "$pv" ]; then
      printf 'VERDICT  %s  new %s run %s  %s/actions/runs/%s\n' "$tok" "$WF" "$v" "$url" "$v"; exit 0; fi
    if has stall && [ $(( (now - up) / 60 )) -ge "$STALL_MIN" ]; then
      printf 'STALL    %s  no progress for %sm (open, unmerged) — takeover candidate\n' "$tok" "$STALL_MIN"; exit 0; fi

    SEED[$tok]="$cur"
  done

  if [ "$TIMEOUT" -gt 0 ] && [ $(( now - start )) -ge "$TIMEOUT" ]; then
    printf 'TIMEOUT  no event within %ss\n' "$TIMEOUT"; exit 4
  fi
  command sleep "$INTERVAL"
done
