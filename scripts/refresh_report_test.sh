#!/usr/bin/env bash
# refresh_report_test.sh — prove the refresh PR's report describes the commit it carries.
#
# WHY. The refresh body publishes the run's status under a legend that defines exactly three
# codes: "(`A` added, `D` removed, `M` modified)". The snapshot that block is built from was
# taken BEFORE the run staged its work, so a brand-new generated file read `??` — a code the
# legend does not define, and a code the commit does not carry. The COUNTS were right (the
# counters accept `^??` as well as `^A `), which is the worst combination: the report looked
# precise while describing something the PR was not. The `charly/pr-validator` caught it on
# opencharly/marketplace#557 and named the mechanism.
#
# THE RULES THIS HOLDS.
#   R-STATUS   the report's status block IS the commit's status block: the same files, with
#              the same codes, as the staged commit carries.
#   R-ONE-STAGE  the run stages exactly ONCE (R2 — one implementation of a step, not two).
#
# HOW IT PROVES IT. The test EXTRACTS the shipped staging step, the shipped snapshot step
# and the shipped ADDED/REMOVED/MODIFIED counters from `.github/workflows/refresh.yml`, and
# runs them against a FIXTURE repo holding one of each class: a brand-new file under a
# brand-new directory (the case that read `??`), a removed file and a modified file. It
# never re-implements the workflow — it reads the shipped lines — so a change to the
# workflow's own logic is followed, not second-guessed.
#
# THE RED ARMS mutate a COPY of the shipped workflow and require each mutation to turn this
# suite RED. A test that cannot fail proves nothing (R7). The two mutations are the two
# rules: the staging moved back after the snapshot, and the staging duplicated.
#
# usage:
#   bash scripts/refresh_report_test.sh [--workflow FILE] [--self-test]
#
#   --workflow FILE  check FILE instead of the shipped workflow (used to run this suite
#                    against the PRE-FIX workflow, which is its own red case)
#   --self-test      additionally run the red arms; each must turn the suite red
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

WF="$REPO/.github/workflows/refresh.yml"
SELFTEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --workflow) WF="${2:?--workflow needs a file}"; shift 2 ;;
    --self-test) SELFTEST=1; shift ;;
    -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "usage: bash scripts/refresh_report_test.sh [--workflow FILE] [--self-test]" >&2; exit 2 ;;
  esac
done

FAILS=0
ok()  { printf '  PASS  %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1" >&2; FAILS=$((FAILS + 1)); }

# --------------------------------------------------------------------- the fixture repo
# One of each class: a brand-new generated file under a brand-new directory (the exact shape
# that read `??`), a removed file, and a modified file.
make_fixture() {
  local d="$1"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email "test@example.com"
  git -C "$d" config user.name "refresh report test"
  printf 'base\n'   > "$d/base.txt"
  printf 'doomed\n' > "$d/doomed.txt"
  git -C "$d" add -A
  git -C "$d" commit -qm "base"
  mkdir -p "$d/newdir"
  printf 'new skill\n' > "$d/newdir/SKILL.md"
  printf 'changed\n' >> "$d/base.txt"
  git -C "$d" rm -q doomed.txt
}

# porcelain "XY path" -> "CODE path", where CODE is the EFFECTIVE status: the index column
# when it is set, else the worktree column. `??` stays `?` — it is the code that says
# "not staged", and the commit never carries it.
normalize_report() {
  awk '{
    x = substr($0, 1, 1); y = substr($0, 2, 1); path = substr($0, 4);
    code = (x != " ") ? x : y;
    print code " " path;
  }'
}

