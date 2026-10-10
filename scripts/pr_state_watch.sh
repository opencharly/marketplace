#!/usr/bin/env bash
# pr_state_watch.sh — poll a PR and STOP the instant it reaches a terminal state.
#
# The landing loop has exactly three states that must halt an operator or an agent
# immediately, and this script exists so that "keep polling" can never be the wrong
# answer to any of them:
#
#   MERGED       — the PR landed (auto-merge squashed it). Done; move to the tag check.
#   BLOCKED      — the fresh `charly/pr-validator` verdict is BLOCK. Do NOT re-dispatch
#                  in a loop, do NOT "retry and see" (R1/R4): read the verdict, fix, and
#                  land a NEW commit.
#   INCONCLUSIVE — the required check is red but the gate produced NO review verdict (its
#                  provider returned nothing). This is NOT a code finding and NOT a BLOCK:
#                  no diff fix follows, so the watcher stops and hands it to the operator
#                  instead of starting a fix loop.
#   CLOSED       — closed without merge (abandoned).
#
# WHY THIS IS NOT `gh pr checks --watch`. A body-only fix does not move the head, so the
# body-fix path is re-running the FAILED run through the REST API. That re-run produces a
# SECOND same-name check-run at the SAME head (MEASURED on opencharly/charly#750 head
# 81a31ee5: attempt 1 `110686319282 failure` + attempt 2 `110688937293 success` both present
# under `filter=all`), which is why the check-run read below asks for `filter=all` rather
# than the API's `latest` default: with `latest` the older attempt is invisible, so the
# classifier cannot tell a fresh single verdict from a superseded one. The NEWER attempt
# settles the merge — #750 merged at 03:15:37Z carrying exactly that pair — so an older
# FAILURE beside a newer SUCCESS is SUPERSEDED (keep polling), never a terminal state.
#
# THE CLASS IS NOT IN THE CHECK-RUN. Both classes conclude `failure`, and the check run's
# own `output.title`/`output.summary` are EMPTY for BLOCK, INCONCLUSIVE and PASS alike
# (MEASURED on marketplace#405 and .github#157). The ONE artifact that carries the class is
# the gate's own PR comment, whose heading is `## Review — BLOCK` or
# `## validator INCONCLUSIVE — …`; this script reads that heading before it calls a red
# check a BLOCK.
#
# Usage:
#   pr_state_watch.sh <owner>/<repo> <pr-number> [--interval SECONDS] [--timeout SECONDS]
#
# Exit codes (terminal — never retried by this script):
#   0  MERGED
#   2  BLOCKED       (verdict BLOCK — a code finding to fix)
#   3  CLOSED        (closed without merge)
#   4  TIMEOUT       (no terminal state within --timeout)
#   5  ERROR         (bad usage, or gh/API failure)
#   8  INCONCLUSIVE  (red check, no review verdict — no code finding; operator class)
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/_watch_common.sh
. "$SELF_DIR/_watch_common.sh"

REPO=""
PR=""
# --interval defaults to 300 and is a FLOOR of 300 seconds (POLL_FLOOR, from
# _watch_common.sh): a sub-300s value is REFUSED (exit 5) so no silent sub-floor
# polling ever ships. Tests that must run fast opt in via ALLOW_FAST_POLL=1.
INTERVAL="${PR_STATE_INTERVAL:-300}"
TIMEOUT=900

