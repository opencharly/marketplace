#!/usr/bin/env bash
# watch_family_test.sh — self-contained coverage for the watcher family
# (pr_watch_many.sh, gh_watch.sh, _watch_common.sh, pr_state_watch.sh). It installs a
# deterministic stub `gh` on PATH so every asserted branch is exercised WITHOUT
# network, then asserts on outcomes. Exit 0 iff every assertion passed.
#
# Run: ./scripts/watch_family_test.sh
#
# Tests that must poll fast opt in explicitly with ALLOW_FAST_POLL=1 (the committed
# defaults are 60s and the floor refuses sub-60s without this escape hatch).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Fast polling is a TEST-ONLY explicit opt-in (the committed default is 60s). Set it
# for the WHOLE suite; the floor's own refusal is asserted in a SUBSHELL with it unset.
export ALLOW_FAST_POLL=1

FAILS=0
ok()  { printf 'ok   - %s\n' "$1"; }
bad() { printf 'FAIL - %s\n       %s\n' "$1" "$2"; FAILS=$((FAILS + 1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3] got [$2]"; fi; }

# --- stub gh ---------------------------------------------------------------
# The watcher family now uses: `api graphql` (the ONE batched poll), the REST
# `api repos/<o>/<r>/actions/runs/<id>` probe (gh_watch's item-scoped verdict
# probe), `run list` (pr_watch_many's repo-scoped verdict), `pr view`
# (pr_state_watch's snapshot), and `api rate_limit`. The stub reads fixtures from
# $WATCH_TEST_DIR.
export WATCH_TEST_DIR="$WORK"
cat > "$WORK/gh" <<'STUB'
#!/usr/bin/env bash
d="${WATCH_TEST_DIR:?}"
case "$1 $2" in
  "api rate_limit"*)
    # WATCH_RATE_HOOK-independent rate fixture: remaining.txt then reset.txt.
    case "$*" in
      *"reset"*) cat "$d/reset.txt" 2>/dev/null || echo "$(date +%s)" ;;
      *) cat "$d/remaining.txt" 2>/dev/null || echo 9999 ;;
    esac ;;
  "api graphql"*)
    # The batched poll. The counter increments on EVERY call (including an erroring
    # one) so a "no retry" assertion can count attempts. If gqlerr.txt exists, emit it
    # (to exercise RATE_LIMIT detection) with gh's exit ${GQLERR_RC:-0}; else gql.json
    # on the first call and gql_after.json on later polls when present.
    n="$(cat "$d/gqlcalls" 2>/dev/null || echo 0)"; n=$((n + 1)); printf '%s' "$n" > "$d/gqlcalls"
    if [ -f "$d/gqlerr.txt" ]; then cat "$d/gqlerr.txt"; exit "${GQLERR_RC:-0}"; fi
    if [ "$n" -le 1 ]; then cat "$d/gql.json" 2>/dev/null || echo '{"data":{}}'
    elif [ -f "$d/gql_after.json" ]; then cat "$d/gql_after.json"
    else cat "$d/gql.json" 2>/dev/null || echo '{"data":{}}'; fi ;;
  "pr view"*)
    # pr_state_watch's single snapshot. If prerr.txt exists, emit it and exit non-zero
    # (to exercise the rate-limit abort); else a benign non-terminal PR.
    if [ -f "$d/prerr.txt" ]; then cat "$d/prerr.txt"; exit 1; fi
    printf '{"state":"OPEN","mergeStateStatus":"BLOCKED","headRefOid":"abcdef1234567890","url":"https://github.com/%s/pull/%s"}' "$3" "$4" ;;
  "api repos/"*"/check-runs"*)
    # pr_state_watch's check-runs read for the head (checkruns.json fixture).
    cat "$d/checkruns.json" 2>/dev/null || echo '{"check_runs":[]}' ;;
  "api repos/"*"/issues/"*"/comments"*)
    # pr_state_watch's verdict-CLASS read: the gate's own comment carries the class
    # (comments.json fixture). The counter proves the read ran, so an assertion can show
    # the class is read for a RED check rather than the check run being trusted.
    n="$(cat "$d/commentcalls" 2>/dev/null || echo 0)"; n=$((n + 1)); printf '%s' "$n" > "$d/commentcalls"
    cat "$d/comments.json" 2>/dev/null || echo '[]' ;;
  "api repos/"*"/actions/runs?"*)
    # pr_state_watch's in-flight probe: the head's workflow runs (headruns.json fixture);
    # the counter proves the probe ran.
    n="$(cat "$d/headrunscalls" 2>/dev/null || echo 0)"; n=$((n + 1)); printf '%s' "$n" > "$d/headrunscalls"
    cat "$d/headruns.json" 2>/dev/null || echo '{"workflow_runs":[]}' ;;
  "api repos/"*"/actions/runs/"*)
    # gh_watch's item-scoped verdict probe (probe_run_id → the REST actions/runs
    # endpoint). run_view.json is the fixture; the counter records that the probe ran,
    # so an assertion can prove the path is exercised (and would fail without it).
    n="$(cat "$d/runcalls" 2>/dev/null || echo 0)"; n=$((n + 1)); printf '%s' "$n" > "$d/runcalls"
    cat "$d/run_view.json" 2>/dev/null || echo '{"id":null}' ;;
  "run list"*)
    # Sequence-aware: the FIRST `run list` (the seed read) returns runs.json; later
    # polls return runs_after.json when present.
    n="$(cat "$d/ncalls" 2>/dev/null || echo 0)"; n=$((n + 1)); printf '%s' "$n" > "$d/ncalls"
    if [ "$n" -le 1 ]; then cat "$d/runs.json" 2>/dev/null || echo '[]'
    elif [ -f "$d/runs_after.json" ]; then cat "$d/runs_after.json"
    else cat "$d/runs.json" 2>/dev/null || echo '[]'; fi ;;
esac
exit 0
STUB
chmod +x "$WORK/gh"
export PATH="$WORK:$PATH"
printf '[]'    > "$WORK/runs.json"
printf '{"data":{}}' > "$WORK/gql.json"


# 1 ── syntax of every family file
for s in _watch_common.sh pr_watch_many.sh gh_watch.sh pr_state_watch.sh; do
  if bash -n "$HERE/$s" 2>/dev/null; then ok "bash -n $s"; else bad "bash -n $s" "syntax error"; fi
done

# 2 ── _watch_common.sh helpers
# shellcheck source=scripts/_watch_common.sh disable=SC1091
. "$HERE/_watch_common.sh"
for v in 0 1 42 007; do
  watch_is_uint "$v" && ok "watch_is_uint accepts '$v'" || bad "watch_is_uint accepts '$v'" "rejected a uint"
done
for v in '' abc -1 1.5 '1 2'; do
  watch_is_uint "$v" && bad "watch_is_uint rejects '[$v]'" "accepted a non-uint" || ok "watch_is_uint rejects '[$v]'"
