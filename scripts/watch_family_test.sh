#!/usr/bin/env bash
# watch_family_test.sh — self-contained coverage for the watcher family
# (pr_watch_many.sh, gh_watch.sh, _watch_common.sh). It installs a deterministic
# stub `gh` on PATH so every asserted branch is exercised WITHOUT network, then
# asserts on outcomes. Exit 0 iff every assertion passed; non-zero otherwise.
#
# Run: ./scripts/watch_family_test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILS=0
ok()  { printf 'ok   - %s\n' "$1"; }
bad() { printf 'FAIL - %s\n       %s\n' "$1" "$2"; FAILS=$((FAILS + 1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3] got [$2]"; fi; }

# --- stub gh: reads fixtures from $WATCH_TEST_DIR (only the calls the family makes)
export WATCH_TEST_DIR="$WORK"
cat > "$WORK/gh" <<'STUB'
#!/usr/bin/env bash
d="${WATCH_TEST_DIR:?}"
case "$1 $2" in
  "run list"*)
    # Sequence-aware: the FIRST `run list` (the seed read) returns runs.json; later
    # polls return runs_after.json when present. This lets a test exercise the
    # seed-vs-poll divergence (an id compare alone would false-fire) deterministically,
    # with no sleeps.
    n="$(cat "$d/ncalls" 2>/dev/null || echo 0)"; n=$((n + 1)); printf '%s' "$n" > "$d/ncalls"
    if [ "$n" -le 1 ]; then cat "$d/runs.json" 2>/dev/null || echo '[]'
    elif [ -f "$d/runs_after.json" ]; then cat "$d/runs_after.json"
    else cat "$d/runs.json" 2>/dev/null || echo '[]'; fi ;;
  "api "*)
    case "$*" in
      *"/pulls/"*"--jq .merged"*) cat "$d/merged.txt" 2>/dev/null || echo "" ;;
      *"/pulls/"*) [ "$(cat "$d/type.txt" 2>/dev/null)" = pr ] && exit 0 || exit 1 ;;
      *"/issues/"*"/comments"*) cat "$d/cc.txt" 2>/dev/null || echo "" ;;
      *"/issues/"*"--jq .state"*) cat "$d/state.txt" 2>/dev/null || echo open ;;
      *"/issues/"*"--jq .updated_at"*) date -u +%Y-%m-%dT%H:%M:%SZ ;;
      *"/issues/"*) exit 0 ;;
    esac ;;
esac
exit 0
STUB
chmod +x "$WORK/gh"
export PATH="$WORK:$PATH"
printf pr      > "$WORK/type.txt"
printf false   > "$WORK/merged.txt"
printf open    > "$WORK/state.txt"
printf 5       > "$WORK/cc.txt"
printf '[]'    > "$WORK/runs.json"

# 1 ── syntax of every family file
for s in _watch_common.sh pr_watch_many.sh gh_watch.sh; do
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

# 3 ── watch_run_latest parses id|conclusion|branch|updatedAt|createdEpoch
printf '[{"databaseId":7,"name":"charly/pr-validator","status":"completed","conclusion":"success","headBranch":"b","updatedAt":"2026-01-01T00:00:00Z","createdAt":"2026-01-01T00:00:00Z"}]' > "$WORK/runs.json"
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

# 5 ── gh_watch: STATE events fire from the baseline (deterministic, bounded)
printf true > "$WORK/merged.txt"
"$HERE/gh_watch.sh" --events merged --interval 1 --timeout 3 opencharly/x#1 >/dev/null 2>&1
eq "gh_watch: merged fires on a pre-merged PR" "$?" 0
printf false > "$WORK/merged.txt"
"$HERE/gh_watch.sh" --events merged --interval 1 --timeout 2 opencharly/x#1 >/dev/null 2>&1
eq "gh_watch: merged suppressed when not merged" "$?" 4
printf closed > "$WORK/state.txt"
"$HERE/gh_watch.sh" --events closed --interval 1 --timeout 3 opencharly/x#1 >/dev/null 2>&1
eq "gh_watch: closed fires" "$?" 0
printf open > "$WORK/state.txt"

# 6 ── gh_watch: stall gate — fires on OPEN, suppressed on CLOSED/MERGED
"$HERE/gh_watch.sh" --events stall --stallmin 0 --interval 1 --timeout 3 opencharly/x#1 >/dev/null 2>&1
eq "gh_watch: stall fires on open" "$?" 0
printf closed > "$WORK/state.txt"
"$HERE/gh_watch.sh" --events stall --stallmin 0 --interval 1 --timeout 2 opencharly/x#1 >/dev/null 2>&1
eq "gh_watch: stall suppressed on closed" "$?" 4
printf open > "$WORK/state.txt"
printf true > "$WORK/merged.txt"
"$HERE/gh_watch.sh" --events stall --stallmin 0 --interval 1 --timeout 2 opencharly/x#1 >/dev/null 2>&1
eq "gh_watch: stall suppressed on merged" "$?" 4
printf false > "$WORK/merged.txt"