usage() {
  cat <<'EOF'
pr_state_watch.sh — poll a PR and STOP the instant it reaches a terminal state.

Usage:
  pr_state_watch.sh <owner>/<repo> <pr-number> [--interval SECONDS] [--timeout SECONDS]

--interval defaults to 300 and is a FLOOR of 300 seconds (POLL_FLOOR): a sub-300s value
is REFUSED (exit 5) so no silent sub-floor polling ever ships. Tests that must run
fast opt in explicitly with ALLOW_FAST_POLL=1; it is never a production setting.

Watches the required `validate / validate` check over ALL of its same-name runs on
the PR head. Terminal states halt immediately (this script never retries them):

  0  MERGED        the PR landed (auto-merge squashed it)
  2  BLOCKED       verdict BLOCK — a code finding to read, fix and land
  3  CLOSED        closed without merge
  4  TIMEOUT       no terminal state within --timeout
  5  ERROR         bad usage, or gh/API failure
  7  FATAL         a GitHub rate limit was hit — a HARD abort, never retried
  8  INCONCLUSIVE  the required check is red but the gate produced NO review verdict
                   (its provider answered nothing). NOT a BLOCK and NOT a code
                   finding: no diff fix follows, so this stops and goes to the
                   operator instead of a fix loop.

WHY NOT `gh pr checks --watch`: a body-only fix does not move the head, so the fix
is re-running the FAILED run through the REST API — which leaves TWO same-name runs
at that head. The newer attempt settles the merge (MEASURED: charly#750 merged with
an older `failure` and a newer `success` at one head), so an older FAILURE beside a
newer SUCCESS is SUPERSEDED and keeps polling. The class of a RED check is read from
the gate's own comment, never from the check run, whose output fields are empty.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --interval) INTERVAL="${2:?--interval needs a value}"; shift 2 ;;
    --timeout)  TIMEOUT="${2:?--timeout needs a value}"; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    -*)         echo "pr_state_watch: unknown flag $1" >&2; usage >&2; exit 5 ;;
    *)          if [ -z "$REPO" ]; then REPO="$1";
                elif [ -z "$PR" ]; then PR="$1";
                else echo "pr_state_watch: unexpected argument $1" >&2; exit 5; fi
                shift ;;
  esac
done

[ -n "$REPO" ] && [ -n "$PR" ] || { usage >&2; exit 5; }
case "$PR" in ''|*[!0-9]*) echo "pr_state_watch: <pr-number> must be numeric, got '$PR'" >&2; exit 5 ;; esac
command -v gh >/dev/null 2>&1 || { echo "pr_state_watch: gh not found" >&2; exit 5; }

# --interval is validated against the 300s POLL_FLOOR (refuse sub-floor unless
# ALLOW_FAST_POLL=1 — tests only).
INTERVAL="$(watch_interval pr_state_watch "$INTERVAL" "--interval")" \
  || { usage >&2; exit 5; }

# The required check this org protects `main` with. Overridable for a repo whose
# ruleset names a different context (and for testing) — the default is the org one.
REQUIRED_CHECK="${PR_STATE_REQUIRED_CHECK:-validate / validate}"
# The workflow FILE that produces the required check (matched as a suffix of a workflow run's
# `path`). A re-run of it that is queued/in progress has NO check run yet, so the check-runs
# view still shows the previous attempt's FAILURE; this lets the classifier see it in flight.
REQUIRED_WORKFLOW="${PR_STATE_REQUIRED_WORKFLOW:-org-wide-pr-validator-required.yml}"
# The account the gate posts its verdict comment as. The comment is the ONLY artifact that
# carries the verdict CLASS (BLOCK vs INCONCLUSIVE) — the check run's `failure` conclusion and
# its empty `output.*` fields are identical for both.
VALIDATOR_AUTHOR="${PR_STATE_VALIDATOR_AUTHOR:-github-actions[bot]}"

deadline=$(( $(date +%s) + TIMEOUT ))
last_report=""

report() { # report <verdict> <detail>
  printf '%s  %s#%s  %s  %s\n' "$(date -u +%H:%M:%S)" "$REPO" "$PR" "$1" "$2"
}

