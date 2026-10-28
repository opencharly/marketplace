#!/usr/bin/env bash
# refresh_elide_test.sh — prove the refresh PR body's evidence elision is COMPLETE, and
# that the body it publishes still fits GitHub's cap.
#
# WHY THIS EXISTS. opencharly/marketplace#413 fixed an over-long refresh body by
# eliding the generator's routine per-ref progress — but it matched ONE literal shape
# (`Downloading <ref>…`). The generator prints TWO per-ref progress shapes, from two
# different modules (opencharly/spec, refs/git.go; opencharly/sdk,
# candywalk/candywalk.go), and the second was pasted whole. Five consecutive daily runs
# (2026-10-24 … 2026-10-28) then assembled a 117 KB body, GitHub rejected every one of
# them ("117183 bytes; the limit is 65536"), and the published corpus was frozen for
# five days. The fix is `scripts/refresh-elide.sh`; this suite is the control that
# would have caught the shape it missed. opencharly/marketplace#451.
#
# WHAT IT PROVES, against the SHIPPED files.
#   E-SHAPES    neither of the generator's TWO per-ref progress shapes reaches the body.
#   E-KEEP      the lines that are in no declared class — the report line, the
#               toolchain line, the resolver's warning — reach the body VERBATIM.
#   E-ARTIFACTS the generator's artifact-path list does not reach the body.
#   E-CAP       the assembled body, for a capture at the scale that broke it, is under
#               GitHub's 65536-byte cap — and the capture itself is over it, so the
#               suite is at the scale, not at a toy one.
#   E-WIRING    the workflow CALLS scripts/refresh-elide.sh and pastes BOTH of its
#               outputs, and the retired one-literal elision is gone from it.
#   E-ORDER     the body is measured and the verdict lands BEFORE the commit and the
#               push, so an over-long body is never published, and the night's advance
#               is deferred to the next run rather than dropped.
#   E-FAIL      a missing or empty capture fails loud (exit 1) instead of publishing a
#               body that claims evidence it does not have.
#
# HOW IT PROVES IT. The elision is EXTRACTED from the shipped files, never re-written:
# the suite runs the shipped `scripts/refresh-elide.sh`, and it runs the shipped body
# assembly — the `{ … } > /tmp/pr-body.md` block of the shipped workflow — against a
# fixture capture, and asserts on the body that block PUBLISHES. The body is the
# artifact, so the artifact is what is graded.
#
# THE RED ARMS mutate a COPY of the shipped files and require each mutation to turn
# this suite RED. A test that cannot fail proves nothing (R7). The four mutations are
# the four ways the change can be undone: the second progress shape admitted, the
# artifact class dropped, the workflow's call replaced by the pre-fix inline elision,
# and the size gate moved back behind the push. An arm that does NOT turn the suite red
# is a FINDING, and the process exits non-zero.
#
# THE META-ARM proves that failure path at the PROCESS boundary: this script re-runs
# ITSELF as a subprocess with its arms made undetectable, and requires that subprocess
# to EXIT NON-ZERO. Checking a function's return value would not do — only the exit
# code is what a gate reads.
#
# usage:
#   bash scripts/refresh_elide_test.sh [--workflow FILE] [--elide FILE] [--self-test]
#
#   --workflow FILE  check FILE instead of the shipped workflow
#   --elide FILE     check FILE instead of the shipped elision script
#   --self-test      additionally run the red arms; each must turn the suite red
set -uo pipefail

# LC_ALL=C: the suite compares byte counts and line counts, and `sort` is
# locale-dependent — the pasted evidence must be reproducible on any machine.
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
# The script re-invokes ITSELF (the meta-arm), so it needs its own path in a form
# that survives any working directory: an absolute path.
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

