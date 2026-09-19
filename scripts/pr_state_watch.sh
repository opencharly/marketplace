#!/usr/bin/env bash
# pr_state_watch.sh — poll a PR and STOP the instant it reaches a terminal state.
#
# The landing loop has exactly three states that must halt an operator or an agent
# immediately, and this script exists so that "keep polling" can never be the wrong
# answer to any of them:
#
#   MERGED   — the PR landed (auto-merge squashed it). Done; move to the tag check.
#   BLOCKED  — the fresh `charly/pr-validator` verdict is BLOCK, or the PR is stuck
#              behind a duplicate same-name check-run (see below). Do NOT re-dispatch
#              in a loop, do NOT "retry and see" (R1/R4): read the verdict, fix, and
#              land a NEW commit.
#   CLOSED   — closed without merge (abandoned).
#
# WHY THIS IS NOT `gh pr checks --watch`. A body-only fix does not move the head, and
# re-dispatching the validator on the SAME head leaves BOTH same-name check-runs in
# the rollup. GitHub's rollup collapses them to the WORST conclusion, so a green
# re-dispatch does NOT clear an earlier red run of the same name — the PR reads
# `mergeStateStatus=BLOCKED` while its verdict is PASS. That state is indistinguishable
# from a real BLOCK by `gh pr checks`, and it is exactly what this script names, because
# the remedy (push a NEW commit, or add the per-repo concurrency dedupe) is different
# from a real BLOCK's remedy (fix the finding).
#
# Usage:
#   pr_state_watch.sh <owner>/<repo> <pr-number> [--interval SECONDS] [--timeout SECONDS]
#
# Exit codes (terminal — never retried by this script):
#   0  MERGED
#   2  BLOCKED  (verdict BLOCK, or a poisonously stuck duplicate check-run)
#   3  CLOSED   (closed without merge)
#   4  TIMEOUT  (no terminal state within --timeout)
#   5  ERROR    (bad usage, or gh/API failure)
set -euo pipefail

REPO=""
PR=""
INTERVAL=15
TIMEOUT=900

usage() {
  cat <<'EOF'
pr_state_watch.sh — poll a PR and STOP the instant it reaches a terminal state.

Usage:
  pr_state_watch.sh <owner>/<repo> <pr-number> [--interval SECONDS] [--timeout SECONDS]

Watches the required `validate / validate` check over ALL of its same-name runs on
the PR head. Terminal states halt immediately (this script never retries them):

  0  MERGED    the PR landed (auto-merge squashed it)
  2  BLOCKED   verdict BLOCK, OR a green re-dispatch stuck behind an older
               same-name FAILURE in the rollup (the POISON state below)
  3  CLOSED    closed without merge
  4  TIMEOUT   no terminal state within --timeout
  5  ERROR     bad usage, or gh/API failure

WHY NOT `gh pr checks --watch`: a body-only fix does not move the head, so a
same-head re-dispatch leaves BOTH same-name runs in the rollup; GitHub collapses
them to the WORST conclusion, so a green run does NOT clear an earlier red one of
the same name — the PR reads BLOCKED while its verdict is PASS. That POISON state
(watch for it in the output) is remedied by a NEW commit, not by re-dispatching.
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

# The required check this org protects `main` with. Overridable for a repo whose
# ruleset names a different context (and for testing) — the default is the org one.
REQUIRED_CHECK="${PR_STATE_REQUIRED_CHECK:-validate / validate}"

deadline=$(( $(date +%s) + TIMEOUT ))
last_report=""

report() { # report <verdict> <detail>
  printf '%s  %s#%s  %s  %s\n' "$(date -u +%H:%M:%S)" "$REPO" "$PR" "$1" "$2"
}

while :; do
  # One snapshot: state + head + all same-name check-runs for that head.
  json="$(gh pr view "$PR" --repo "$REPO" \
            --json state,mergeStateStatus,headRefOid,url 2>/dev/null)" || {
    echo "pr_state_watch: gh pr view failed for $REPO#$PR" >&2; exit 5; }

  state="$(gh --version >/dev/null; printf '%s' "$json" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)"
  head="$(printf '%s' "$json" | grep -o '"headRefOid":"[^"]*"' | head -1 | cut -d'"' -f4)"
  merge_state="$(printf '%s' "$json" | grep -o '"mergeStateStatus":"[^"]*"' | head -1 | cut -d'"' -f4)"
  url="$(printf '%s' "$json" | grep -o '"url":"[^"]*"' | head -1 | cut -d'"' -f4)"

  case "$state" in
    MERGED) report MERGED "landed ($url)"; exit 0 ;;
    CLOSED) report CLOSED "closed without merge ($url)"; exit 3 ;;
  esac

  # Classify the required check over ALL same-name runs on the head.
  #   NONE    no run yet (or a different check name)  -> keep polling
  #   PENDING a run is queued/in progress             -> keep polling
  #   PASS    newest completed is SUCCESS, no failure -> keep polling (await merge)
  #   BLOCKED newest completed is FAILURE             -> terminal
  #   POISON  newest is SUCCESS but an older FAILURE
  #           of the same name remains in the rollup  -> terminal (stuck)
  # gh api's --jq takes ONE expression (no jq flags), so filter in jq itself with the
  # required-check name passed as a positional argument.
  # NB: the REST check-runs API returns lowercase "completed"/"success"/"failure",
  # while `gh pr view --json` (GraphQL) returns uppercase. Normalize with ascii_upcase
  # so the script is correct against EITHER shape.
  verdict="$(gh api "repos/$REPO/commits/$head/check-runs" --paginate 2>/dev/null \
      | jq -r --arg name "$REQUIRED_CHECK" '
        [.check_runs[] | select(.name==$name)]
        | if length==0 then "NONE"
          elif any(.[]; (.status|ascii_upcase) != "COMPLETED") then "PENDING"
          else (sort_by(.started_at) | .[-1]) as $newest
               | if   ($newest.conclusion|ascii_upcase)=="FAILURE" then "BLOCKED"
                 elif any(.[]; (.conclusion|ascii_upcase)=="FAILURE") then "POISON"
                 else "PASS" end
          end')" || {
    echo "pr_state_watch: gh api check-runs failed for $REPO@$head" >&2; exit 5; }

  case "$verdict" in
    BLOCKED)
      report BLOCKED "verdict BLOCK at head ${head:0:9} (mergeState=$merge_state)"
      echo "  read the latest 'Review — BLOCK' comment on $url; fix, commit, RE-FINALIZE the body, push."
      exit 2 ;;
    POISON)
      report BLOCKED "STUCK: newest $REQUIRED_CHECK is SUCCESS but an older FAILURE of the same name still poisons the rollup (head ${head:0:9})"
      echo "  This is NOT a verdict BLOCK. A same-head re-dispatch cannot clear it."
      echo "  Remedy: push a NEW commit (fresh SHA), OR add the per-repo concurrency dedupe to"
      echo "  .github/workflows/pr-validator.yml (group pr-validator-\${{ github.repository }}-\${{ ... }})."
      exit 2 ;;
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
