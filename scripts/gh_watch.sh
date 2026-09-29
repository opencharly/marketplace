#!/usr/bin/env bash
# gh_watch.sh — watch a list of GitHub PRs and/or issues and wake ONCE, the moment a
# chosen EVENT fires. The harness notifies the caller when this background command
# finishes, so exiting IS the notification.
#
# SELF-SUSTAINING LOOP — see the ONE canonical statement in `_watch_common.sh`
#   ("THE HARNESS CONSTRAINT", `--auto-rearm`, the single-instance lock, the rate-limit
#   discipline). This script carries only a pointer so the explanation lives ONCE.
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
#   4. A WATCH MUST NEVER BE DROPPED. `--auto-rearm` keeps one alive across fires.
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
#   --interval SEC    poll cadence, seconds           (env INTERVAL, default 60; FLOOR 60)
#   --stallmin MIN    stall window, minutes           (env STALL_MIN, default 60; >= 0)
#   --workflow NAME   validator run name              (env WF,       default charly/pr-validator)
#   --timeout SEC     overall deadline; 0 = none      (env TIMEOUT,  default 0)
#   --auto-rearm      keep the watch ALIVE: on exit, detach a lock-guarded successor
#                     with the SAME args (env AUTO_REARM=1)
#   --no-rearm        one-shot: exit on the event, the agent re-arms (env AUTO_REARM=0)
#   -h, --help        print this help and exit 0
#
# ONE WATCHER PER SESSION, ONE POLL PER MINUTE. --interval is a FLOOR of 60 seconds
#   (POLL_FLOOR): a sub-60s value is REFUSED at parse time (exit 5), so no silent
#   sub-floor polling ever ships. Tests that must run fast opt in explicitly with
#   ALLOW_FAST_POLL=1 (and --interval < 60); it is never a production setting.
#
# WHY THE FLOOR — the measured budget. MEASURED 2026-09-28: the account's shared core
#   budget is 5000 calls/hr. This script's snapshot() issued 6 REST calls PER ITEM PER
#   POLL and over 5 items that is 30 calls/poll: at its own old 30s default (2 polls/
#   min) 3600/hr (72% of the budget for ONE watcher), and at a then-reachable 20s
#   cadence 5400/hr (OVER budget). Repeated fast/stacked polls produced HTTP 403s.
#   Now: the default is 60s, and the WHOLE item list is polled in ONE GraphQL request
#   (see the batched-poll comment) — MEASURED at 6 items, seed + poll: 3 gh
#   invocations (2 GraphQL + 1 FREE /rate_limit). The billable constant is ONE
#   request per poll for N items, so a 60s watch is ~60 requests/hr regardless of N.
#
# RATE-LIMIT GUARD. Before each poll the FREE `/rate_limit` endpoint is read; below
#   WATCH_RATE_MIN (default 200) the watcher backs off (interval × WATCH_RATE_BACKOFF_FACTOR,
#   default 2, capped 600s) and SKIPS the poll rather than hammering into the 403 wall.
#
# OUTPUT (stdout; the line's first token is the event)
#   MERGED   <item>  (unblocked)
#   CLOSED   <item>  closed without merging — find its successor
#   COMMENT  <item>  new comment (<before> -> <after>)  <url>
#   VERDICT  <item>  new <WF> run <id>  <url>
#   STALL    <item>  no progress for <MIN>m (open, unmerged) — takeover candidate
#   TIMEOUT  no event within <SEC>s                      (only with --timeout > 0)
#   FATAL    a rate limit was hit — ABORT (stderr), exit 7; never retried/still-polled
#
# EXIT  0 on an event; 4 on timeout; 5 on usage/argument (incl. a sub-floor interval);
#       6 on lock error; 7 on a RATE LIMIT (a HARD abort — never retried); 8 on a poll
#       error other than a rate limit.
# A watcher must never die silently: like pr_watch_many.sh, poll WITHOUT `-e` (a
# transient `gh` failure must skip this poll, not kill the watch) and keep `-uo pipefail`.
# A RATE LIMIT is the ONE exception to "skip the poll": it is a STOP, so it exits 7.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/_watch_common.sh
. "$SELF_DIR/_watch_common.sh"

ORIG_ARGS=("$@")
ARGV0="$SELF_DIR/$(basename "${BASH_SOURCE[0]}")"