WF="$REPO/.github/workflows/refresh.yml"
ELIDE="$REPO/scripts/refresh-elide.sh"
SELFTEST=0
# RET_FORCE_NOOP_ARM: the arms are made undetectable on purpose. It exists for ONE
# caller — this script's own meta-arm, which re-runs this script as a subprocess to
# prove that an undetected arm makes the PROCESS exit non-zero, not merely that a
# function returns non-zero. It is not a way to skip the arms: a caller that sets it
# still gets a RED run.
RET_FORCE_NOOP_ARM=0
while [ $# -gt 0 ]; do
  case "$1" in
    --workflow) WF="${2:?--workflow needs a file}"; shift 2 ;;
    --elide) ELIDE="${2:?--elide needs a file}"; shift 2 ;;
    --self-test) SELFTEST=1; shift ;;
    --force-noop-arm) RET_FORCE_NOOP_ARM=1; shift ;;
    -h|--help) sed -n '2,50p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "usage: bash scripts/refresh_elide_test.sh [--workflow FILE] [--elide FILE] [--self-test]" >&2; exit 2 ;;
  esac
done

FAILS=0
SELF_TEST_FAILS=0
ok()  { printf '  PASS  %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1" >&2; FAILS=$((FAILS + 1)); }

# --------------------------------------------------------------------- the fixtures
# The small capture: every shape the elision must classify, one of each, including the
# two-space line that is NOT a path and the resolver's warning (the shape the body
# exists to surface).
make_small_log() {
  local d="$1"
  mkdir -p "$d"
  {
    printf '  GOTOOLCHAIN: local\n'
    printf 'charly: git metadata cached.\n'
    printf 'Downloading github.com/opencharly/alpha:v2026.297.0523 (files only)...\n'
    printf 'Downloading github.com/opencharly/beta:v2026.297.0524...\n'
    printf 'charly: resolving github.com/opencharly/gamma:v2026.297.0525 (3 resolved, 12 queued)\n'
    printf '  build/skills/build/SKILL.md\n'
    printf 'charly: git latest-tag fetch for https://github.com/opencharly/delta failed (dial tcp: i/o timeout); serving the persisted OFFLINE-FALLBACK tag v2026.297.0526 (resolved 2026-10-28T09:00:00Z)\n'
    printf 'marketplace generate: wrote 496 artifact(s) across 43 family(ies)\n'
  } > "$d/generate.log"
}

# The full-scale capture: the size that broke the refresh. ~600 refs x TWO progress
# lines, plus the artifact-path list — over GitHub's cap on its own.
make_full_log() {
  local d="$1"
  mkdir -p "$d"
  {
    printf '  GOTOOLCHAIN: local\n'
    printf 'charly: git metadata cached.\n'
    local i=1
    while [ "$i" -le 600 ]; do
      printf 'charly: resolving github.com/opencharly/repo-%s:v2026.297.0523 (%s resolved, 225 queued)\n' "$i" "$i"
      printf 'Downloading github.com/opencharly/repo-%s:v2026.297.0523 (files only)...\n' "$i"
      i=$((i + 1))
    done
    local j=1
    while [ "$j" -le 500 ]; do
      printf '  family-%s/skills/skill-%s/SKILL.md\n' "$((j % 43))" "$j"
      j=$((j + 1))
    done
    printf 'charly: git latest-tag fetch for https://github.com/opencharly/repo-7 failed (dial tcp: i/o timeout); serving the persisted OFFLINE-FALLBACK tag v2026.297.0523 (resolved 2026-10-28T09:00:00Z)\n'
    printf 'marketplace generate: wrote 496 artifact(s) across 43 family(ies)\n'
  } > "$d/generate.log"
}

# The other two captures the shipped body block reads.
make_body_logs() {
  local d="$1"
  mkdir -p "$d"
  {
    printf '  github.com/opencharly/spec -> v0.2026296.2332\n'
    printf '  github.com/opencharly/sdk -> v0.2026297.1851\n'
    printf 'refresh-refs: 2 pin(s) advanced, 0 unresolved\n'
  } > "$d/refresh.log"
  printf 'consumer-currency: 1 consumer(s) read, 0 behind\n' > "$d/consumer-currency.log"
}

# The shipped body-assembly block: the `{ … } > /tmp/pr-body.md` group. It is
# EXTRACTED from the workflow, so a change to the workflow's own logic is followed,
# not second-guessed.
extract_body_block() {
  awk '
    { lines[NR] = $0 }
    /^[[:space:]]*\{[[:space:]]*$/ { start = NR }
    /\} > \/tmp\/pr-body\.md/ { if (start) { for (i = start; i <= NR; i++) print lines[i]; exit } }
  ' "$1"
}

# The shipped elision CALL: the line that invokes scripts/refresh-elide.sh.
extract_elide_call() {
  grep -m 1 -E '^[[:space:]]*bash scripts/refresh-elide\.sh ' "$1" | sed -e 's/^[[:space:]]*//'
}

# --------------------------------------------------------------------- the checker
# check_suite <workflow> <elide-script> <label> — 0 when every rule holds.
# The return value is the NUMBER of findings, so "red" and "how red" are one number.
check_suite() {
  local wf="$1" elide="$2" label="$3"
  local before=$FAILS

  if [ ! -f "$wf" ]; then
    bad "[$label] the workflow file does not exist: $wf"
    return $((FAILS - before))
  fi
  if [ ! -f "$elide" ]; then
    bad "[$label] the elision script does not exist: $elide"
    return $((FAILS - before))
  fi

  # --- E-WIRING ----------------------------------------------------------------------
  local call
  call="$(extract_elide_call "$wf")"
  if [ -n "$call" ]; then
    ok "[$label] the workflow calls scripts/refresh-elide.sh"
  else
    bad "[$label] the workflow does NOT call scripts/refresh-elide.sh — the elision is not wired in"
  fi
  if grep -qF 'cat /tmp/elide-block.txt' "$wf"; then
    ok "[$label] the workflow pastes the elided block into the body"
  else
    bad "[$label] the workflow does NOT paste the elided block into the body"
  fi
  if grep -qF 'cat /tmp/elide-notice.txt' "$wf"; then
    ok "[$label] the workflow pastes the elision notice into the body"
  else
    bad "[$label] the workflow does NOT paste the elision notice into the body"
  fi
  # The retired one-literal elision — the mechanism #413 shipped and that let the second
  # shape through — must not be able to come back (R5, claim-keyed).
  if grep -qF "grep -v '^Downloading '" "$wf"; then
    bad "[$label] the retired one-literal elision is still in the workflow"
  else
    ok "[$label] the retired one-literal elision is absent from the workflow (R5 claim-keyed)"
  fi

  # --- E-ORDER -----------------------------------------------------------------------
  # The body is measured and the verdict lands BEFORE the commit and the push: an
  # over-long body is never published, and the advance is deferred to the next run
  # (which re-resolves the newest tags and regenerates the corpus) rather than dropped.
  local meas push gate
  meas="$(grep -nF 'PR_BODY_BYTES=$(wc -c < /tmp/pr-body.md)' "$wf" | cut -d: -f1 | tr '\n' ' ')"
  push="$(grep -nE '^[[:space:]]*git push -u origin HEAD' "$wf" | cut -d: -f1 | tr '\n' ' ')"
  gate="$(grep -nF 'if [ "$PR_BODY_BYTES" -gt 65536 ]' "$wf" | cut -d: -f1 | tr '\n' ' ')"
  local m p g
  m="$(printf '%s' "$meas" | tr -d ' ')"; p="$(printf '%s' "$push" | tr -d ' ')"; g="$(printf '%s' "$gate" | tr -d ' ')"
  if [ -n "$m" ] && [ -n "$p" ] && [ -n "$g" ] && [ "$m" -lt "$g" ] && [ "$g" -lt "$p" ]; then
    ok "[$label] the body is measured and the verdict lands before the push"
  else
    bad "[$label] the size-gate order is wrong (measure=$m verdict=$g push=$p) — the body must be measured and the verdict must land before the push"
  fi

  # --- E-SCRIPT: the shipped elision, on every shape ---------------------------------
  local sm logs
  sm="$(mktemp -d "$WORK/small.XXXXXX")"
  logs="$sm"
  make_small_log "$sm"
  local rc=0
  bash "$elide" "$sm/generate.log" "$sm/block.txt" "$sm/notice.txt" > "$sm/stdout.txt" 2> "$sm/stderr.txt" || rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "[$label] the elision succeeds on a complete capture"
  else
    bad "[$label] the elision failed on a complete capture (rc=$rc)"
    sed -n '1,10p' "$sm/stderr.txt" >&2
    return $((FAILS - before))
  fi

  # E-SHAPES: neither per-ref progress shape may reach the body.
  if grep -qF 'Downloading github.com/opencharly/alpha' "$sm/block.txt" || \
     grep -qF 'Downloading github.com/opencharly/beta' "$sm/block.txt" || \
     grep -qF 'charly: resolving github.com/opencharly/gamma' "$sm/block.txt"; then
    bad "[$label] a per-ref progress shape reached the elided block"
  else
    ok "[$label] neither per-ref progress shape reached the elided block"
  fi
  # E-ARTIFACTS: the artifact-path list may not reach the body.
  if grep -qF 'build/skills/build/SKILL.md' "$sm/block.txt"; then
    bad "[$label] the generator's artifact-path list reached the elided block"
  else
    ok "[$label] the generator's artifact-path list did not reach the elided block"
  fi
  # E-KEEP: everything outside the declared classes is verbatim — the report line, the
  # toolchain line, the metadata line, and above all the resolver's warning.
  local keep
  keep=0
  grep -qF 'marketplace generate: wrote 496 artifact(s) across 43 family(ies)' "$sm/block.txt" && keep=$((keep + 1))
  grep -qF '  GOTOOLCHAIN: local' "$sm/block.txt" && keep=$((keep + 1))
  grep -qF 'charly: git metadata cached.' "$sm/block.txt" && keep=$((keep + 1))
  grep -qF 'charly: git latest-tag fetch for https://github.com/opencharly/delta failed' "$sm/block.txt" && keep=$((keep + 1))
  if [ "$keep" -eq 4 ]; then
    ok "[$label] every line outside the declared classes is kept verbatim (report, toolchain, metadata, warning)"
  else
    bad "[$label] only $keep of the 4 lines outside the declared classes are kept verbatim"
  fi
  # The two-space line that is NOT a path is kept — the elision errs toward keeping.
  if grep -qF '  GOTOOLCHAIN: local' "$sm/block.txt"; then
    ok "[$label] a two-space line that is not a path is KEPT (the elision errs toward keeping)"
  else
    bad "[$label] a two-space line that is not a path was elided"
  fi
  # The notice states the counts, so what the body does not show is MEASURED.
  if grep -qF '3 line(s)' "$sm/notice.txt" && grep -qF '1 line(s)' "$sm/notice.txt" \
     && grep -qF '4 of them are shown' "$sm/notice.txt"; then
    ok "[$label] the notice names each class's line count and the count of lines shown"
  else
    bad "[$label] the notice does NOT name the elided/shown counts"
    sed -n '1,20p' "$sm/notice.txt" >&2
  fi
  # The measurement goes to stderr; stdout stays empty, so the elision can be called
  # from inside the body block without polluting the body.
  if [ ! -s "$sm/stdout.txt" ] && grep -qF 'refresh-elide:' "$sm/stderr.txt"; then
    ok "[$label] the measurement goes to stderr and stdout stays empty"
  else
    bad "[$label] the elision wrote to stdout (or its measurement did not reach stderr)"
  fi

  # --- E-FAIL: a missing or empty capture fails loud --------------------------------
  rc=0
  bash "$elide" "$sm/does-not-exist.log" "$sm/b.txt" "$sm/n.txt" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 1 ]; then
    ok "[$label] a missing capture fails loud (exit 1) instead of publishing a body without evidence"
  else
    bad "[$label] a missing capture exits $rc, want 1"
  fi
  : > "$sm/empty.log"
  rc=0
  bash "$elide" "$sm/empty.log" "$sm/b.txt" "$sm/n.txt" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 1 ]; then
    ok "[$label] an empty capture fails loud (exit 1)"
  else
    bad "[$label] an empty capture exits $rc, want 1"
  fi
  rc=0
  bash "$elide" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 2 ]; then
    ok "[$label] a usage error exits 2"
  else
    bad "[$label] a usage error exits $rc, want 2"
  fi

  # --- E-BODY: the artifact boundary (R7) --------------------------------------------
  # The body is the artifact, so the body is what is graded: the shipped body
  # assembly runs against a capture at the scale that broke the refresh, and the body
  # it PUBLISHES is asserted.
  local fl run logsdir rundir
  fl="$(mktemp -d "$WORK/full.XXXXXX")"
  run="$(mktemp -d "$WORK/run.XXXXXX")"
  logsdir="$(mktemp -d "$WORK/logs.XXXXXX")"
  make_body_logs "$logsdir"
  # The capture the elision reads is the FULL-SCALE one, and it lives beside the other
  # captures so the shipped call line can be pointed at it.
  make_full_log "$fl"
  cp "$fl/generate.log" "$logsdir/generate.log"

  # The run directory holds what the body block reads by a RELATIVE path: the drift
  # gate's step out of deploy.yml, and the elision script under test. It is NOT the
  # repo, and it is not the fixture: scaffolding must never land in either.
  mkdir -p "$run/.github/workflows" "$run/scripts"
  cp "$REPO/.github/workflows/deploy.yml" "$run/.github/workflows/deploy.yml"
  cp "$elide" "$run/scripts/refresh-elide.sh"

  # The elision runs the way the WORKFLOW runs it: the shipped call line, with the
  # capture and the two outputs pointed at the fixture.
  if [ -n "$call" ]; then
    local call_sub
    call_sub="$(printf '%s' "$call" \
      | sed -e "s#/tmp/generate\.log#$logsdir/generate.log#g" \
            -e "s#/tmp/elide-block\.txt#$logsdir/elide-block.txt#g" \
            -e "s#/tmp/elide-notice\.txt#$logsdir/elide-notice.txt#g")"
    ( cd "$run" && bash -c "$call_sub" ) >/dev/null 2>&1 || true
  fi

  local block body rc2
  block="$(mktemp "$WORK/body.XXXXXX.sh")"
  extract_body_block "$wf" > "$block"
  if [ ! -s "$block" ]; then
    bad "[$label] the workflow has no body-assembly block (no '} > /tmp/pr-body.md')"
    return $((FAILS - before))
  fi
  sed -e "s#/tmp/refresh\.log#$logsdir/refresh.log#g" \
      -e "s#/tmp/consumer-currency\.log#$logsdir/consumer-currency.log#g" \
      -e "s#/tmp/elide-block\.txt#$logsdir/elide-block.txt#g" \
      -e "s#/tmp/elide-notice\.txt#$logsdir/elide-notice.txt#g" \
      -e "s#} > /tmp/pr-body\.md#} > $logsdir/pr-body.md#" \
      "$block" > "$block.run"
  rc2=0
  (
    cd "$run" || exit 2
    BUMPED=2 STATUS="M  build/skills/build/SKILL.md" SKILLS=1 FILES=1 \
      ADDED=0 REMOVED=0 MODIFIED=1 \
      bash "$block.run" >/dev/null 2>&1
  ) || rc2=$?
  body="$logsdir/pr-body.md"
  if [ ! -s "$body" ]; then
    bad "[$label] the shipped body block did not produce a body (rc=$rc2)"
    return $((FAILS - before))
  fi
  ok "[$label] the shipped body block produces a body"

  # E-SHAPES at the artifact boundary: the shapes must not be IN the published body.
  # The check names the FIXTURE's lines, not the shapes: the elision NOTICE quotes both
  # shapes in prose, and that quotation is evidence, not a leaked progress line.
  if grep -qF 'charly: resolving github.com/opencharly/repo-' "$body" \
     || grep -qF 'Downloading github.com/opencharly/repo-' "$body"; then
    bad "[$label] a per-ref progress shape reached the PUBLISHED body"
  else
    ok "[$label] neither per-ref progress shape reached the PUBLISHED body"
  fi
  # E-ARTIFACTS at the artifact boundary.
  if grep -qF 'family-3/skills/skill-1/SKILL.md' "$body"; then
    bad "[$label] the generator's artifact-path list reached the PUBLISHED body"
  else
    ok "[$label] the generator's artifact-path list did not reach the PUBLISHED body"
  fi
  # E-KEEP at the artifact boundary: the warning and the report line are IN the body.
  if grep -qF 'charly: git latest-tag fetch for https://github.com/opencharly/repo-7 failed' "$body"; then
    ok "[$label] the resolver's warning is in the PUBLISHED body, verbatim"
  else
    bad "[$label] the resolver's warning is NOT in the PUBLISHED body"
  fi
  if grep -qF 'marketplace generate: wrote 496 artifact(s) across 43 family(ies)' "$body"; then
    ok "[$label] the generator's report line is in the PUBLISHED body, verbatim"
  else
    bad "[$label] the generator's report line is NOT in the PUBLISHED body"
  fi
  if grep -qF 'Elision notice' "$body"; then
    ok "[$label] the PUBLISHED body carries the elision notice"
  else
    bad "[$label] the PUBLISHED body does NOT carry the elision notice"
  fi

  # E-CAP: the body fits, and the capture does not — the suite is at the scale that
  # broke the refresh, so the assertion is about the real bound.
  local log_bytes body_bytes
  log_bytes="$(wc -c < "$logsdir/generate.log")"
  body_bytes="$(wc -c < "$body")"
  if [ "$log_bytes" -gt 65536 ]; then
    ok "[$label] the fixture capture is over the cap on its own ($log_bytes bytes) — the suite is at the scale that broke it"
  else
    bad "[$label] the fixture capture is only $log_bytes bytes — the suite is not at the scale that broke the refresh"
  fi
  if [ "$body_bytes" -lt 65536 ]; then
    ok "[$label] the PUBLISHED body is under GitHub's cap ($body_bytes bytes of 65536)"
  else
    bad "[$label] the PUBLISHED body is $body_bytes bytes — over GitHub's 65536-byte cap"
  fi

  return $((FAILS - before))
}