# --------------------------------------------------------------------- the checker
# check_workflow <workflow-file> <label> — 0 when the workflow satisfies both rules.
check_workflow() {
  local wf="$1" label="$2"
  local fails=0
  local stage_lines snap_lines count_lines
  local stage_first snap_line

  if [ ! -f "$wf" ]; then
    bad "[$label] the workflow file does not exist: $wf"
    return 1
  fi

  stage_lines="$(grep -nE '^[[:space:]]*git add -A[[:space:]]*$' "$wf" | cut -d: -f1 | tr '\n' ' ')"
  snap_lines="$(grep -nE '^[[:space:]]*STATUS=\$\(git status --porcelain' "$wf" | cut -d: -f1 | tr '\n' ' ')"
  count_lines="$(grep -E '^[[:space:]]*(ADDED|REMOVED|MODIFIED)=' "$wf")"

  if [ -z "$snap_lines" ]; then
    bad "[$label] the workflow has no STATUS=\$(git status --porcelain ...) snapshot"
    return 1
  fi
  if [ -z "$count_lines" ]; then
    bad "[$label] the workflow has no ADDED/REMOVED/MODIFIED counters"
    return 1
  fi

  # --- R-ONE-STAGE -------------------------------------------------------------------
  local n_stage
  n_stage="$(printf '%s\n' "$stage_lines" | grep -c '[0-9]' || true)"
  n_stage="${n_stage:-0}"
  if [ "$n_stage" -eq 1 ]; then
    ok "[$label] the run stages exactly once (line $(printf '%s' "$stage_lines" | tr -d ' '))"
  elif [ "$n_stage" -eq 0 ]; then
    bad "[$label] the run never stages: the snapshot reports unstaged codes (?? / ' M') that the commit does not carry"
    fails=$((fails + 1))
  else
    bad "[$label] the run stages $n_stage times (lines $(printf '%s' "$stage_lines" | tr -d ' ')) — one implementation of a step, not several"
    fails=$((fails + 1))
  fi

  stage_first="$(printf '%s\n' "$stage_lines" | tr -d ' ' | cut -d' ' -f1)"
  snap_line="$(printf '%s\n' "$snap_lines" | tr -d ' ' | cut -d' ' -f1)"

  # --- R-STATUS ----------------------------------------------------------------------
  # Run the SHIPPED steps against the fixture, in the SHIPPED order, and compare the
  # report's block with the codes the commit carries.
  local fx status report_norm commit_norm counts
  fx="$(mktemp -d "$WORK/fixture.XXXXXX")"
  make_fixture "$fx"

  if [ -n "$stage_first" ] && [ "$stage_first" -lt "$snap_line" ]; then
    git -C "$fx" add -A
    status="$(git -C "$fx" status --porcelain -uall)"
  else
    status="$(git -C "$fx" status --porcelain -uall)"
    git -C "$fx" add -A
  fi

  report_norm="$(printf '%s\n' "$status" | normalize_report | sort)"
  commit_norm="$(git -C "$fx" diff --cached --name-status | awk '{print $1 " " $2}' | sort)"

  if [ "$report_norm" = "$commit_norm" ]; then
    ok "[$label] the report's status codes are the commit's codes"
  else
    bad "[$label] the report's status codes are NOT the commit's codes"
    printf '        report : %s\n' "$(printf '%s' "$report_norm" | tr '\n' ';')" >&2
    printf '        commit : %s\n' "$(printf '%s' "$commit_norm" | tr '\n' ';')" >&2
    fails=$((fails + 1))
  fi

  if printf '%s\n' "$status" | grep -q '^??'; then
    bad "[$label] the report still lists an untracked (??) file — a code the legend does not define"
    fails=$((fails + 1))
  else
    ok "[$label] the report lists no untracked (??) file"
  fi

  counts="$(
    STATUS="$status"
    export STATUS
    eval "$count_lines"
    printf '%s %s %s' "${ADDED:-?}" "${REMOVED:-?}" "${MODIFIED:-?}"
  )"
  if [ "$counts" = "1 1 1" ]; then
    ok "[$label] the shipped counters read 1 added / 1 removed / 1 modified"
  else
    bad "[$label] the shipped counters read '$counts', expected '1 1 1'"
    fails=$((fails + 1))
  fi

  # --- the emitted artifact, at its own boundary ------------------------------------
  check_published_body "$wf" "$fx" "$status" "$label" || fails=$((fails + 1))

  return "$fails"
}

# --------------------------------------------------------------------- the red arms
mutate_stage_after_snapshot() {
  sed -e '/^[[:space:]]*git add -A[[:space:]]*$/d' "$1" \
    | awk '{ print; if ($0 ~ /^[[:space:]]*STATUS=\$\(git status --porcelain/) print "          git add -A" }' \
    > "$2"
}

mutate_duplicate_stage() {
  awk '{ print; if ($0 ~ /^[[:space:]]*git add -A[[:space:]]*$/) print "          git add -A" }' "$1" > "$2"
}