done
watch_has a 'a,b'   && ok "watch_has finds a in a,b"      || bad "watch_has finds a"     "miss"
watch_has x 'a,b'   && bad "watch_has rejects x in a,b"   "false positive" || ok "watch_has rejects x"
watch_usage "$HERE/pr_watch_many.sh" | head -1 | grep -q '^pr_watch_many.sh' \
  && ok "watch_usage emits the header" || bad "watch_usage" "no header line"

# 2b ── the poll floor: sub-60 is refused unless ALLOW_FAST_POLL=1 (tests only)
eq "POLL_FLOOR is 60" "$POLL_FLOOR" 60
( unset ALLOW_FAST_POLL; watch_interval x 5 "--interval" >/dev/null 2>&1 ) \
  && bad "watch_interval refuses sub-floor without ALLOW_FAST_POLL" "accepted 5" \
  || ok "watch_interval refuses sub-floor without ALLOW_FAST_POLL"
eq "watch_interval accepts the floor (60)" "$(watch_interval x 60 "--interval")" 60
eq "watch_interval accepts ALLOW_FAST_POLL sub-floor" "$(watch_interval x 5 "--interval")" 5
( unset ALLOW_FAST_POLL; watch_interval x abc "--interval" >/dev/null 2>&1 ) \
  && bad "watch_interval rejects a non-integer" "accepted abc" \
  || ok "watch_interval rejects a non-integer"