# --------------------------------------------------------------------- the red arms
# Each mutation narrows the elision back toward the defect it was written to close.
mutate_second_shape() {
  # The class-1 pattern keeps only the `Downloading …` literal — #413's shape.
  sed -e 's#|"charly: resolving "\*)#)#' "$1" > "$2"
}

mutate_drop_artifact_class() {
  # The class-2 condition is disabled, so the artifact-path list is pasted whole.
  awk '{ if (index($0, "=~ ^\\ \\ (") > 0) { print "  if false; then"; next } print }' "$1" > "$2"
}

mutate_inline_elision() {
  # The workflow goes back to the pre-fix inline elision: one literal, inlined, and the
  # elision script's outputs are no longer pasted.
  awk '
    { if ($0 ~ /^[[:space:]]*bash scripts\/refresh-elide\.sh /) {
        print "          LOG_ELIDED=$(grep -c \"^Downloading \" /tmp/generate.log || true)";
        print "          grep -v \"^Downloading \" /tmp/generate.log || true";
        next }
      if ($0 ~ /^[[:space:]]*cat \/tmp\/elide-(block|notice)\.txt$/) next
      print }
  ' "$1" > "$2"
}

# A mutation that changes NOTHING — the control for the arms' own failure path.
mutate_noop() {
  cp "$1" "$2"
}