# 7 ── gh_watch: SEEDED, no false fire on a pre-existing comment
printf 5 > "$WORK/cc.txt"
"$HERE/gh_watch.sh" --events comment --interval 1 --timeout 2 opencharly/x#1 >/dev/null 2>&1
eq "gh_watch: comment does not fire on a pre-existing count" "$?" 4

# 8 ── STALE-FIRE guard (the field bug). A "new" run must COMPLETE at/after arm time;
#      an id compare alone false-fires when the seed-vs-poll run CHANGES to a different
#      but still-old run. The stub's run-list output can differ between the seed read
#      (call 1) and later polls (runs_after.json), deterministically and with no sleeps.
reset_calls() { rm -f "$WORK/ncalls" "$WORK/runs_after.json"; }
run_old()  { printf '[{"databaseId":%s,"name":"charly/pr-validator","status":"completed","conclusion":"success","headBranch":"x","updatedAt":"%s","createdAt":"%s"}]' "$1" "$2" "$2"; }
OLD4="$(date -u -d '4 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
OLD3="$(date -u -d '3 hours ago' +%Y-%m-%dT%H:%M:%SZ)"

# 8a ── old seed AND a DIFFERENT old run on the next poll → MUST NOT fire
for tool in many item; do
  reset_calls
  run_old 111 "$OLD4" > "$WORK/runs.json"
  run_old 222 "$OLD3" > "$WORK/runs_after.json"
  if [ "$tool" = many ]; then
    "$HERE/pr_watch_many.sh" --interval 1 --timeout 2 --repos opencharly/x >/dev/null 2>&1; rc=$?
    eq "pr_watch_many: a DIFFERENT but still-old run never fires" "$rc" 4
  else
    "$HERE/gh_watch.sh" --events verdict --interval 1 --timeout 2 opencharly/x#1 >/dev/null 2>&1; rc=$?
    eq "gh_watch: a DIFFERENT but still-old run never fires" "$rc" 4
  fi
done

# 8b ── EMPTY/UNKNOWN seed, then a run that completed BEFORE arm → MUST NOT fire
for tool in many item; do
  reset_calls
  printf '[]' > "$WORK/runs.json"
  run_old 222 "$OLD3" > "$WORK/runs_after.json"
  if [ "$tool" = many ]; then
    "$HERE/pr_watch_many.sh" --interval 1 --timeout 2 --repos opencharly/x >/dev/null 2>&1; rc=$?
    eq "pr_watch_many: empty seed + a pre-arm run never fires" "$rc" 4
  else
    "$HERE/gh_watch.sh" --events verdict --interval 1 --timeout 2 opencharly/x#1 >/dev/null 2>&1; rc=$?
    eq "gh_watch: empty seed + a pre-arm run never fires" "$rc" 4
  fi
done

# 8c ── POSITIVE control: a run that COMPLETED AFTER arm DOES fire (proves the gate is
#       a real discriminator, not a blanket suppression). The background writer replaces
#       runs_after.json with a NOW-dated run after the arm read.
for tool in many item; do
  reset_calls
  printf '[]' > "$WORK/runs.json"
  printf '[]' > "$WORK/runs_after.json"
  ( sleep 1; run_old 333 "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$WORK/runs_after.json" ) &
  if [ "$tool" = many ]; then
    "$HERE/pr_watch_many.sh" --interval 1 --timeout 8 --repos opencharly/x >/dev/null 2>&1; rc=$?
    eq "pr_watch_many: a run completed AFTER arm fires" "$rc" 0
  else
    "$HERE/gh_watch.sh" --events verdict --interval 1 --timeout 8 opencharly/x#1 >/dev/null 2>&1; rc=$?
    eq "gh_watch: a run completed AFTER arm fires" "$rc" 0
  fi
done
reset_calls

# 9 ── pr_watch_many: a terminal result is reported (stub pr_state_watch.sh beside a copy)
cat > "$WORK/pr_state_watch.sh" <<'PSW'
#!/usr/bin/env bash
exit 2
PSW
chmod +x "$WORK/pr_state_watch.sh"
cp "$HERE/pr_watch_many.sh" "$WORK/pr_watch_many.sh"
cp "$HERE/_watch_common.sh" "$WORK/_watch_common.sh"
"$WORK/pr_watch_many.sh" --interval 1 --timeout 4 opencharly/x 1 > "$WORK/out.txt" 2>&1
grep -q '^TERMINAL BLOCKED (exit 2) opencharly/x#1' "$WORK/out.txt" \
  && ok "pr_watch_many: reports a terminal BLOCKED" || bad "pr_watch_many terminal" "$(cat "$WORK/out.txt")"

echo
if [ "$FAILS" -eq 0 ]; then
  echo "PASS — all watcher-family assertions passed"
  exit 0
else
  echo "FAIL — $FAILS assertion(s) failed"
  exit 1
fi