INTERVAL="${INTERVAL:-60}"
STALL_MIN="${STALL_MIN:-60}"
EVENTS="${EVENTS:-merged,closed,stall}"
WF="${WF:-charly/pr-validator}"
TIMEOUT="${TIMEOUT:-0}"
AUTO_REARM="${AUTO_REARM:-0}"
ITEMS=()

usage() { watch_usage "${BASH_SOURCE[0]}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --events)     EVENTS="${2:?--events needs a value}"; shift 2 ;;
    --interval)   INTERVAL="${2:?--interval needs a value}"; shift 2 ;;
    --stallmin)   STALL_MIN="${2:?--stallmin needs a value}"; shift 2 ;;
    --workflow)   WF="${2:?--workflow needs a value}"; shift 2 ;;
    --timeout)    TIMEOUT="${2:?--timeout needs a value}"; shift 2 ;;
    --auto-rearm) AUTO_REARM=1; shift ;;
    --no-rearm)   AUTO_REARM=0; shift ;;
    -h|--help)    usage; exit 0 ;;
    -*)           echo "gh_watch: unknown flag $1" >&2; usage >&2; exit 5 ;;
    *)            ITEMS+=("$1"); shift ;;
  esac
done

numeric() { watch_is_uint "$1"; }
# ONE poll per minute (POLL_FLOOR); sub-floor is refused unless ALLOW_FAST_POLL=1 (tests).
INTERVAL="$(watch_interval gh_watch "$INTERVAL" "the INTERVAL env/default")" || exit 5
numeric "$STALL_MIN" || { echo "gh_watch: --stallmin must be an integer >= 0, got '$STALL_MIN'" >&2; exit 5; }
numeric "$TIMEOUT" || { echo "gh_watch: --timeout must be an integer >= 0, got '$TIMEOUT'" >&2; exit 5; }
case "$AUTO_REARM" in 0|1) ;; *) echo "gh_watch: AUTO_REARM must be 0 or 1, got '$AUTO_REARM'" >&2; exit 5 ;; esac
[ "${#ITEMS[@]}" -gt 0 ] || { echo "gh_watch: no items — pass one or more owner/repo#num (or --help)" >&2; exit 5; }
command -v gh >/dev/null 2>&1 || { echo "gh_watch: gh not found" >&2; exit 5; }
command -v jq >/dev/null 2>&1 || { echo "gh_watch: jq not found" >&2; exit 5; }
command -v flock >/dev/null 2>&1 || { echo "gh_watch: flock not found (util-linux) — required for the single-instance lock" >&2; exit 6; }

# --- single-instance lock (one watcher per identical invocation) ----------------
# A successor (WATCH_INHERITED_LOCK=1) INHERITS the predecessor's flock (atomic
# hand-off, it already holds the lock and never waits); a foreground arm TAKES OVER a
# live peer. The policy lives ONCE in `watch_lock_or_exit`.
watch_lock_or_exit "$ARGV0" "gh_watch" "${ORIG_ARGS[@]}"
watch_install_trap "$AUTO_REARM" "$ARGV0" "${ORIG_ARGS[@]}"

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

# ── ONE batched GraphQL poll (calls-per-poll = 1 for N items) ────────────────
# MEASURED 2026-09-28: the previous per-item REST snapshot issued 6 calls per item
# per poll (a `/pulls` type probe, `/issues` state, `/pulls` merged,
# `/issues/comments`, a per-item `gh run list`, and `/issues` updated_at). Over 5
# items that is 30 calls/poll: 3600/hr at this script's own old 30s default (72% of
# the shared 5000/hr budget for ONE watcher), 5400/hr at a reachable 20s cadence
# (over budget). Repeated fast/stacked polls produced the observed HTTP 403.
#
# This replaces it with ONE GraphQL request per poll, regardless of item count:
# `issueOrPullRequest(number:)` serves BOTH PRs and issues, so a whole batch is a
# single aliased query. `state`, `merged`, `updatedAt`, `comments.totalCount` and the
# head commit's latest check-suites (for the `verdict` event) all arrive in that one
# round-trip. GraphQL counts as ONE request against the budget (not per-node), so
# N items cost exactly 1 call per poll.
#
# SKIP UNCHANGED WORK: a per-item fingerprint of
# `updatedAt|headOid|newestCompletedRunId` gates the event checks — an idempotent
# no-change poll returns a fingerprint equal to the seed and is skipped before any
# event logic (the poll itself is not skipped; it is the SINGLE batched call that
# keeps the watch honest). The check-suite walk (candidate run ids) is only consulted
# for an item whose fingerprint moved.
#
# RATE-LIMIT HARD ABORT: any rate-limit signal — HTTP 403/429, an `errors[].type ==
# RATE_LIMIT` body, or a zero/absent quota — is a STOP, not a retry. `graphql_batch`
# exits 7 via `watch_fatal_rate_limit` (naming the reset instant). MEASURED trap:
# `gh api graphql` exits 0 while its body carries the RATE_LIMIT error, so the payload
# is inspected, never the exit code alone.

