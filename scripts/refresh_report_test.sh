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
#   R-STATUS     the report's status block IS the commit's status block: the same files, with
#                the same codes, as the staged commit carries.
#   R-ONE-STAGE  the run stages exactly ONCE (R2 — one implementation of a step, not two).
#   R-COUNTS     the published body's counts are the SHIPPED counters' counts — the numbers
#                are data the body renders, not text the body happens to contain.
#
# HOW IT PROVES IT. The test EXTRACTS the shipped staging step, the shipped snapshot step
# and the shipped BUMPED/SKILLS/FILES/ADDED/REMOVED/MODIFIED counters from
# `.github/workflows/refresh.yml`, and runs them against a FIXTURE repo holding one of each
# class: a brand-new file under a brand-new directory (the case that read `??`), a removed
# file and a modified file. It never re-implements the workflow — it reads the shipped lines
# — so a change to the workflow's own logic is followed, not second-guessed.
#
# THE RED ARMS mutate a COPY of the shipped workflow and require each mutation to turn this
# suite RED. A test that cannot fail proves nothing (R7). The two mutations are the two
# rules: the staging moved back after the snapshot, and the staging duplicated. An arm that
# does NOT turn the suite red is a FINDING, and the process exits non-zero.
#
# THE META-ARM proves that failure path at the PROCESS boundary: this script re-runs ITSELF
# as a subprocess with its arms made undetectable, and requires that subprocess to EXIT
# NON-ZERO. Checking a function's return value would not do — the defect this suite's
# first version shipped was precisely that an arm's failure never reached the exit code,
# and only the exit code is what a gate reads.
#
# usage:
#   bash scripts/refresh_report_test.sh [--workflow FILE] [--self-test]
#
#   --workflow FILE  check FILE instead of the shipped workflow (used to run this suite
#                    against the PRE-FIX workflow, which is its own red case)
#   --self-test      additionally run the red arms; each must turn the suite red
set -uo pipefail

# LC_ALL=C: `sort` is locale-dependent, so the order the report is compared in would
# otherwise depend on the machine that ran the suite — and the pasted evidence would not
# be reproducible. C ordering is byte order, and it is the same everywhere.
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
# The script re-invokes ITSELF (the meta-arm), so it needs its own path in a form that
# survives any working directory: an absolute path.
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

WF="$REPO/.github/workflows/refresh.yml"
SELFTEST=0
# RRT_FORCE_NOOP_ARM: the arms are made undetectable on purpose. It exists for ONE caller —
# this script's own meta-arm, which re-runs this script as a subprocess to prove that an
# undetected arm makes the PROCESS exit non-zero, not merely that a function returns
# non-zero. It is not a way to skip the arms: a caller that sets it still gets a RED run.
RRT_FORCE_NOOP_ARM=0
while [ $# -gt 0 ]; do
  case "$1" in
    --workflow) WF="${2:?--workflow needs a file}"; shift 2 ;;
    --self-test) SELFTEST=1; shift ;;
    --force-noop-arm) RRT_FORCE_NOOP_ARM=1; shift ;;
    -h|--help) sed -n '2,36p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "usage: bash scripts/refresh_report_test.sh [--workflow FILE] [--self-test]" >&2; exit 2 ;;
  esac
done

FAILS=0
SELF_TEST_FAILS=0
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
  # The three changes are all UNSTAGED, which is the state the run finds them in: the
  # generator leaves a new file untracked, a removed file gone from the worktree and a
  # modified file edited, and the run is what stages them.
  rm -f "$d/doomed.txt"
}