# 2c ── committed defaults are 60s (no test leak into the shipped default) and the
#       floor is enforced end to end (a sub-60 --interval exits 5 without the hatch).
eq "gh_watch default interval is 60"      "$(grep -m1 '^INTERVAL="' "$HERE/gh_watch.sh" | grep -o ':-[0-9]*' | tr -d ':-')" 60
eq "pr_watch_many default interval is 60" "$(grep -m1 '^INTERVAL='  "$HERE/pr_watch_many.sh" | grep -o '[0-9]*')" 60
eq "pr_state_watch default interval is 60" "$(grep -m1 '^INTERVAL="' "$HERE/pr_state_watch.sh" | grep -o ':-[0-9]*' | tr -d ':-')" 60
( unset ALLOW_FAST_POLL; "$HERE/gh_watch.sh" --events merged --interval 5 --timeout 1 opencharly/x#1 >/dev/null 2>&1 )
eq "gh_watch: sub-60 --interval refused (exit 5) without ALLOW_FAST_POLL" "$?" 5

# 2d ── the rate-limit HARD ABORT: a RATE_LIMIT body exits 7, never a retry. MEASURED
#       trap the predicate covers: `gh api graphql` exits 0 while the body carries it.
eq "watch_is_rate_limited detects a GraphQL RATE_LIMIT body" \
   "$(watch_is_rate_limited '{"errors":[{"type":"RATE_LIMIT","message":"API rate limit already exceeded"}]}' && echo yes || echo no)" yes
eq "watch_is_rate_limited detects an HTTP 403 message" \
   "$(watch_is_rate_limited 'gh: HTTP 403: rate limit exceeded' && echo yes || echo no)" yes
eq "watch_is_rate_limited ignores ordinary output" \
   "$(watch_is_rate_limited '{"data":{"r_x_1":{"issueOrPullRequest":null}}}' && echo yes || echo no)" no

# 3 ── watch_run_latest parses id|conclusion|branch|updatedAt|completedEpoch
#      (the fixture carries NO `createdAt` — faithful to the `--json` request)
printf '[{"databaseId":7,"name":"charly/pr-validator","status":"completed","conclusion":"success","headBranch":"b","updatedAt":"2026-01-01T00:00:00Z"}]' > "$WORK/runs.json"
eq "watch_run_latest parses a completed run" "$(watch_run_latest owner/repo charly/pr-validator)" \
   "7|success|b|2026-01-01T00:00:00Z|1767225600"
printf '[]' > "$WORK/runs.json"
eq "watch_run_latest is empty when none" "$(watch_run_latest owner/repo charly/pr-validator)" ""

# 4 ── usage/argument errors exit 5
"$HERE/pr_watch_many.sh" >/dev/null 2>&1;               eq "pr_watch_many: no args exit 5" "$?" 5
"$HERE/pr_watch_many.sh" a 1 b >/dev/null 2>&1;         eq "pr_watch_many: odd pairs exit 5" "$?" 5
"$HERE/pr_watch_many.sh" --interval 0 a 1 >/dev/null 2>&1; eq "pr_watch_many: bad interval exit 5" "$?" 5
"$HERE/gh_watch.sh" >/dev/null 2>&1;                    eq "gh_watch: no items exit 5" "$?" 5
"$HERE/gh_watch.sh" owner/repo >/dev/null 2>&1;         eq "gh_watch: malformed item exit 5" "$?" 5

# ── GraphQL fixture helpers. The batched poll parses ONE JSON document, so the tests
#    build it from per-item field files. `gql_item <owner> <repo> <num> <type> <state>
#    <merged> <comments> <head> <updatedAt> [runId] [runConclusion] [runUpdatedAt]`.
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; NOW_ISO="$NOW"
OLD="$(date -u -d '3 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
gql_item() {
  local o="$1" r="$2" n="$3" ty="$4" st="$5" mg="$6" cc="$7" hd="$8" up="$9"
  local rid="${10:-}" rc="${11:-}" ru="${12:-}"
  if [ "$ty" = pr ]; then
    printf '{"__typename":"PullRequest","state":"%s","merged":%s,"updatedAt":"%s","comments":{"totalCount":%s},"headRefOid":"%s","commits":{"nodes":[{"commit":{"checkSuites":{"nodes":[%s]}}}]}}' \
      "$(printf '%s' "$st" | tr '[:lower:]' '[:upper:]')" "$mg" "$up" "$cc" "$hd" \
      "$( [ -n "$rid" ] && printf '{"conclusion":"%s","updatedAt":"%s","workflowRun":{"databaseId":%s,"workflow":{"name":"charly/pr-validator"}}}' "$rc" "$ru" "$rid" || echo "" )"
  else
    printf '{"__typename":"Issue","state":"%s","updatedAt":"%s","comments":{"totalCount":%s}}' \
      "$(printf '%s' "$st" | tr '[:lower:]' '[:upper:]')" "$up" "$cc"
  fi
}
# gql_doc <item-token> <item-json> [<item-token> <item-json> ...] → a full
# {"data":{...}} document. The alias is derived with the SAME `gql_alias` the watcher
# uses, so fixture and script can never disagree on the key.
gql_doc() { local s="" ; while [ "$#" -ge 2 ]; do s+="\"$(gql_alias "$1")\":{\"issueOrPullRequest\":$2},"; shift 2; done; printf '{"data":{%s}}' "${s%,}"; }
# The REST actions/runs/{id} shape probe_run_id parses: .id/.conclusion/.updated_at.
run_view_of() { printf '{"id":%s,"conclusion":"%s","updated_at":"%s"}' "$1" "$2" "$3"; }
# Faithful to the real `gh run list --json databaseId,name,status,conclusion,
# headBranch,updatedAt` request: NO `createdAt` (the API is not asked for it, so the
# response omits it). watch_run_latest derives the epoch from `.updatedAt`.
run_old() { printf '[{"databaseId":%s,"name":"charly/pr-validator","status":"completed","conclusion":"success","headBranch":"x","updatedAt":"%s"}]' "$1" "$2"; }
# reset_calls — clear every sequence/call counter + later-poll fixture. Defined HERE
# (before its first use) — a later definition left the early tests' counters unreset.
reset_calls() { rm -f "$WORK/gqlcalls" "$WORK/ncalls" "$WORK/runcalls" "$WORK/gql_after.json" "$WORK/runs_after.json" "$WORK/gqlerr.txt" "$WORK/run_view.json"; }
# seed_no_run — a benign, run-less PR seed (nothing new yet).
seed_no_run() { gql_doc opencharly/x#1 "$(gql_item opencharly x 1 pr open false 0 h1 "$NOW")" > "$WORK/gql.json"; }
# fire_after_arm <runid> — a background writer that, AFTER the arm read, swaps in a
# freshly NOW-timestamped completed run (the DELTA `verdict` fire). It writes ALL the
# fixtures both tools read: gql_after.json (gh_watch) and runs_after.json +
# run_view.json (pr_watch_many / the probe). The timestamp is computed INSIDE the
# subshell, so it is strictly after ARM_EPOCH (a pre-captured NOW would be stale).
fire_after_arm() {
  ( sleep 1
    t="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    run_old "$1" "$t" > "$WORK/runs_after.json"
    run_view_of "$1" success "$t" > "$WORK/run_view.json"
    gql_doc opencharly/x#1 "$(gql_item opencharly x 1 pr open false 0 h2 "$t" "$1" success "$t")" > "$WORK/gql_after.json" ) &
}

# 5 ── gh_watch: STATE events fire from the baseline (deterministic, bounded)
gql_doc opencharly/x#1 "$(gql_item opencharly x 1 pr open true 0 h1 "$NOW")" > "$WORK/gql.json"
"$HERE/gh_watch.sh" --events merged --interval 1 --timeout 3 opencharly/x#1 >/dev/null 2>&1
eq "gh_watch: merged fires on a pre-merged PR" "$?" 0
gql_doc opencharly/x#1 "$(gql_item opencharly x 1 pr open false 0 h1 "$NOW")" > "$WORK/gql.json"
"$HERE/gh_watch.sh" --events merged --interval 1 --timeout 2 opencharly/x#1 >/dev/null 2>&1
eq "gh_watch: merged suppressed when not merged" "$?" 4
gql_doc opencharly/x#1 "$(gql_item opencharly x 1 pr closed false 0 h1 "$NOW")" > "$WORK/gql.json"
"$HERE/gh_watch.sh" --events closed --interval 1 --timeout 3 opencharly/x#1 >/dev/null 2>&1
eq "gh_watch: closed fires" "$?" 0

# 6 ── gh_watch: stall gate — fires on OPEN, suppressed on CLOSED/MERGED
gql_doc opencharly/x#1 "$(gql_item opencharly x 1 pr open false 0 h1 "$NOW")" > "$WORK/gql.json"
"$HERE/gh_watch.sh" --events stall --stallmin 0 --interval 1 --timeout 3 opencharly/x#1 >/dev/null 2>&1
eq "gh_watch: stall fires on open" "$?" 0
gql_doc opencharly/x#1 "$(gql_item opencharly x 1 pr closed false 0 h1 "$NOW")" > "$WORK/gql.json"
"$HERE/gh_watch.sh" --events stall --stallmin 0 --interval 1 --timeout 2 opencharly/x#1 >/dev/null 2>&1
eq "gh_watch: stall suppressed on closed" "$?" 4
gql_doc opencharly/x#1 "$(gql_item opencharly x 1 pr open true 0 h1 "$NOW")" > "$WORK/gql.json"
"$HERE/gh_watch.sh" --events stall --stallmin 0 --interval 1 --timeout 2 opencharly/x#1 >/dev/null 2>&1
eq "gh_watch: stall suppressed on merged" "$?" 4

# 7 ── gh_watch: SEEDED, no false fire on a pre-existing comment
printf '[]' > "$WORK/gql_after.json"
gql_doc opencharly/x#1 "$(gql_item opencharly x 1 pr open false 5 h1 "$NOW")" > "$WORK/gql.json"
"$HERE/gh_watch.sh" --events comment --interval 1 --timeout 2 opencharly/x#1 >/dev/null 2>&1
eq "gh_watch: comment does not fire on a pre-existing count" "$?" 4

# 7b ── an UNKNOWN seed (the item is null on the seed poll) must NOT fire a COMMENT
#       when the next poll shows a real comment count. This is the unknown-sentinel
#       regression: the sentinel must leave the comments slot EMPTY, not 0, or the
#       `[ -n "$pcc" ]` gate passes and a pre-existing comment fires. FAILS if the
#       sentinel carries a 0 in the comments slot.
reset_calls
gql_doc opencharly/x#1 null > "$WORK/gql.json"
gql_doc opencharly/x#1 "$(gql_item opencharly x 1 pr open false 5 h2 "$NOW")" > "$WORK/gql_after.json"
"$HERE/gh_watch.sh" --events comment --interval 1 --timeout 2 opencharly/x#1 >/dev/null 2>&1
eq "gh_watch: an UNKNOWN seed never fires a false COMMENT" "$?" 4
reset_calls

# 8 ── STALE-FIRE guard (the field bug). A "new" verdict must COMPLETE at/after arm
#      time; an id compare alone false-fires when the seed-vs-poll run CHANGES to a
#      different but still-old run. The stub's graphql output can differ between the
#      seed call (call 1) and later polls (gql_after.json), deterministically, no sleeps.
# (reset_calls is defined near the fixture helpers above.)

# 8a ── old seed AND a DIFFERENT old run on the next poll → MUST NOT fire
for tool in many item; do
  reset_calls
  run_old 111 "$OLD" > "$WORK/runs.json"
  run_old 222 "$(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ)" > "$WORK/runs_after.json"
  run_view_of 222 success "$OLD" > "$WORK/run_view.json"
  gql_doc opencharly/x#1 "$(gql_item opencharly x 1 pr open false 0 h1 "$NOW" 111 success "$OLD")" > "$WORK/gql.json"
  gql_doc opencharly/x#1 "$(gql_item opencharly x 1 pr open false 0 h2 "$NOW" 222 success "$(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ)")" > "$WORK/gql_after.json"
  if [ "$tool" = many ]; then
    "$HERE/pr_watch_many.sh" --interval 1 --timeout 2 --repos opencharly/x >/dev/null 2>&1; rc=$?
    eq "pr_watch_many: a DIFFERENT but still-old run never fires" "$rc" 4
  else
    "$HERE/gh_watch.sh" --events verdict --interval 1 --timeout 2 opencharly/x#1 >/dev/null 2>&1; rc=$?
    eq "gh_watch: a DIFFERENT but still-old run never fires" "$rc" 4
  fi
done

# 8b ── EMPTY/UNKNOWN candidate, then a run that completed BEFORE arm → MUST NOT fire
for tool in many item; do
  reset_calls
  printf '[]' > "$WORK/runs.json"
  run_old 222 "$OLD" > "$WORK/runs_after.json"
  run_view_of 222 success "$OLD" > "$WORK/run_view.json"
  gql_doc opencharly/x#1 "$(gql_item opencharly x 1 pr open false 0 h1 "$NOW")" > "$WORK/gql.json"
  gql_doc opencharly/x#1 "$(gql_item opencharly x 1 pr open false 0 h2 "$NOW" 222 success "$OLD")" > "$WORK/gql_after.json"
  if [ "$tool" = many ]; then
    "$HERE/pr_watch_many.sh" --interval 1 --timeout 2 --repos opencharly/x >/dev/null 2>&1; rc=$?
    eq "pr_watch_many: empty seed + a pre-arm run never fires" "$rc" 4
  else
    "$HERE/gh_watch.sh" --events verdict --interval 1 --timeout 2 opencharly/x#1 >/dev/null 2>&1; rc=$?
    eq "gh_watch: empty seed + a pre-arm run never fires" "$rc" 4
  fi
done

# 8c ── POSITIVE control: a run that COMPLETED AFTER arm DOES fire (proves the gate is
#       a real discriminator, not a blanket suppression). fire_after_arm writes all
#       fixtures with a timestamp strictly AFTER arm time.
for tool in many item; do
  reset_calls
  printf '[]' > "$WORK/runs.json"
  seed_no_run; fire_after_arm 333
  if [ "$tool" = many ]; then
    "$HERE/pr_watch_many.sh" --interval 1 --timeout 8 --repos opencharly/x >/dev/null 2>&1; rc=$?
    eq "pr_watch_many: a run completed AFTER arm fires" "$rc" 0
  else
    "$HERE/gh_watch.sh" --events verdict --interval 1 --timeout 8 opencharly/x#1 >/dev/null 2>&1; rc=$?
    eq "gh_watch: a run completed AFTER arm fires" "$rc" 0
    # The firing gh_watch verdict ran probe_run_id → the REST actions/runs probe.
    # This FAILS if probe_run_id is deleted (then no probe call is made, and the
    # candidate's own completion time would be used instead of the confirmed one).
    [ "$(cat "$WORK/runcalls" 2>/dev/null || echo 0)" -ge 1 ] \
      && ok "gh_watch verdict: the probe_run_id REST actions/runs probe is exercised" \
      || bad "probe_run_id exercised" "no actions/runs probe call (probe_run_id dead?)"
  fi
  wait 2>/dev/null
done

# 8d ── MULTI-ITEM batched poll: TWO items in ONE GraphQL request → exactly ONE
#       `api graphql` call for the whole poll (the calls-per-poll = 1 target).
#       The SECOND item is the one with the fireable state (merged=true); the first is
#       benign. This proves the batch resolves BOTH aliases (a mis-keyed second alias
#       would parse as the `unknown` sentinel and the second item would never fire).
reset_calls
printf '[]' > "$WORK/gql.json"
gql_doc opencharly/x#1 "$(gql_item opencharly x 1 pr open false 0 h1 "$NOW")" opencharly/y#2 "$(gql_item opencharly y 2 pr open true 0 h2 "$NOW")" > "$WORK/gql.json"
"$HERE/gh_watch.sh" --events merged --interval 1 --timeout 3 opencharly/x#1 opencharly/y#2 > "$WORK/8d.out" 2>&1
eq "multi-item: the batched poll fires the SECOND item's event" "$?" 0
grep -q '^MERGED   opencharly/y#2' "$WORK/8d.out" \
  && ok "multi-item: the second item resolves in the batch (its alias is keyed correctly)" \
  || bad "multi-item second item" "did not fire on y#2: $(cat "$WORK/8d.out")"
# gqlcalls counts the SEED (1) plus the first poll that fires the event (1) = 2 total
# for the whole 2-item run: calls-per-poll = 1, independent of the 2 items.
eq "multi-item: 2 items cost exactly 1 GraphQL call per poll (2 total incl. seed)" "$(cat "$WORK/gqlcalls" 2>/dev/null || echo 0)" 2
reset_calls

# 8e ── RATE-LIMIT HARD ABORT: a poll that returns a RATE_LIMIT body ABORTS with a
#       non-zero exit (7) and a FATAL naming the reset — it never polls again.
reset_calls
printf '{"errors":[{"type":"RATE_LIMIT","code":"graphql_rate_limit","message":"API rate limit already exceeded"}]}' > "$WORK/gqlerr.txt"
printf '%s' "$(( $(date +%s) + 1200 ))" > "$WORK/reset.txt"
"$HERE/gh_watch.sh" --events verdict --interval 1 --timeout 10 opencharly/x#1 > "$WORK/out_ratelimit.txt" 2>&1
eq "rate-limit: a RATE_LIMIT poll ABORTS non-zero (exit 7)" "$?" 7
grep -q 'FATAL gh_watch: GitHub rate limit reached' "$WORK/out_ratelimit.txt" \
  && ok "rate-limit: prints a FATAL rate-limit message" \
  || bad "rate-limit FATAL message" "$(cat "$WORK/out_ratelimit.txt")"
grep -q 'quota resets at:' "$WORK/out_ratelimit.txt" \
  && ok "rate-limit: the FATAL names the reset time" \
  || bad "rate-limit reset time" "$(cat "$WORK/out_ratelimit.txt")"
eq "rate-limit: it ABORTS on the first poll (no retry) — exactly 1 GraphQL call" "$(cat "$WORK/gqlcalls" 2>/dev/null || echo 0)" 1
reset_calls

# 8f ── pr_state_watch: a rate-limit poll also ABORTS non-zero (7)
printf '%s' "$(( $(date +%s) + 900 ))" > "$WORK/reset.txt"
printf 'gh: HTTP 403: API rate limit exceeded for user' > "$WORK/prerr.txt"
"$HERE/pr_state_watch.sh" opencharly/x 1 --interval 1 --timeout 10 > "$WORK/out_psw_rl.txt" 2>&1
eq "pr_state_watch: a rate-limit poll ABORTS non-zero (exit 7)" "$?" 7
grep -q 'FATAL pr_state_watch: GitHub rate limit reached' "$WORK/out_psw_rl.txt" \
  && ok "pr_state_watch: prints a FATAL rate-limit message" \
  || bad "pr_state_watch rate-limit FATAL" "$(cat "$WORK/out_psw_rl.txt")"
rm -f "$WORK/prerr.txt"
reset_calls

# 8g ── pr_state_watch: a FAILURE check run with a QUEUED re-run of the required workflow is
#       PENDING, not BLOCKED (opencharly/marketplace#403) — and the same FAILURE with nothing in
#       flight is still a terminal BLOCKED (the control).
rm -f "$WORK/prerr.txt" "$WORK/headrunscalls"
printf '%s' '{"check_runs":[{"name":"validate / validate","status":"completed","conclusion":"failure","started_at":"2026-10-01T22:14:50Z"}]}' > "$WORK/checkruns.json"
printf '%s' '{"workflow_runs":[{"path":".github/workflows/org-wide-pr-validator-required.yml","status":"queued","run_attempt":2}]}' > "$WORK/headruns.json"
timeout 15 "$HERE/pr_state_watch.sh" opencharly/x 1 --interval 60 --timeout 1 > "$WORK/out_psw_q.txt" 2>&1
rc=$?
[ "$rc" -ne 2 ] && ok "pr_state_watch: a queued re-run keeps a stale FAILURE non-terminal (rc=$rc)" \
  || bad "pr_state_watch queued re-run" "exited 2 (false BLOCKED): $(cat "$WORK/out_psw_q.txt")"
grep -q 'running at head' "$WORK/out_psw_q.txt" \
  && ok "pr_state_watch: reports the queued re-run as WAIT/running" \
  || bad "pr_state_watch queued re-run report" "$(cat "$WORK/out_psw_q.txt")"
[ "$(cat "$WORK/headrunscalls" 2>/dev/null || echo 0)" -ge 1 ] \
  && ok "pr_state_watch: the actions/runs in-flight probe is exercised" \
  || bad "in-flight probe exercised" "no actions/runs?head_sha call"
printf '%s' '{"workflow_runs":[{"path":".github/workflows/org-wide-pr-validator-required.yml","status":"completed","conclusion":"failure","run_attempt":1}]}' > "$WORK/headruns.json"
timeout 15 "$HERE/pr_state_watch.sh" opencharly/x 1 --interval 60 --timeout 1 > "$WORK/out_psw_b.txt" 2>&1
eq "pr_state_watch: a FAILURE with nothing in flight is still BLOCKED (exit 2)" "$?" 2
rm -f "$WORK/checkruns.json" "$WORK/headruns.json"

# 8h ── pr_state_watch: a RED check whose gate produced NO verdict is INCONCLUSIVE (exit 8),
#       NOT a BLOCK. The check run's `failure` conclusion is identical for both classes, so the
#       class must come from the gate's own comment heading. A false BLOCK here is expensive:
#       it starts a fix loop for a finding that does not exist.
rm -f "$WORK/commentcalls"
printf '%s' '{"check_runs":[{"name":"validate / validate","status":"completed","conclusion":"failure","started_at":"2026-10-02T03:04:52Z"}]}' > "$WORK/checkruns.json"
printf '%s' '{"workflow_runs":[],"total_count":0}' > "$WORK/headruns.json"
printf '%s' '[{"user":{"login":"github-actions[bot]"},"created_at":"2026-10-02T03:04:52Z","body":"## validator INCONCLUSIVE — no review verdict was produced (not a BLOCK; no code finding)\n\nThe gate could **not** obtain a review verdict on this run."}]' > "$WORK/comments.json"
timeout 15 "$HERE/pr_state_watch.sh" opencharly/x 1 --interval 60 --timeout 1 > "$WORK/out_psw_ic.txt" 2>&1
eq "pr_state_watch: a no-verdict red check is INCONCLUSIVE (exit 8), not BLOCKED" "$?" 8
grep -q 'NO code finding' "$WORK/out_psw_ic.txt" \
  && ok "pr_state_watch: the INCONCLUSIVE message says there is no finding to fix" \
  || bad "pr_state_watch INCONCLUSIVE message" "$(cat "$WORK/out_psw_ic.txt")"
[ "$(cat "$WORK/commentcalls" 2>/dev/null || echo 0)" -ge 1 ] \
  && ok "pr_state_watch: the gate-comment class read is exercised" \
  || bad "class read exercised" "no issues/<n>/comments call"

# 8i ── the control for 8h: the SAME red check with a real BLOCK comment must still exit 2, so
#       8h proves the class read discriminates rather than always reporting INCONCLUSIVE.
printf '%s' '[{"user":{"login":"github-actions[bot]"},"created_at":"2026-10-02T02:00:00Z","body":"## Review — BLOCK\n\nHead SHA: `abc`\n"}]' > "$WORK/comments.json"
timeout 15 "$HERE/pr_state_watch.sh" opencharly/x 1 --interval 60 --timeout 1 > "$WORK/out_psw_bl.txt" 2>&1
eq "pr_state_watch: the same red check with a BLOCK comment is still BLOCKED (exit 2)" "$?" 2

# 8j ── an older FAILURE beside a NEWER SUCCESS at one head is SUPERSEDED, never terminal: a
#       REST re-run leaves a second same-name check run at the SAME head (MEASURED on
#       charly#750: `110686319282 failure` + `110688937293 success`), and the newer attempt
#       settles the merge — #750 merged carrying exactly that pair. Reading check-runs with the
#       API's `latest` default would HIDE the older attempt, so this also pins `filter=all`.
printf '%s' '{"check_runs":[{"name":"validate / validate","status":"completed","conclusion":"failure","started_at":"2026-10-02T03:02:27Z"},{"name":"validate / validate","status":"completed","conclusion":"success","started_at":"2026-10-02T03:13:35Z"}]}' > "$WORK/checkruns.json"
timeout 15 "$HERE/pr_state_watch.sh" opencharly/x 1 --interval 60 --timeout 1 > "$WORK/out_psw_ss.txt" 2>&1
rc=$?
[ "$rc" -ne 2 ] && ok "pr_state_watch: a superseded FAILURE is not terminal (rc=$rc)" \
  || bad "pr_state_watch superseded" "exited 2 (false BLOCKED): $(cat "$WORK/out_psw_ss.txt")"
grep -q 'superseded by a newer SUCCESS' "$WORK/out_psw_ss.txt" \
  && ok "pr_state_watch: names the superseded FAILURE explicitly" \
  || bad "pr_state_watch superseded report" "$(cat "$WORK/out_psw_ss.txt")"
grep -q 'check-runs?filter=all' "$HERE/pr_state_watch.sh" \
  && ok "pr_state_watch: reads check-runs with filter=all (the default hides the older attempt)" \
  || bad "filter=all read" "check-runs call drops filter=all, so a superseded attempt is invisible"
rm -f "$WORK/checkruns.json" "$WORK/headruns.json" "$WORK/comments.json"

# 9 ── pr_watch_many: a terminal result is reported (stub pr_state_watch.sh beside a copy)
cat > "$WORK/pr_state_watch.sh" <<'PSW'
#!/usr/bin/env bash
exit 2
PSW
chmod +x "$WORK/pr_state_watch.sh"
cp "$HERE/pr_watch_many.sh" "$WORK/pr_watch_many.sh"
cp "$HERE/_watch_common.sh" "$WORK/_watch_common.sh"
ALLOW_FAST_POLL=1 "$WORK/pr_watch_many.sh" --interval 1 --timeout 4 opencharly/x 1 > "$WORK/out.txt" 2>&1
grep -q '^TERMINAL BLOCKED (exit 2) opencharly/x#1' "$WORK/out.txt" \
  && ok "pr_watch_many: reports a terminal BLOCKED" || bad "pr_watch_many terminal" "$(cat "$WORK/out.txt")"

# ── 10..13: the AUTO-REARM loop, the single-instance lock, the rate-limit guard ──
# Every auto-rearm assertion uses WATCH_REARM_HOOK so NO real successor is ever spawned
# (a real one would detach a stray watcher). The hook logs one line per call; the count
# IS the assertion (exactly one successor, never a stack).
REARM_LOG="$WORK/rearm.log"
printf '#!/usr/bin/env bash\necho "REARM $*" >> %s\n' "$REARM_LOG" > "$WORK/rearm-hook.sh"
chmod +x "$WORK/rearm-hook.sh"
export WATCH_REARM_HOOK="$WORK/rearm-hook.sh"
export WATCH_RUNTIME_DIR="$WORK/rt"; mkdir -p "$WATCH_RUNTIME_DIR"
rearm_count() { grep -c '^REARM ' "$REARM_LOG" 2>/dev/null || echo 0; }
rm -f "$REARM_LOG"

# (fire_after_arm / seed_no_run are defined ONCE near the fixture helpers above.)

# A DELTA `verdict` fire must re-arm so a watch stays alive.
reset_calls; seed_no_run; fire_after_arm 444
"$HERE/gh_watch.sh" --events verdict --interval 1 --timeout 6 --auto-rearm opencharly/x#1 >/dev/null 2>&1
rc=$?
eq "auto-rearm: a DELTA fire exits 0" "$rc" 0
eq "auto-rearm: a DELTA fire spawns EXACTLY ONE successor" "$(rearm_count)" 1
reset_calls

# A TIMEOUT (no event) MUST also keep a watch alive → exactly one successor.
rm -f "$REARM_LOG"; seed_no_run
"$HERE/gh_watch.sh" --events verdict --interval 1 --timeout 2 --auto-rearm opencharly/x#1 >/dev/null 2>&1
eq "auto-rearm: a TIMEOUT re-arms (exit 4)" "$?" 4
eq "auto-rearm: a TIMEOUT spawns EXACTLY ONE successor" "$(rearm_count)" 1

# --no-rearm (the default) spawns NO successor — per-event notify is one-shot.
rm -f "$REARM_LOG"; reset_calls; seed_no_run; fire_after_arm 555
"$HERE/gh_watch.sh" --events verdict --interval 1 --timeout 6 --no-rearm opencharly/x#1 >/dev/null 2>&1
eq "--no-rearm: a DELTA fire still exits 0" "$?" 0
eq "--no-rearm: spawns NO successor" "$(rearm_count)" 0
reset_calls

# A STATE fire (merged) must NOT re-arm — a successor would IMMEDIATELY re-fire it
# (livelock). This is the guard that keeps --auto-rearm from burning the API budget.
rm -f "$REARM_LOG"
gql_doc opencharly/x#1 "$(gql_item opencharly x 1 pr open true 0 h1 "$NOW")" > "$WORK/gql.json"
"$HERE/gh_watch.sh" --events merged --interval 1 --timeout 3 --auto-rearm opencharly/x#1 >/dev/null 2>&1
eq "auto-rearm: a STATE (merged) fire exits 0" "$?" 0
eq "auto-rearm: a STATE fire spawns NO successor (no livelock)" "$(rearm_count)" 0

# A TAKEOVER (SIGTERM → exit 143) must NOT re-arm: a successor would immediately take
# the lock back from the displacing arm → perpetual ping-pong. This exercises the
# trap's exit-code capture (a `trap 'cleanup; watch_on_exit_common $?'` would lose 143).
# Arm a long-running --auto-rearm watcher in the BACKGROUND, TERM it, and assert the
# re-arm hook never fired.
rm -f "$REARM_LOG"
"$HERE/gh_watch.sh" --events verdict --interval 30 --timeout 60 --auto-rearm opencharly/x#1 >/dev/null 2>&1 &
TPID=$!
sleep 1
kill -TERM "$TPID" 2>/dev/null
wait "$TPID" 2>/dev/null; trc=$?
eq "auto-rearm: a SIGTERM takeover exits 143" "$trc" 143
eq "auto-rearm: a takeover spawns NO successor (no ping-pong)" "$(rearm_count)" 0

# ── the SAME takeover guard for pr_watch_many.sh, whose trap needed the $?-capture fix ──
# gh_watch.sh uses watch_install_trap (no `cleanup`); pr_watch_many.sh's EXIT trap runs
# `cleanup` FIRST, so a `watch_on_exit_common $?` would read cleanup's status and wrongly
# re-arm on a takeover. REPO-ONLY mode (no PR pairs) so signal 0 is inactive and only the
# trap path is exercised (a PR pair would fire signal 0 via the stub and exit 0 first).
rm -f "$REARM_LOG"
cp "$HERE/pr_watch_many.sh" "$WORK/pr_watch_many.sh"
cp "$HERE/_watch_common.sh" "$WORK/_watch_common.sh"
"$WORK/pr_watch_many.sh" --repos opencharly/x --interval 30 --timeout 60 --auto-rearm >/dev/null 2>&1 &
MPID=$!
sleep 1
kill -TERM "$MPID" 2>/dev/null
wait "$MPID" 2>/dev/null; mrc=$?
eq "pr_watch_many: a SIGTERM takeover exits 143" "$mrc" 143
eq "pr_watch_many: a takeover spawns NO successor (the trap $?-capture)" "$(rearm_count)" 0

# ── pr_watch_many.sh's OWN verdict-fire re-arm (the WAKE VERDICT arm) ──
# The SIGTERM test above covers the EXIT-trap path; this covers the fire site. A REPO
# run completing at/after arm must re-arm a successor (the same "watch stays alive"
# property gh_watch asserts). Removing the `watch_rearm_now` call at the WAKE VERDICT
# arm fails THIS assertion — the previous coverage gap (a repo-only SIGTERM test never
# reached the fire site). The same DELTA stub drives both: an empty seed, then a
# NOW-dated completed run on the next poll.
rm -f "$REARM_LOG"; reset_calls; printf '[]' > "$WORK/runs.json"
( sleep 1; run_old 777 "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$WORK/runs_after.json" ) &
"$WORK/pr_watch_many.sh" --repos opencharly/x --interval 1 --timeout 8 --auto-rearm >/dev/null 2>&1
eq "pr_watch_many --auto-rearm: a repo run completed AFTER arm fires" "$?" 0
eq "pr_watch_many --auto-rearm: a verdict fire spawns EXACTLY ONE successor" "$(rearm_count)" 1

# --no-rearm (the default) spawns NO successor for the same fire (one-shot notify).
rm -f "$REARM_LOG"; reset_calls; printf '[]' > "$WORK/runs.json"
( sleep 1; run_old 778 "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$WORK/runs_after.json" ) &
"$WORK/pr_watch_many.sh" --repos opencharly/x --interval 1 --timeout 8 --no-rearm >/dev/null 2>&1
rc=$?
eq "pr_watch_many --no-rearm: a verdict fire exits 0" "$rc" 0
eq "pr_watch_many --no-rearm: a verdict fire spawns NO successor" "$(rearm_count)" 0
reset_calls

# ── the fire site re-arms BEFORE it prints (the ordering guarantee, so the successor ──
# ── is ALIVE before the agent is woken). The EXIT trap is a BACKSTOP for the same    ──
# ── successor, so a COUNT alone cannot distinguish the two paths. This asserts the    ──
# ── ORDER: the hook writes its marker to STDOUT, so it must PRECEDE the WAKE line.    ──
# Removing the fire-site `watch_rearm_now` leaves only the trap's marker, which lands
# AFTER the WAKE line -> this FAILS (the coverage the reviewer asked for).
cat > "$WORK/order-hook.sh" <<OH
#!/usr/bin/env bash
echo "REARM-ORDER"
echo "REARM \$*" >> "$REARM_LOG"
OH
chmod +x "$WORK/order-hook.sh"
rm -f "$REARM_LOG"; reset_calls; printf '[]' > "$WORK/runs.json"
( sleep 1; run_old 779 "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$WORK/runs_after.json" ) &
WATCH_REARM_HOOK="$WORK/order-hook.sh" "$WORK/pr_watch_many.sh" --repos opencharly/x \
  --interval 1 --timeout 8 --auto-rearm > "$WORK/order.log" 2>&1
rn="$(grep -n 'REARM-ORDER' "$WORK/order.log" | head -1 | cut -d: -f1)"
wn="$(grep -n 'WAKE VERDICT' "$WORK/order.log" | head -1 | cut -d: -f1)"
{ [ -n "$rn" ] && [ -n "$wn" ] && [ "$rn" -lt "$wn" ]; } \
  && ok "pr_watch_many --auto-rearm: the fire site re-arms BEFORE printing the WAKE (successor alive before the wake)" \
  || bad "pr_watch_many re-arm ordering" "REARM-ORDER line=[$rn] WAKE line=[$wn] (REARM must precede WAKE)"
reset_calls

# ── a REAL successor hand-off (no hook): the successor carries the hand-off env ──
# This drives the ACTUAL `watch_rearm` spawn and asserts the child's environment carries
# WATCH_INHERITED_LOCK=1 (the successor already holds the inherited flock) and
# WATCH_PREDECESSOR_PID, and does NOT carry a stale WATCH_REARMED latch (which would
# suppress the child's own future re-arm). A `WATCH_REARMED=1` used as the signal would
# clobber here. (The ATOMIC HAND-OFF itself — that the child genuinely holds fd 9 — is
# asserted separately below; see "the successor INHERITS the flock".)
PROBE="$WORK/probe-succ"
cat > "$PROBE" <<'PS'
#!/usr/bin/env bash
printf 'inherited=%s pred=%s rearmed=%s\n' \
  "${WATCH_INHERITED_LOCK:-unset}" \
  "$([ -n "${WATCH_PREDECESSOR_PID:-}" ] && echo set || echo unset)" \
  "${WATCH_REARMED:-unset}" >> "$PROBE_LOG"
PS
chmod +x "$PROBE"
PROBE_LOG="$WORK/succ.log"; export PROBE_LOG; rm -f "$PROBE_LOG"
WATCH_REARM_HOOK= bash -c '
  . "$1/_watch_common.sh"
  watch_rearm "$2"
' _ "$HERE" "$PROBE"
sleep 1
grep -q 'inherited=1 pred=set rearmed=unset' "$PROBE_LOG" 2>/dev/null \
  && ok "auto-rearm: the real successor is spawned with WATCH_INHERITED_LOCK=1 + a predecessor PID (inherits, no takeover)" \
  || bad "real successor env" "got: $([ -f "$PROBE_LOG" ] && cat "$PROBE_LOG" || echo '<no log>')"

# ── the lock-fd liveness: a hung POLL CHILD must not hold the lock after the parent exits ──
# A child that inherited fd 9 would keep the flock alive after the main script died, so a
# bounded `flock -w 5 9` takeover would time out. This drives the REAL poll helpers
# (`watch_rate_remaining` / `watch_run_latest`) against a hung `gh` and asserts a takeover
# still succeeds. Fails without the `exec 9>&-` in those helpers.
HUNGBIN="$WORK/hungbin"; mkdir -p "$HUNGBIN"
printf '#!/usr/bin/env bash\nsleep 20\n' > "$HUNGBIN/gh"; chmod +x "$HUNGBIN/gh"
HUNG_KEY="$(watch_key hung-lock-test)"
(
  PATH="$HUNGBIN:$PATH" bash -c '
    . "$1/_watch_common.sh"
    watch_lock "$2" --takeover || exit 1
    watch_rate_remaining >/dev/null 2>&1 &   # spawns the hung `gh` child
    watch_run_latest owner/repo WF >/dev/null 2>&1 &
    command sleep 0.5
  ' _ "$HERE" "$HUNG_KEY" )   # parent exits here; the hung children linger
sleep 1
( . "$HERE/_watch_common.sh"; watch_lock "$HUNG_KEY" --takeover ) \
  && ok "lock-fd: a hung poll child does not hold the lock after the parent exits" \
  || bad "lock-fd liveness" "a hung gh child kept the flock (fd 9 leaked)"
pkill -f "$HUNGBIN/gh" 2>/dev/null

# ── the AUTO-REARM hand-off is ATOMIC: the successor INHERITS the flock (fd 9). ──
# RCA for the field report (three identical-arg watchers live at once): the successor
# used to be spawned with fd 9 CLOSED and WAITED for the lock, so a holder + waiter
# coexisted and a `--takeover` raced the waiter. The fix INHERITS fd 9 (the same open
# file description → the flock is held ACROSS the hand-off with no gap and no waiter)
# and marks the child WATCH_INHERITED_LOCK=1 + WATCH_PREDECESSOR_PID. This drives the
# REAL watch_rearm and asserts, from the probe child, that it (a) is marked INHERITED,
# (b) ALREADY HOLDS the flock (fd 9 is open and `flock -n 9` succeeds), and (c) carries
# the predecessor PID (so it will not poll until the predecessor exits) — the three
# properties whose absence reproduced the stacking.
PROBE2="$WORK/probe-inherit"
cat > "$PROBE2" <<'PI'
#!/usr/bin/env bash
inherited="${WATCH_INHERITED_LOCK:-unset}"
pred="${WATCH_PREDECESSOR_PID:-unset}"
holds=no; flock -n 9 2>/dev/null && holds=yes     # fd 9 inherited + already locked
printf 'inherited=%s holds_fd9=%s pred_set=%s\n' "$inherited" "$holds" \
  "$([ "$pred" != unset ] && echo yes || echo no)" >> "$PROBE2_LOG"
PI
chmod +x "$PROBE2"
PROBE2_LOG="$WORK/inherit.log"; export PROBE2_LOG; rm -f "$PROBE2_LOG"
bash -c '
  . "$1/_watch_common.sh"
  K="$(watch_key inherit-test)"
  watch_lock "$K" --takeover || exit 1
  WATCH_REARM_HOOK= watch_rearm "$2"
  command sleep 0.5
' _ "$HERE" "$PROBE2"
sleep 1
grep -q 'inherited=1 holds_fd9=yes pred_set=yes' "$PROBE2_LOG" 2>/dev/null \
  && ok "auto-rearm: the successor INHERITS the flock (fd 9 held across the hand-off, no gap, no waiter)" \
  || bad "atomic hand-off" "got: $([ -f "$PROBE2_LOG" ] && cat "$PROBE2_LOG" || echo '<no log>')"

# ── the single-instance lock: among two SEPARATE processes, exactly one holds ──
# A probe sources _watch_common.sh, acquires the lock (taking over any peer), reports
# the holder, then holds briefly. `sleep N 9>&-` is ESSENTIAL — the sleep child must
# not inherit the lock fd, or the probe would never release the lock (the same
# fd-inheritance class the scripts guard against).
cat > "$WORK/lock-probe.sh" <<'LP'
#!/usr/bin/env bash
# shellcheck source=/dev/null
. "$1"; shift
key="$1"
watch_lock "$key" --takeover || { echo "REFUSED"; exit 1; }
echo "HOLDER $$"
sleep "${LOCK_HOLD:-3}" 9>&-
LP
chmod +x "$WORK/lock-probe.sh"
LOCK_KEY="$(watch_key lock-probe-test)"
LOCK_HOLD=4 "$WORK/lock-probe.sh" "$HERE/_watch_common.sh" "$LOCK_KEY" > "$WORK/lp1.out" 2>&1 &
LP1=$!
sleep 1
H1="$(cat "$(watch_holder_file "$LOCK_KEY")" 2>/dev/null)"
LOCK_HOLD=4 "$WORK/lock-probe.sh" "$HERE/_watch_common.sh" "$LOCK_KEY" > "$WORK/lp2.out" 2>&1 &
LP2=$!
# The takeover is multi-step (kill the peer → wait for it to die → acquire): poll for
# the handoff rather than sampling once, which would race the displacement.
H2=""
i=0
while [ "$i" -lt 40 ]; do
  H2="$(cat "$(watch_holder_file "$LOCK_KEY")" 2>/dev/null)"
  [ -n "$H2" ] && [ "$H2" != "$H1" ] && break
  command sleep 0.1; i=$((i+1))
done
[ -n "$H1" ] && [ -n "$H2" ] && [ "$H1" != "$H2" ] \
  && ok "lock: the second arm displaces the first (holder $H1 → $H2)" \
  || bad "lock takeover" "holders were [$H1] then [$H2]"
kill -0 "$LP1" 2>/dev/null && bad "lock: first probe still alive" "not displaced" || ok "lock: the first holder was displaced"
kill "$LP1" "$LP2" 2>/dev/null; wait "$LP1" "$LP2" 2>/dev/null

# ── the rate-limit guard: below threshold, BACK OFF and do not poll/fire ──
export ALLOW_FAST_POLL=1
printf '#!/usr/bin/env bash\necho 5\n' > "$WORK/rate-low.sh"; chmod +x "$WORK/rate-low.sh"
printf '#!/usr/bin/env bash\necho 0\n' > "$WORK/rate-zero.sh"; chmod +x "$WORK/rate-zero.sh"
printf '#!/usr/bin/env bash\necho 99999\n' > "$WORK/rate-ok.sh"; chmod +x "$WORK/rate-ok.sh"
SLEEP_LOG="$WORK/sleep.log"
# the sleep hook records the requested seconds but sleeps only a hair, so the test is fast
printf '#!/usr/bin/env bash\necho "SLEEP $1" >> %s\ncommand sleep 0.05\n' "$SLEEP_LOG" > "$WORK/sleep-hook.sh"
chmod +x "$WORK/sleep-hook.sh"
export WATCH_SLEEP_HOOK="$WORK/sleep-hook.sh"
export WATCH_RATE_MIN=200 WATCH_RATE_BACKOFF_FACTOR=2

rm -f "$SLEEP_LOG"; export WATCH_RATE_HOOK="$WORK/rate-low.sh"
"$HERE/gh_watch.sh" --events verdict --interval 5 --timeout 1 opencharly/x#1 >/dev/null 2>&1
rc=$?
eq "rate-limit: below threshold TIMES OUT without firing" "$rc" 4
grep -q '^SLEEP 10$' "$SLEEP_LOG" 2>/dev/null \
  && ok "rate-limit: backs off the backoff-factor × interval (5 × 2 → 10s)" \
  || bad "rate-limit backoff" "no 2x backoff seen; log: $(cat "$SLEEP_LOG" 2>/dev/null)"

# ── a genuine exhaustion (remaining=0) is a HARD ABORT (exit 7), never a backoff/retry ──
printf '%s' "$(( $(date +%s) + 600 ))" > "$WORK/reset.txt"
export WATCH_RATE_HOOK="$WORK/rate-zero.sh"
"$HERE/gh_watch.sh" --events verdict --interval 60 --timeout 5 opencharly/x#1 >/dev/null 2>&1
eq "rate-limit: remaining=0 ABORTS non-zero (exit 7)" "$?" 7

rm -f "$SLEEP_LOG"; export WATCH_RATE_HOOK="$WORK/rate-ok.sh"; reset_calls; seed_no_run; fire_after_arm 666
"$HERE/gh_watch.sh" --events verdict --interval 1 --timeout 6 opencharly/x#1 >/dev/null 2>&1
eq "rate-limit: healthy quota polls and fires normally" "$?" 0
reset_calls
unset ALLOW_FAST_POLL WATCH_SLEEP_HOOK WATCH_RATE_HOOK WATCH_RATE_MIN WATCH_RATE_BACKOFF_FACTOR

echo
if [ "$FAILS" -eq 0 ]; then
  echo "PASS — all watcher-family assertions passed"
  exit 0
else
  echo "FAIL — $FAILS assertion(s) failed"
  exit 1
fi