# --------------------------------------------------- the published body, at its boundary
# The PR body IS this workflow's emitted artifact. Extract the shipped body-assembly
# block, run it against the fixture, and assert the body it PUBLISHES carries the
# commit's codes. Only the three /tmp inputs and the output path are moved into the
# fixture — a PATH-ONLY substitution; the logic is the shipped logic.
extract_body_block() {
  awk '
    { lines[NR] = $0 }
    /^[[:space:]]*\{[[:space:]]*$/ { start = NR }
    /\} > \/tmp\/pr-body\.md/ { if (start) { for (i = start; i <= NR; i++) print lines[i]; exit } }
  ' "$1"
}

check_published_body() {
  local wf="$1" fx="$2" status="$3" label="$4"
  local block body rc

  block="$(mktemp "$WORK/body.XXXXXX.sh")"
  extract_body_block "$wf" > "$block"
  if [ ! -s "$block" ]; then
    bad "[$label] the workflow has no body-assembly block (no '} > /tmp/pr-body.md')"
    return 1
  fi

  sed -e "s#/tmp/refresh\.log#$fx/refresh.log#g" \
      -e "s#/tmp/generate\.log#$fx/generate.log#g" \
      -e "s#/tmp/consumer-currency\.log#$fx/consumer-currency.log#g" \
      -e "s#} > /tmp/pr-body\.md#} > $fx/pr-body.md#" \
      "$block" > "$block.run"

  printf '  -> opencharly/spec: v0.2026296.1338\n' > "$fx/refresh.log"
  printf 'refresh-refs: 1 pin(s) advanced, 0 unresolved\n' >> "$fx/refresh.log"
  printf 'Downloading opencharly/sdk...\ngenerated 1 file\n' > "$fx/generate.log"
  printf 'consumer-currency: 1 consumer(s) read, 0 behind\n' > "$fx/consumer-currency.log"
  mkdir -p "$fx/.github/workflows"
  cp "$REPO/.github/workflows/deploy.yml" "$fx/.github/workflows/deploy.yml"

  (
    cd "$fx" || exit 2
    BUMPED=1 STATUS="$status" SKILLS=1 FILES=3 ADDED=1 REMOVED=1 MODIFIED=1 \
      bash "$block.run" >/dev/null 2>&1
  )
  rc=$?
  body="$fx/pr-body.md"
  if [ "$rc" -ne 0 ] || [ ! -s "$body" ]; then
    bad "[$label] the shipped body block did not produce a body (rc=$rc)"
    return 1
  fi

  if grep -qF "A  newdir/SKILL.md" "$body"; then
    ok "[$label] the PUBLISHED body carries the added file as 'A'"
  else
    bad "[$label] the PUBLISHED body does NOT carry the added file as 'A'"
    grep -nF 'newdir/SKILL.md' "$body" | head -3 >&2
    return 1
  fi
  if grep -qE '^\?\? ' "$body"; then
    bad "[$label] the PUBLISHED body still carries an untracked (??) line"
    return 1
  fi
  ok "[$label] the PUBLISHED body carries no untracked (??) line"
  if grep -qF "file(s) total (added 1, removed 1, modified 1)" "$body"; then
    ok "[$label] the PUBLISHED body's file counts come from the shipped counters"
  else
    bad "[$label] the PUBLISHED body's file counts do not match the shipped counters"
    return 1
  fi
  return 0
}

printf 'refresh_report_test.sh — the shipped workflow: %s\n' "$WF"
check_workflow "$WF" "shipped" || true
SHIP_FAILS=$FAILS

if [ "$SELFTEST" -eq 1 ]; then
  printf '\nred arms — each mutation must turn the suite RED\n'
  FAILS=0
  mutate_stage_after_snapshot "$WF" "$WORK/arm-stage-after-snapshot.yml"
  if check_workflow "$WORK/arm-stage-after-snapshot.yml" "arm:staging-after-snapshot" >/dev/null 2>&1; then
    bad "red arm 'staging moved after the snapshot' did NOT turn the suite red"
  else
    ok "red arm 'staging moved after the snapshot' turns the suite red"
  fi

  FAILS=0
  mutate_duplicate_stage "$WF" "$WORK/arm-duplicate-stage.yml"
  if check_workflow "$WORK/arm-duplicate-stage.yml" "arm:staging-duplicated" >/dev/null 2>&1; then
    bad "red arm 'staging duplicated' did NOT turn the suite red"
  else
    ok "red arm 'staging duplicated' turns the suite red"
  fi
  FAILS=0
fi

if [ "$SHIP_FAILS" -ne 0 ]; then
  printf '\nFAILED: %d finding(s) against the shipped workflow\n' "$SHIP_FAILS" >&2
  exit 1
fi
printf '\nOK\n'
exit 0