while :; do
  # RATE-LIMIT HARD ABORT: a genuine ZERO quota is a STOP, routed through the ONE
  # shared guard (watch_rate_zero_abort) so the policy lives in _watch_common.sh, not
  # duplicated here. `--interval` floors the cadence; this is the second line.
  watch_rate_zero_abort "pr_state_watch"

  # One snapshot: state + head + all same-name check-runs for that head. Capture the
  # RAW output so a rate-limit signal in it is detected and ABORTS, rather than being
  # mistaken for a generic gh failure (a rate limit is a stop, not a transient).
  json="$(gh pr view "$PR" --repo "$REPO" \
            --json state,mergeStateStatus,headRefOid,url 2>&1)" || {
    watch_is_rate_limited "$json" && watch_fatal_rate_limit "pr_state_watch" "$(printf '%s' "$json" | head -c 200)"
    echo "pr_state_watch: gh pr view failed for $REPO#$PR" >&2; exit 5; }
  watch_is_rate_limited "$json" && watch_fatal_rate_limit "pr_state_watch" "$(printf '%s' "$json" | head -c 200)"

  state="$(printf '%s' "$json" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)"
  head="$(printf '%s' "$json" | grep -o '"headRefOid":"[^"]*"' | head -1 | cut -d'"' -f4)"
  merge_state="$(printf '%s' "$json" | grep -o '"mergeStateStatus":"[^"]*"' | head -1 | cut -d'"' -f4)"
  url="$(printf '%s' "$json" | grep -o '"url":"[^"]*"' | head -1 | cut -d'"' -f4)"

  case "$state" in
    MERGED) report MERGED "landed ($url)"; exit 0 ;;
    CLOSED) report CLOSED "closed without merge ($url)"; exit 3 ;;
  esac

  # Classify the required check over ALL same-name runs on the head.
  #   NONE       no run yet (or a different check name)  -> keep polling
  #   PENDING    a run is queued/in progress             -> keep polling
  #   PASS       newest completed is SUCCESS, no blocking conclusion -> keep polling (await merge)
  #   SUPERSEDED newest is SUCCESS but an older run did not pass (FAILURE, CANCELLED, ...)
  #              of the same name remains               -> keep polling (the newer
  #              attempt settles the merge; charly#750 merged on exactly this pair)
  #   BLOCKED    newest completed run did NOT pass       -> terminal (class below). The
  #              blocking conclusions are ENUMERATED at the classifier; FAILURE is one
  #              of them, not the definition of the state.
  # gh api's --jq takes ONE expression (no jq flags), so filter in jq itself with the
  # required-check name passed as a positional argument.
  # NB: the REST check-runs API returns lowercase "completed"/"success"/"failure",
  # while `gh pr view --json` (GraphQL) returns uppercase. Normalize with ascii_upcase
  # so the script is correct against EITHER shape.
  # `filter=all` is REQUIRED, not cosmetic: the endpoint's default is `latest`, which
  # returns only the newest same-name run and so hides a superseded attempt entirely.
  cr_json="$(gh api "repos/$REPO/commits/$head/check-runs?filter=all" --paginate 2>&1)" || {
    watch_is_rate_limited "$cr_json" && watch_fatal_rate_limit "pr_state_watch" "$(printf '%s' "$cr_json" | head -c 200)"
    echo "pr_state_watch: gh api check-runs failed for $REPO@$head" >&2; exit 5; }
  watch_is_rate_limited "$cr_json" && watch_fatal_rate_limit "pr_state_watch" "$(printf '%s' "$cr_json" | head -c 200)"
  verdict="$(printf '%s' "$cr_json" | jq -r --arg name "$REQUIRED_CHECK" '
        [.check_runs[] | select(.name==$name)]
        | if length==0 then "NONE"
          elif any(.[]; (.status|ascii_upcase) != "COMPLETED") then "PENDING"
          else def # a conclusion the merge gate does NOT treat as passing. ENUMERATED, never
               # inferred: the check-run vocabulary is FAILURE, CANCELLED, TIMED_OUT,
               # STARTUP_FAILURE, STALE, ACTION_REQUIRED, and the passing values are SUCCESS,
               # NEUTRAL and SKIPPED. The revision before this one tested `=="FAILURE"` only and
               # let every other value fall through to "PASS" — so a CANCELLED run beside a newer
               # SUCCESS read as PASS on a PR that was BLOCKED and could not merge. Measured:
               # opencharly/opencharly#460 (head carried one success and one cancelled; it stayed
               # BLOCKED with auto-merge armed until the cancelled run was re-run).
               blocking: (.conclusion|ascii_upcase) as $c
                 | ["FAILURE","CANCELLED","TIMED_OUT","STARTUP_FAILURE","STALE","ACTION_REQUIRED"]
                 | index($c) != null;
               (sort_by(.started_at) | .[-1]) as $newest
               | if   ($newest|blocking) then "BLOCKED"
                 elif any(.[]; blocking) then "SUPERSEDED"
                 else "PASS" end
          end')" || {
    echo "pr_state_watch: jq failed for check-runs of $REPO@$head" >&2; exit 5; }

  # A FAILURE verdict is only terminal when no NEWER attempt is in flight. A requested re-run
  # (the REST body-only fix) creates its check run only once its job starts, so for that window
  # the check-runs view still shows the old attempt's FAILURE. Consult the head's workflow runs:
  # a queued/in-progress run of the required workflow means the verdict is PENDING, not BLOCKED
  # (opencharly/marketplace#403).
  if [ "$verdict" = "BLOCKED" ]; then
    wr_json="$(gh api "repos/$REPO/actions/runs?head_sha=$head&per_page=100" 2>&1)" || {
      watch_is_rate_limited "$wr_json" && watch_fatal_rate_limit "pr_state_watch" "$(printf '%s' "$wr_json" | head -c 200)"
      echo "pr_state_watch: gh api actions/runs failed for $REPO@$head" >&2; exit 5; }
    watch_is_rate_limited "$wr_json" && watch_fatal_rate_limit "pr_state_watch" "$(printf '%s' "$wr_json" | head -c 200)"
    inflight="$(printf '%s' "$wr_json" | jq -r --arg wf "$REQUIRED_WORKFLOW" '
          [.workflow_runs[]? | select((.path // "") | endswith($wf))
                             | select((.status // "" | ascii_downcase) != "completed")] | length')" || {
      echo "pr_state_watch: jq failed for actions/runs of $REPO@$head" >&2; exit 5; }
    [ "${inflight:-0}" -gt 0 ] && verdict="PENDING"
  fi

  # A RED check is not yet a BLOCK: the gate's `failure` conclusion is the SAME for a real
  # BLOCK and for an INCONCLUSIVE run that produced no verdict at all. The class lives only in
  # the gate's own comment heading (`## Review — BLOCK` / `## validator INCONCLUSIVE — …`), so
  # read it before naming a terminal state — an unreviewed red check must NOT start a fix loop.
  class=""
  if [ "$verdict" = "BLOCKED" ]; then
    # The class may only be read from a comment attributable to THIS head: a verdict left on
    # an EARLIER head must never set this head's class. The gate's two comment shapes are
    # attributable by different signals, so both are scoped below:
    #   * the ENGINE's review verdict carries the head it reviewed — `Head SHA: `<sha>`` — so
    #     it is attributable exactly when that sha is this head (a re-run at the same head
    #     legitimately leaves a comment older than the newest attempt's run start).
    #   * the workflow's own INCONCLUSIVE notice carries NO head line (it names the run's
    #     class, not the head), so its only signal is time: it is posted DURING the run it
    #     belongs to, so it must not PREDATE this head's failed run.
    # Without the scoping an older head's INCONCLUSIVE stops the watcher (exit 8, "no finding —
    # escalate") on a fresh head whose own verdict was never read (marketplace#405 B18).
    run_started="$(printf '%s' "$cr_json" | jq -r --arg name "$REQUIRED_CHECK" '
          [.check_runs[] | select(.name==$name)
                          | select((.conclusion|ascii_upcase)=="FAILURE")]
          | sort_by(.started_at) | .[-1].started_at // ""')" || {
      echo "pr_state_watch: jq failed for the failed run timestamp of $REPO@$head" >&2; exit 5; }
    # PAGINATED, like the check-runs read above: this read exists to find the NEWEST verdict
    # comment, and the API orders issue comments OLDEST-first, so a single page hides the newest
    # one on any thread longer than a page — the read would then report no verdict for a head
    # whose gate did produce one. gh emits ONE JSON ARRAY PER PAGE, so the jq below slurps the
    # pages and flattens them (`add`) before filtering.
    vc_json="$(gh api --paginate "repos/$REPO/issues/$PR/comments" 2>&1)" || {
      watch_is_rate_limited "$vc_json" && watch_fatal_rate_limit "pr_state_watch" "$(printf '%s' "$vc_json" | head -c 200)"
      echo "pr_state_watch: gh api issue comments failed for $REPO#$PR" >&2; exit 5; }
    watch_is_rate_limited "$vc_json" && watch_fatal_rate_limit "pr_state_watch" "$(printf '%s' "$vc_json" | head -c 200)"
    class="$(printf '%s' "$vc_json" | jq -sr --arg author "$VALIDATOR_AUTHOR" --arg head "$head" --arg since "$run_started" '
          (add // [])
          | [ .[] | select(.user.login==$author)
                | select((.body // "") | test("^## (validator|Review)"))
                | select((if ((.body // "") | test("Head SHA:"))
                         then ((.body // "") | test("Head SHA: `" + $head + "`"))
                         else (($since != "") and ((.created_at // "") >= $since)) end)) ]
          | if length==0 then "UNKNOWN"
            else (.[-1].body | split("\n")[0])
                 | if test("INCONCLUSIVE") then "INCONCLUSIVE" else "BLOCK" end end')" || {
      echo "pr_state_watch: jq failed for issue comments of $REPO#$PR" >&2; exit 5; }
  fi

  case "$verdict" in
    BLOCKED)
      if [ "$class" = "INCONCLUSIVE" ]; then
        report INCONCLUSIVE "no review verdict at head ${head:0:9} — the gate is red but produced NO code finding (mergeState=$merge_state)"
        echo "  This is NOT a BLOCK and there is NO finding to fix, so do NOT open a fix loop."
        echo "  The gate could not obtain a verdict (its provider class). Escalate to the operator"
        echo "  rather than re-running blindly; a re-run is a fresh attempt and may still pass:"
        echo "    gh api -X POST repos/$REPO/actions/runs/<run-id>/rerun"
        exit 8
      fi
      if [ "$class" = "UNKNOWN" ]; then
        report BLOCKED "verdict BLOCK at head ${head:0:9} (mergeState=$merge_state)"
        echo "  No verdict comment could be attributed to this head: every gate verdict on this"
        echo "  thread names another head, or predates this head's failed run, and a stale verdict"
        echo "  must NOT set this head's class. Fail-closed: read the run's own evidence artifact"
        echo "  and the thread before assuming a BLOCK finding exists — and never fix-loop on a"
        echo "  comment that cannot be attributed to this head:"
        echo "    gh pr view $url --comments"
        exit 2
      fi
      report BLOCKED "verdict BLOCK at head ${head:0:9} (mergeState=$merge_state)"
      echo "  read the latest '## Review — BLOCK' comment on $url; fix, commit, RE-FINALIZE the body, push."
      exit 2 ;;
    SUPERSEDED)
      [ "$last_report" = "SUPERSEDED" ] || { report WAIT "an older non-passing run of $REQUIRED_CHECK is superseded by a newer SUCCESS at head ${head:0:9} (mergeState=$merge_state)"; last_report=SUPERSEDED; } ;;
    PASS)
      [ "$last_report" = "PASS" ] || { report PASS "verdict PASS at head ${head:0:9}; awaiting merge (mergeState=$merge_state)"; last_report=PASS; } ;;
    NONE)
      [ "$last_report" = "NONE" ] || { report WAIT "no $REQUIRED_CHECK run yet at head ${head:0:9}"; last_report=NONE; } ;;
    PENDING)
      [ "$last_report" = "PENDING" ] || { report WAIT "$REQUIRED_CHECK running at head ${head:0:9}"; last_report=PENDING; } ;;
  esac

  if [ "$(date +%s)" -ge "$deadline" ]; then
    report TIMEOUT "no terminal state in ${TIMEOUT}s (last: $verdict, mergeState=$merge_state)"
    exit 4
  fi
  sleep "$INTERVAL"
done