# The three logs the shipped step reads. The refresh log's first line is indented and
# starts with a lowercase letter, which is what the shipped BUMPED counter counts.
#
# They live OUTSIDE the fixture repository, on purpose: a log inside the repo is an
# untracked file the fixture would stage and count, and the suite would then be grading
# its own scaffolding instead of the workflow's.
make_fixture_logs() {
  local d="$1"
  mkdir -p "$d"
  printf '  opencharly/spec -> v0.2026296.1338\n' > "$d/refresh.log"
  printf 'refresh-refs: 1 pin(s) advanced, 0 unresolved\n' >> "$d/refresh.log"
  printf 'Downloading opencharly/sdk...\ngenerated 1 file\n' > "$d/generate.log"
  printf 'consumer-currency: 1 consumer(s) read, 0 behind\n' > "$d/consumer-currency.log"
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

# The SHIPPED counters, evaluated on the fixture's status and the fixture's refresh log.
# The lines are READ OUT of the workflow and evaluated here — nothing is re-implemented.
# Prints "BUMPED SKILLS FILES ADDED REMOVED MODIFIED".
eval_counters() {
  local wf="$1" logs="$2" status="$3" lines
  lines="$(grep -E '^[[:space:]]*(BUMPED|SKILLS|FILES|ADDED|REMOVED|MODIFIED)=' "$wf" \
            | sed -e "s#/tmp/refresh\.log#$logs/refresh.log#g")"
  (
    STATUS="$status"
    export STATUS
    eval "$lines"
    printf '%s %s %s %s %s %s' \
      "${BUMPED:-0}" "${SKILLS:-0}" "${FILES:-0}" "${ADDED:-0}" "${REMOVED:-0}" "${MODIFIED:-0}"
  )
}

# --------------------------------------------------------------------- the checker
# check_workflow <workflow-file> <label> — 0 when the workflow satisfies every rule.
# The return value is the NUMBER of findings, so "red" and "how red" are one number.
check_workflow() {
  local wf="$1" label="$2"
  local before=$FAILS
  local stage_lines snap_lines count_lines
  local stage_first snap_line

  if [ ! -f "$wf" ]; then
    bad "[$label] the workflow file does not exist: $wf"
    return $((FAILS - before))
  fi

  stage_lines="$(grep -nE '^[[:space:]]*git add -A[[:space:]]*$' "$wf" | cut -d: -f1 | tr '\n' ' ')"
  snap_lines="$(grep -nE '^[[:space:]]*STATUS=\$\(git status --porcelain' "$wf" | cut -d: -f1 | tr '\n' ' ')"
  count_lines="$(grep -E '^[[:space:]]*(BUMPED|SKILLS|FILES|ADDED|REMOVED|MODIFIED)=' "$wf")"

  if [ -z "$snap_lines" ]; then
    bad "[$label] the workflow has no STATUS=\$(git status --porcelain ...) snapshot"
    return $((FAILS - before))
  fi
  if [ -z "$count_lines" ]; then
    bad "[$label] the workflow has no BUMPED/SKILLS/FILES/ADDED/REMOVED/MODIFIED counters"
    return $((FAILS - before))
  fi

  # --- R-ONE-STAGE -------------------------------------------------------------------
  local n_stage
  n_stage="$(printf '%s\n' "$stage_lines" | grep -c '[0-9]' || true)"
  n_stage="${n_stage:-0}"
  if [ "$n_stage" -eq 1 ]; then
    ok "[$label] the run stages exactly once (line $(printf '%s' "$stage_lines" | tr -d ' '))"
  elif [ "$n_stage" -eq 0 ]; then
    bad "[$label] the run never stages: the snapshot reports unstaged codes (?? / ' M') that the commit does not carry"
  else
    bad "[$label] the run stages $n_stage times (lines $(printf '%s' "$stage_lines" | tr -d ' ')) — one implementation of a step, not several"
  fi

  stage_first="$(printf '%s\n' "$stage_lines" | tr -d ' ' | cut -d' ' -f1)"
  snap_line="$(printf '%s\n' "$snap_lines" | tr -d ' ' | cut -d' ' -f1)"

  # --- R-STATUS ----------------------------------------------------------------------
  # Run the SHIPPED steps against the fixture, in the SHIPPED order, and compare the
  # report's block with the codes the commit carries.
  local fx logs status report_norm commit_norm
  fx="$(mktemp -d "$WORK/fixture.XXXXXX")"
  logs="$(mktemp -d "$WORK/logs.XXXXXX")"
  make_fixture "$fx"
  make_fixture_logs "$logs"

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
  fi

  if printf '%s\n' "$status" | grep -q '^??'; then
    bad "[$label] the report still lists an untracked (??) file — a code the legend does not define"
  else
    ok "[$label] the report lists no untracked (??) file"
  fi

  # --- the shipped counters ------------------------------------------------------------
  # The expectation is DERIVED FROM THE COMMIT, not hard-coded: added = the commit's `A`
  # entries, removed = its `D` entries, modified = its `M` entries, files = its entries,
  # skills = its entries naming a SKILL.md. A hard-coded tuple would only say the
  # fixture happens to hold one of each class; a derived one says the numbers the run
  # publishes DESCRIBE the commit the run makes. That is the property that broke: the
  # counters were right by luck while the codes were wrong.
  local counts bumped skills files added removed modified
  local want_files want_added want_removed want_modified want_skills
  counts="$(eval_counters "$wf" "$logs" "$status")"
  read -r bumped skills files added removed modified <<<"$counts"
  want_files="$(printf '%s\n' "$commit_norm" | grep -c .)"
  want_added="$(printf '%s\n' "$commit_norm" | grep -c '^A ')"
  want_removed="$(printf '%s\n' "$commit_norm" | grep -c '^D ')"
  want_modified="$(printf '%s\n' "$commit_norm" | grep -c '^M ')"
  want_skills="$(printf '%s\n' "$commit_norm" | grep -c 'SKILL.md')"
  if [ "$files" = "$want_files" ] && [ "$added" = "$want_added" ] \
     && [ "$removed" = "$want_removed" ] && [ "$modified" = "$want_modified" ] \
     && [ "$skills" = "$want_skills" ]; then
    ok "[$label] the shipped counters describe the commit ($files file(s), $added added, $removed removed, $modified modified, $skills skill(s))"
  else
    bad "[$label] the shipped counters do NOT describe the commit"
    printf '        counters: %s files / %s added / %s removed / %s modified / %s skills\n' \
      "$files" "$added" "$removed" "$modified" "$skills" >&2
    printf '        commit  : %s files / %s added / %s removed / %s modified / %s skills\n' \
      "$want_files" "$want_added" "$want_removed" "$want_modified" "$want_skills" >&2
  fi

  # --- the emitted artifact, at its own boundary ------------------------------------
  check_published_body "$wf" "$fx" "$logs" "$status" "$label" \
    "$bumped" "$skills" "$files" "$added" "$removed" "$modified" || true

  return $((FAILS - before))
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

# A mutation that changes NOTHING — the control for the arms' own failure path.
mutate_noop() {
  cp "$1" "$2"
}

# run_self_test <mutation-1> <mutation-2> — 0 when every arm turned the suite red.
# The arms' findings are EXPECTED here, so they do not touch the outer counter; an
# arm that did NOT turn the suite red is the finding, and it is counted here and
# returned, so the caller can fail on it.
run_self_test() {
  local m1="$1" m2="$2"
  local saved="$SELF_TEST_FAILS"
  SELF_TEST_FAILS=0

  # The no-op override exists for the meta-arm, which needs an arm that CANNOT be
  # detected, so that the suite's own reaction to an undetected arm can be observed.
  if [ "$RRT_FORCE_NOOP_ARM" -eq 1 ]; then
    m1="mutate_noop"
    m2="mutate_noop"
  fi

  "$m1" "$WF" "$WORK/arm-stage-after-snapshot.yml"
  if check_workflow "$WORK/arm-stage-after-snapshot.yml" "arm:staging-after-snapshot" >/dev/null 2>&1; then
    printf '  FAIL  red arm %s did NOT turn the suite red\n' "'staging moved after the snapshot'" >&2
    SELF_TEST_FAILS=$((SELF_TEST_FAILS + 1))
  else
    ok "red arm 'staging moved after the snapshot' turns the suite red"
  fi

  "$m2" "$WF" "$WORK/arm-duplicate-stage.yml"
  if check_workflow "$WORK/arm-duplicate-stage.yml" "arm:staging-duplicated" >/dev/null 2>&1; then
    printf '  FAIL  red arm %s did NOT turn the suite red\n' "'staging duplicated'" >&2
    SELF_TEST_FAILS=$((SELF_TEST_FAILS + 1))
  else
    ok "red arm 'staging duplicated' turns the suite red"
  fi

  local rc=$SELF_TEST_FAILS
  SELF_TEST_FAILS="$saved"
  return "$rc"
}

# --------------------------------------------------- the published body, at its boundary
# The PR body IS this workflow's emitted artifact. Extract the shipped body-assembly
# block, run it against the fixture, and assert the body it PUBLISHES carries the
# commit's codes and the counters' numbers. Only the three /tmp inputs and the output
# path are moved into the fixture — a PATH-ONLY substitution; the logic is the shipped
# logic.
extract_body_block() {
  awk '
    { lines[NR] = $0 }
    /^[[:space:]]*\{[[:space:]]*$/ { start = NR }
    /\} > \/tmp\/pr-body\.md/ { if (start) { for (i = start; i <= NR; i++) print lines[i]; exit } }
  ' "$1"
}

check_published_body() {
  local wf="$1" fx="$2" logs="$3" status="$4" label="$5"
  local bumped="$6" skills="$7" files="$8" added="$9" removed="${10}" modified="${11}"
  local block body rc

  block="$(mktemp "$WORK/body.XXXXXX.sh")"
  extract_body_block "$wf" > "$block"
  if [ ! -s "$block" ]; then
    bad "[$label] the workflow has no body-assembly block (no '} > /tmp/pr-body.md')"
    return 1
  fi

  # The body block pastes the elision's two outputs (scripts/refresh-elide.sh), so the
  # harness runs the SHIPPED elision first — against the FIXTURE's capture, into the
  # fixture's own directory. The body this harness grades is then the body the
  # workflow actually publishes, and the fixture never depends on a stale /tmp file
  # left behind by another run.
  if [ -f "$REPO/scripts/refresh-elide.sh" ]; then
    if bash "$REPO/scripts/refresh-elide.sh" "$logs/generate.log" \
         "$logs/elide-block.txt" "$logs/elide-notice.txt" >/dev/null 2>&1; then
      :
    else
      bad "[$label] the shipped elision failed on the fixture capture"
    fi
  else
    bad "[$label] the shipped elision script scripts/refresh-elide.sh is missing"
  fi

  sed -e "s#/tmp/refresh\.log#$logs/refresh.log#g" \
      -e "s#/tmp/generate\.log#$logs/generate.log#g" \
      -e "s#/tmp/consumer-currency\.log#$logs/consumer-currency.log#g" \
      -e "s#/tmp/elide-block\.txt#$logs/elide-block.txt#g" \
      -e "s#/tmp/elide-notice\.txt#$logs/elide-notice.txt#g" \
      -e "s#} > /tmp/pr-body\.md#} > $logs/pr-body.md#" \
      "$block" > "$block.run"

  # The body block reads this repo's own deploy.yml by a RELATIVE path, so it runs in a
  # directory that has it. That directory is NOT the fixture repository: the fixture is
  # the git state under test, and scaffolding must never land in it.
  local pub
  pub="$(mktemp -d "$WORK/publish.XXXXXX")"
  mkdir -p "$pub/.github/workflows"
  cp "$REPO/.github/workflows/deploy.yml" "$pub/.github/workflows/deploy.yml"

  # The body is rendered with the SHIPPED counters' values — the ones the shipped
  # counter lines computed on the shipped status above. Nothing here is a literal.
  (
    cd "$pub" || exit 2
    BUMPED="$bumped" STATUS="$status" SKILLS="$skills" FILES="$files" \
      ADDED="$added" REMOVED="$removed" MODIFIED="$modified" \
      bash "$block.run" >/dev/null 2>&1
  )
  rc=$?
  body="$logs/pr-body.md"
  if [ "$rc" -ne 0 ] || [ ! -s "$body" ]; then
    bad "[$label] the shipped body block did not produce a body (rc=$rc)"
    return 1
  fi

  if grep -qF "A  newdir/SKILL.md" "$body"; then
    ok "[$label] the PUBLISHED body carries the added file as 'A'"
  else
    bad "[$label] the PUBLISHED body does NOT carry the added file as 'A'"
    grep -m 3 -nF 'newdir/SKILL.md' "$body" >&2
    return 1
  fi
  if grep -qE '^\?\? ' "$body"; then
    bad "[$label] the PUBLISHED body still carries an untracked (??) line"
    return 1
  fi
  ok "[$label] the PUBLISHED body carries no untracked (??) line"

  # R-COUNTS: the body's numbers are the shipped counters' numbers.
  if grep -qF "file(s) total (added $added, removed $removed, modified $modified)" "$body"; then
    ok "[$label] the PUBLISHED body's file counts are the shipped counters' counts"
  else
    bad "[$label] the PUBLISHED body's file counts are NOT the shipped counters' counts"
    grep -m 3 -nF 'file(s) total' "$body" >&2
    return 1
  fi

  # ...and they are DATA, not text: handing the body a different count must change
  # what it publishes. Without this, the check above would pass against a body that
  # hard-codes its numbers, and the counters would feed nothing.
  (
    cd "$pub" || exit 2
    BUMPED="$bumped" STATUS="$status" SKILLS="$skills" FILES="$files" \
      ADDED=7 REMOVED="$removed" MODIFIED="$modified" \
      bash "$block.run" >/dev/null 2>&1
  )
  if grep -qF "file(s) total (added 7, removed $removed, modified $modified)" "$logs/pr-body.md"; then
    ok "[$label] the PUBLISHED body's counts follow the counters it is handed"
  else
    bad "[$label] the PUBLISHED body's counts do NOT follow the counters it is handed"
    grep -m 3 -nF 'file(s) total' "$logs/pr-body.md" >&2
    return 1
  fi

  return 0
}

printf 'refresh_report_test.sh — the shipped workflow: %s\n' "$WF"
check_workflow "$WF" "shipped" || true
SHIP_FAILS=$FAILS
FAILS=0

if [ "$SELFTEST" -eq 1 ]; then
  printf '\nred arms — each mutation must turn the suite RED\n'
  if run_self_test mutate_stage_after_snapshot mutate_duplicate_stage; then
    ok "both red arms turn the suite red"
  else
    printf '  FAIL  a red arm did NOT turn the suite red\n' >&2
    SELF_TEST_FAILS=$((SELF_TEST_FAILS + 1))
  fi
  FAILS=0

  # The arms' own failure path, proved AT THE PROCESS BOUNDARY: this script is re-run as
  # a SUBPROCESS with its arms made undetectable (a mutation that cannot change the
  # workflow), and that subprocess must EXIT NON-ZERO. Checking a function's return value
  # would not do: the defect the validator found was precisely that the failure never
  # reached the exit code, and only the exit code is what a gate reads. A suite that
  # cannot fail is not coverage (R7).
  if [ "$RRT_FORCE_NOOP_ARM" -eq 0 ]; then
    printf '\nthe arms themselves — an UNDETECTED arm must make the PROCESS exit non-zero\n'
    meta_log="$WORK/meta-arm.log"
    meta_rc=0
    # The child ALWAYS runs the SHIPPED workflow, whatever this process was pointed at:
    # the property under test is a property of the SUITE, not of the workflow file. That
    # also makes the attribution exact — the child's shipped check is green, so the only
    # thing that can make it exit non-zero is the undetected arm.
    bash "$SELF" --self-test --force-noop-arm > "$meta_log" 2>&1 || meta_rc=$?
    # THREE conditions, and all are required. The non-zero exit proves the failure
    # reached the exit code; the marker in the child's own output proves the non-zero
    # exit CAME FROM THE ARM; the ABSENCE of a shipped-check failure proves the child
    # was not red for some other reason, which would make this check pass for the wrong
    # reason.
    if [ "$meta_rc" -ne 0 ] \
       && grep -q 'did NOT turn the suite red' "$meta_log" \
       && ! grep -q 'finding(s) against the shipped workflow' "$meta_log"; then
      ok "an undetected red arm makes the process exit non-zero (rc=$meta_rc)"
    else
      printf '  FAIL  an undetected red arm did NOT make the process exit non-zero (rc=%s)\n' "$meta_rc" >&2
      sed -n '1,40p' "$meta_log" >&2
      SELF_TEST_FAILS=$((SELF_TEST_FAILS + 1))
    fi
    FAILS=0
  fi
fi

if [ "$SHIP_FAILS" -ne 0 ]; then
  printf '\nFAILED: %d finding(s) against the shipped workflow\n' "$SHIP_FAILS" >&2
  exit 1
fi
if [ "$SELF_TEST_FAILS" -ne 0 ]; then
  printf '\nFAILED: %d red-arm finding(s) — an arm that did not turn the suite red, or an undetected one\n' "$SELF_TEST_FAILS" >&2
  exit 1
fi
printf '\nOK\n'
exit 0