# gql_alias is defined in _watch_common.sh (shared with the test fixtures).

# graphql_batch → prints the raw JSON on stdout; on a rate-limit signal it prints the
# signal to stderr and exits 7 (the poll loop aborts). Any other failure exits 8 (a
# genuine poll error the caller treats as a skipped poll, not a fire).
graphql_batch() {
  { exec 9>&-; } 2>/dev/null || true
  local sel="" q out alias
  for tok in "${NORM[@]}"; do
    o="${tok%%/*}"; rest="${tok#*/}"; r="${rest%%#*}"; n="${tok##*#}"
    # GraphQL alias names allow only [A-Za-z0-9_]; sanitize owner/repo/number to that
    # set (a hyphen in a repo name would otherwise make the query invalid). gql_parse
    # derives the SAME key from the token, so the two must sanitize identically.
    alias="$(gql_alias "$tok")"
    # NOTE the shape (MEASURED): `conclusion`/`updatedAt` live on the CheckSuite, NOT
    # on `workflowRun`; the run id and workflow NAME live under `workflowRun`.
    sel+=" $alias: repository(owner: \"$o\", name: \"$r\") { issueOrPullRequest(number: $n) { __typename ... on Issue { state updatedAt comments { totalCount } } ... on PullRequest { state merged updatedAt comments { totalCount } headRefOid commits(last: 1) { nodes { commit { checkSuites(last: 5) { nodes { conclusion updatedAt workflowRun { databaseId workflow { name } } } } } } } } } }"
  done
  q="query { ${sel} }"
  out="$(gh api graphql -f "query=$q" 2>&1)"; rc=$?
  if watch_is_rate_limited "$out"; then
    watch_fatal_rate_limit "gh_watch" "$(printf '%s' "$out" | head -c 200)"
  fi
  [ "$rc" -eq 0 ] || { printf 'gh_watch: graphql poll failed (%s): %s\n' "$rc" "$(printf '%s' "$out" | head -c 200)" >&2; exit 8; }
  printf '%s' "$out"
}