# The size gate moves back BEHIND the push: the verdict is lifted out of the workflow and
# re-inserted after `git push -u origin HEAD`, which is the order this change removed.
mutate_verdict_after_push() {
  awk '
    BEGIN { inblk = 0; n = 0 }
    /^[[:space:]]*if \[ "\$PR_BODY_BYTES" -gt 65536 \]; then/ { inblk = 1; blk[++n] = $0; next }
    inblk {
      blk[++n] = $0
      if ($0 ~ /^[[:space:]]*fi[[:space:]]*$/) { inblk = 0 }
      next
    }
    { print }
    /^[[:space:]]*git push -u origin HEAD/ { for (i = 1; i <= n; i++) print blk[i]; n = 0 }
  ' "$1" > "$2"
}

# run_self_test — 0 when every arm turned the suite red.
# The arms' findings are EXPECTED here, so they do not touch the outer counter; an arm
# that did NOT turn the suite red is the finding, and it is counted here and returned,
# so the caller can fail on it.
run_self_test() {
  local saved="$SELF_TEST_FAILS"
  SELF_TEST_FAILS=0

  local m1="mutate_second_shape" m2="mutate_drop_artifact_class" m3="mutate_inline_elision" m4="mutate_verdict_after_push"
  if [ "$RET_FORCE_NOOP_ARM" -eq 1 ]; then
    m1="mutate_noop"; m2="mutate_noop"; m3="mutate_noop"; m4="mutate_noop"
  fi

  "$m1" "$ELIDE" "$WORK/arm-second-shape.sh"
  if check_suite "$WF" "$WORK/arm-second-shape.sh" "arm:second-shape" >/dev/null 2>&1; then
    printf '  FAIL  red arm %s did NOT turn the suite red\n' "'the second progress shape admitted'" >&2
    SELF_TEST_FAILS=$((SELF_TEST_FAILS + 1))
  else
    ok "red arm 'the second progress shape admitted' turns the suite red"
  fi

  "$m2" "$ELIDE" "$WORK/arm-drop-artifact.sh"
  if check_suite "$WF" "$WORK/arm-drop-artifact.sh" "arm:drop-artifact-class" >/dev/null 2>&1; then
    printf '  FAIL  red arm %s did NOT turn the suite red\n' "'the artifact class dropped'" >&2
    SELF_TEST_FAILS=$((SELF_TEST_FAILS + 1))
  else
    ok "red arm 'the artifact class dropped' turns the suite red"
  fi

  "$m3" "$WF" "$WORK/arm-inline-elision.yml"
  if check_suite "$WORK/arm-inline-elision.yml" "$ELIDE" "arm:inline-elision" >/dev/null 2>&1; then
    printf '  FAIL  red arm %s did NOT turn the suite red\n' "'the workflow's call replaced by the inline elision'" >&2
    SELF_TEST_FAILS=$((SELF_TEST_FAILS + 1))
  else
    ok "red arm 'the workflow's call replaced by the inline elision' turns the suite red"
  fi

  "$m4" "$WF" "$WORK/arm-verdict-after-push.yml"
  if check_suite "$WORK/arm-verdict-after-push.yml" "$ELIDE" "arm:verdict-after-push" >/dev/null 2>&1; then
    printf '  FAIL  red arm %s did NOT turn the suite red\n' "'the size gate moved back behind the push'" >&2
    SELF_TEST_FAILS=$((SELF_TEST_FAILS + 1))
  else
    ok "red arm 'the size gate moved back behind the push' turns the suite red"
  fi

  local rc=$SELF_TEST_FAILS
  SELF_TEST_FAILS="$saved"
  return "$rc"
}