# gql_parse <json> <tok> — one item's fingerprint line
#   "type|state|merged|comments|headOid|updEpoch|newestRunId|newestRunConclusion|newestRunEpoch"
# Missing/null fields become empty so the caller's exact-value gates never fire on an
# unknown. `updEpoch` is the item's updatedAt as Unix seconds.
gql_parse() {
  printf '%s' "$1" | jq -r --arg tok "$2" --arg wf "$WF" --arg alias "$(gql_alias "$2")" '
    .data[$alias] as $r
    | ($r.issueOrPullRequest // null) as $i
    | if $i == null then "unknown|||0|||"
      else
        ($i.__typename) as $t
        | (if $t == "PullRequest" then "pr" else "issue" end) as $ty
        # GraphQL state is an uppercase enum (OPEN/CLOSED/MERGED); the event checks
        # compare lowercase, so normalize here (the ONE place the raw state is read).
        | ($i.state | ascii_downcase) as $st
        | ($i.comments.totalCount // 0) as $c
        | (($i.updatedAt // "") | if . == "" then 0 else (fromdateiso8601) end) as $u
        | (if $t == "PullRequest" then
             # conclusion/updatedAt are on the CheckSuite; databaseId + workflow.name
             # are under workflowRun (MEASURED shape).
             ([ $i.commits.nodes[]?.commit.checkSuites.nodes[]?
                | select(.workflowRun.workflow.name == $wf and .conclusion != null) ]
              | sort_by(.workflowRun.databaseId) | last) as $cs
             | ($cs.workflowRun.databaseId // "") as $rid
             | ($cs.conclusion // "") as $rc
             | (($cs.updatedAt // "") | if . == "" then 0 else (fromdateiso8601) end) as $re
             | "\($ty)|\($st)|\($i.merged)|\($c)|\($i.headRefOid // "")|\($u)|\($rid)|\($rc)|\($re)"
           else
             "\($ty)|\($st)||\($c)||\($u)|||"
           end)
      end' 2>/dev/null
}

# probe_run_id <owner/repo> <candidate-id> — the item-scoped validator-run probe used
# ONLY when a fingerprint moved. The head check-suite gave a CANDIDATE run id; this
# reads that run's own completion time via the REST `actions/runs/{id}` endpoint (ONE
# REST core call — a normal REST read, not the GraphQL points budget). NB: `gh run
# view` is NOT usable here — MEASURED: it 404s on a GraphQL `workflowRun.databaseId`
# (it resolves a different run numbering), so this calls the REST endpoint directly.
# Returns "id|conclusion|completedEpoch" or "" (unknown).
probe_run_id() {
  { exec 9>&-; } 2>/dev/null || true
  local out rc
  out="$(gh api "repos/$1/actions/runs/$2" 2>&1)"; rc=$?
  if watch_is_rate_limited "$out"; then
    watch_fatal_rate_limit "gh_watch" "$(printf '%s' "$out" | head -c 200)"
  fi
  [ "$rc" -eq 0 ] || return 0
  printf '%s' "$out" \
    | jq -r 'if .id == null then "" else "\(.id)|\(.conclusion // "")|\(.updated_at | fromdateiso8601)" end' 2>/dev/null
}

# A "new" event must be genuinely newer than ARM_EPOCH — never merely different from an
# empty seed, and never a pre-existing comment. An EMPTY seed is UNKNOWN (transient gh
# failure / no run yet), so an item with no seed adopts its first observation as the
# baseline WITHOUT firing. A `verdict` fires ONLY on its run COMPLETING at/after
# ARM_EPOCH (the field-validated newness gate). merged/closed are STATE events and
# intentionally fire from the baseline.
ARM_EPOCH="$(date -u +%s)"
declare -A SEED
declare -A CAND_RUN

seed_batch() {
  local batch rc
  batch="$(graphql_batch)"; rc=$?
  watch_rc_guard "$rc"          # a rate-limit abort inside the subshell ends us too
  [ "$rc" -eq 0 ] || return 1   # any other poll error: seed failed
  for tok in "${NORM[@]}"; do
    SEED[$tok]="$(gql_parse "$batch" "$tok")" || SEED[$tok]="unknown|||0|||"
    IFS='|' read -r _ _ _ _ _ _ v _ _ <<<"${SEED[$tok]}"
    CAND_RUN[$tok]="$v"
  done
}
seed_batch || { echo "gh_watch: initial GraphQL seed failed" >&2; exit 8; }

start="$(date -u +%s)"
while :; do
  # OVERALL DEADLINE FIRST — checked before the rate gate so a rate-limit backoff can
  # never starve the timeout (a `continue` past a bottom-of-loop check would).
  if [ "$TIMEOUT" -gt 0 ] && [ $(( $(date -u +%s) - start )) -ge "$TIMEOUT" ]; then
    printf 'TIMEOUT  no event within %ss\n' "$TIMEOUT"; exit 4
  fi
  # RATE-LIMIT DISCIPLINE: never poll when the core quota is nearly exhausted; a
  # genuine EXHAUSTION aborts (exit 7) rather than sleeping into the 403 wall.
  watch_rate_gate "$INTERVAL" "gh_watch" || continue

  # ONE batched GraphQL request for the WHOLE item list (calls-per-poll = 1).
  batch="$(graphql_batch)"; grc=$?
  watch_rc_guard "$grc"                                                 # rate limit → abort 7
  [ "$grc" -eq 0 ] || { watch_sleep "$INTERVAL"; continue; }            # poll error → skip
  now="$(date -u +%s)"

  for tok in "${NORM[@]}"; do
    o="${tok%%/*}"; rest="${tok#*/}"; r="${rest%%#*}"; n="${tok##*#}"
    cur="$(gql_parse "$batch" "$tok")"
    IFS='|' read -r type state merged cc head up v rc ve <<<"$cur"
    IFS='|' read -r ptype pstate pmerged pcc phead pup pv prc pve <<<"${SEED[$tok]}"
    url="https://github.com/$o/$r"

    # SKIP UNCHANGED WORK applies ONLY to the DELTA events (comment/verdict): STATE
    # events (merged/closed/stall) fire from the BASELINE by design, so they can never
    # be skipped. An unchanged fingerprint means an idle item costs nothing beyond the
    # single batched poll (the poll itself is never skipped).
    changed=0; [ "$cur" != "${SEED[$tok]}" ] && changed=1

    # merged/closed/comment/verdict all key on an exact per-FIELD value, so an UNKNOWN
    # field (empty from a failed poll) never fires: merged/closed need an exact
    # "true"/"closed"; comment needs both counts known; verdict needs a run that
    # COMPLETED at/after arm time.
    #
    # A STATE fire (merged/closed/stall) sets WATCH_DONE=1 and does NOT re-arm: the
    # successor would IMMEDIATELY re-fire it (a merged PR stays merged; a stalled item
    # stays stalled), which would livelock and burn the API budget. A DELTA fire
    # (comment/verdict) calls watch_rearm_now — the successor is ALIVE before we print
    # and exit, so the agent is woken AND a watch keeps running.
    if has merged && [ "$merged" = "true" ]; then
      WATCH_DONE=1
      printf 'MERGED   %s  (unblocked)\n' "$tok"; exit 0; fi
    if has closed && [ "$state" = "closed" ] && [ "$merged" != "true" ]; then
      WATCH_DONE=1
      printf 'CLOSED   %s  closed without merging — find its successor\n' "$tok"; exit 0; fi
    if has comment && [ "$changed" = 1 ] && [ -n "$cc" ] && [ -n "$pcc" ] && [ "$cc" != "$pcc" ]; then
      watch_rearm_now
      printf 'COMMENT  %s  new comment (%s -> %s)  %s/%s/%s\n' \
        "$tok" "$pcc" "$cc" "$url" "$([ "$type" = pr ] && echo pull || echo issues)" "$n"; exit 0; fi
    if has verdict && [ "$changed" = 1 ] && [ -n "$v" ] && [ "$v" != "$pv" ]; then
      # The batched query supplied a CANDIDATE run id (newest completed `$WF` run on
      # the head); confirm its COMPLETION time with a single item-scoped `gh run view`.
      # Falls back to the query's own run-completion instant when the probe is
      # unavailable. `probe_run_id` returns "id|conclusion|completedEpoch".
      probe="$(probe_run_id "$o/$r" "$v" "$up")"; prc=$?
      watch_rc_guard "$prc"      # a rate-limit abort inside the probe ends us too
      probe_rc=""; probe_epoch="$ve"
      [ -n "$probe" ] && { v="${probe%%|*}"; rest2="${probe#*|}"; probe_rc="${rest2%%|*}"; probe_epoch="${rest2##*|}"; }
      if [ -n "$probe_epoch" ] && [ "$probe_epoch" -ge "$ARM_EPOCH" ]; then
        watch_rearm_now
        printf 'VERDICT  %s  new %s run %s%s  %s/actions/runs/%s\n' \
          "$tok" "$WF" "$v" "$([ -n "$probe_rc" ] && printf ' (%s)' "$probe_rc")" "$url" "$v"; exit 0; fi
    fi
    # stall requires an OBSERVED open state — never alarm on an unknown state.
    if has stall && [ "$merged" != "true" ] && [ "$state" != "closed" ] \
       && [ -n "$state" ] && [ "$state" != "unknown" ] && [ -n "$up" ] && [ "$up" -gt 0 ] \
       && [ $(( (now - up) / 60 )) -ge "$STALL_MIN" ]; then
      WATCH_DONE=1
      printf 'STALL    %s  no progress for %sm (open, unmerged) — takeover candidate\n' "$tok" "$STALL_MIN"; exit 0; fi

    SEED[$tok]="$cur"
  done

  watch_sleep "$INTERVAL"
done