printf 'refresh_elide_test.sh — workflow: %s\n' "$WF"
printf '                        elision: %s\n' "$ELIDE"
check_suite "$WF" "$ELIDE" "shipped" || true
SHIP_FAILS=$FAILS
FAILS=0

if [ "$SELFTEST" -eq 1 ]; then
  printf '\nred arms — each mutation must turn the suite RED\n'
  if run_self_test; then
    ok "every red arm turns the suite red"
  else
    printf '  FAIL  a red arm did NOT turn the suite red\n' >&2
    SELF_TEST_FAILS=$((SELF_TEST_FAILS + 1))
  fi
  FAILS=0

  # The arms' own failure path, proved AT THE PROCESS BOUNDARY: this script is re-run
  # as a SUBPROCESS with its arms made undetectable (a mutation that cannot change the
  # shipped files), and that subprocess must EXIT NON-ZERO. Checking a function's
  # return value would not do — only the exit code is what a gate reads. A suite that
  # cannot fail is not coverage (R7).
  if [ "$RET_FORCE_NOOP_ARM" -eq 0 ]; then
    printf '\nthe arms themselves — an UNDETECTED arm must make the PROCESS exit non-zero\n'
    meta_log="$WORK/meta-arm.log"
    meta_rc=0
    # The child ALWAYS runs the SHIPPED files, whatever this process was pointed at:
    # the property under test is a property of the SUITE, not of the files. That also
    # makes the attribution exact — the child's shipped check is green, so the only
    # thing that can make it exit non-zero is the undetected arm.
    bash "$SELF" --self-test --force-noop-arm > "$meta_log" 2>&1 || meta_rc=$?
    if [ "$meta_rc" -ne 0 ] \
       && grep -q 'did NOT turn the suite red' "$meta_log" \
       && ! grep -q 'finding(s) against the shipped files' "$meta_log"; then
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
  printf '\nFAILED: %d finding(s) against the shipped files\n' "$SHIP_FAILS" >&2
  exit 1
fi
if [ "$SELF_TEST_FAILS" -ne 0 ]; then
  printf '\nFAILED: %d red-arm finding(s) — an arm that did not turn the suite red, or an undetected one\n' "$SELF_TEST_FAILS" >&2
  exit 1
fi
printf '\nOK\n'
exit 0
