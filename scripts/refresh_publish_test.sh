#!/usr/bin/env bash
# refresh_publish_test.sh — drive the PUBLICACTION block of .github/workflows/refresh.yml
# against a stubbed `gh`, so the three states its readback must tell apart are PROVEN rather
# than argued (opencharly/marketplace#451).
#
# WHY. The block replaces a `for attempt in 1 2 3 … sleep $((attempt*10))` loop that repeated a
# WRITE. Repetition cannot make a write safe: a 504/5xx may mean the PR was created and only the
# response was lost, and the repeat then fails with "already exists" and masks the success. The
# new rule is ONE attempt plus an idempotent READBACK, and the three outcomes are:
#   1. the attempt succeeded and a PR exists      → published
#   2. the attempt failed but a PR exists         → the write landed, the response was lost
#   3. the attempt failed and no PR exists        → ::error, the branch is preserved by hand
# This harness asserts all three, asserts exactly ONE `gh pr create` call in each case, and
# asserts the retired loop cannot come back (no `sleep`, no `for attempt in`) — the R5 claim-keyed
# self-check, in the harness itself.
#
# The block is EXTRACTED from the workflow at run time, never copied: a second copy of the logic
# would be the very duplication (R2) this repo removes.
#
# usage: bash scripts/refresh_publish_test.sh [<workflow-file>]
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WF="${1:-$HERE/../.github/workflows/refresh.yml}"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
FAILS=0
ok()  { printf '  PASS  %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1" >&2; FAILS=$((FAILS+1)); }

# ---- extract the publication block: from the `BR=$(git rev-parse` anchor to the end of the
# step's script (the block IS the tail of the step in both the old and the new workflow).
python3 - "$WF" "$WORK/publish.sh" <<'PY'
import sys
src = open(sys.argv[1]).read().split('\n')
start = next(i for i, l in enumerate(src) if l.lstrip().startswith('BR=$(git rev-parse'))
ind = len(src[start]) - len(src[start].lstrip())
body = []
for l in src[start:]:
    body.append(l[ind:] if l.strip() else '')
open(sys.argv[2], 'w').write('\n'.join(body) + '\n')
PY
[ -s "$WORK/publish.sh" ] || { echo "could not extract the publication block from $WF" >&2; exit 2; }
BLOCK="$(cat "$WORK/publish.sh")"

# ---- the retired mechanism must not come back, in the block or anywhere in its step.
if grep -qE '(^|[^a-zA-Z])sleep[^a-zA-Z]' <<<"$BLOCK"; then
  bad "the publication block contains a sleep (R3: no blind retry)"
else ok "no sleep in the publication block"; fi
if grep -q 'for attempt in' <<<"$BLOCK"; then
  bad "the publication block still contains the retired 'for attempt in' retry loop"
else ok "the retired retry loop is absent (R5 claim-keyed check)"; fi

# ---- run one case: <label> <CREATE_RC> <PR_LIST> <EXPECT_RC> <GREP> [<GREP2>]
run_case() {
  local label="$1" create_rc="$2" pr_list="$3" expect_rc="$4"; shift 4
  local case_dir="$WORK/case-$label"; mkdir -p "$case_dir/bin"
  printf 'refresh body' > "$WORK/pr-body.md"
  cat > "$case_dir/bin/gh" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$WORK/calls-$label"
if [ "\$1 \$2" = "pr create" ]; then exit $create_rc; fi
if [ "\$1 \$2" = "pr list" ]; then printf '%s\n' '$pr_list'; exit 0; fi
exit 0
SH
  chmod +x "$case_dir/bin/gh"
  : > "$WORK/calls-$label"
  local out rc
  out="$(cd "$WORK" && PATH="$case_dir/bin:$PATH" GH_TOKEN=x GITHUB_REPOSITORY=opencharly/marketplace \
        bash -c "$BLOCK" 2>&1)"; rc=$?
  if [ "$rc" -ne "$expect_rc" ]; then
    bad "$label: exit $rc, want $expect_rc — output: $out"
  else ok "$label: exit $expect_rc"; fi
  local g
  for g in "$@"; do
    grep -q "$g" <<<"$out" && ok "$label: output says '$g'" || bad "$label: output lacks '$g' (got: $out)"
  done
  local creates; creates="$(grep -c '^pr create' "$WORK/calls-$label" || true)"
  [ "$creates" = "1" ] && ok "$label: exactly ONE pr create call" \
    || bad "$label: $creates pr create calls (want exactly 1 — no repeated write)"
}

# The branch name comes from the real git in $WORK: initialise it once.
( cd "$WORK" && git init -q . && git config user.email t@t && git config user.name t \
  && : > f && git add f && git commit -qm init && git checkout -qb refresh/20261013-000000 ) \
  || { echo "could not prepare the scratch git repo" >&2; exit 2; }

run_case "created"      0 7     0 "published: PR #7"
run_case "response-lost" 1 9    0 "the PR EXISTS (#9)" "the write landed"
run_case "not-created"  1 ""    1 "did not create a PR" "Open it by hand"

# ---- the EMITTED compliance block, validated at its actual boundary (R7). The block is shell
# `echo`s; running them is what the workflow does, so run them here. Two properties, both aimed
# at the round-2 defect this harness now guards: a renumbering that drops a bullet's HEADER
# leaves its body lines printed with no rule id — the artifact this PR exists to fix — and a
# mapping that emits one rule id twice is equally wrong.
python3 - "$WF" "$WORK/emitted.txt" "$WORK/emitted-head.txt" "$WORK/emitted-all.txt" <<'PY'
import re, sys
src = open(sys.argv[1]).read().split('\n')
# The body is assembled by runs of `echo` lines. Pick the run that CARRIES rule bullets — the
# compliance block — not the first fence in the file (there are many fences; the log/diff
# sections each close one).
runs, cur = [], []
for l in src:
    if re.match(r'\s*echo(\s|$)', l): cur.append(l)
    else:
        if cur: runs.append(cur)
        cur = []
if cur: runs.append(cur)
def emit(run):
    out = []
    for l in run:
        m = re.match(r'\s*echo\s*(.*)$', l)
        a = (m.group(1) if m else '').strip()
        if a.startswith('"') and a.endswith('"'): a = a[1:-1]
        out.append(a.replace('\\`', '`').replace('\\"', '"'))
    return out
block = next((r for r in runs if any(t.startswith('- **R') for t in emit(r))), None)
open(sys.argv[2], 'w').write('\n'.join(emit(block)) + '\n' if block else '')
# The WHOLE assembled body — every `echo` run the workflow emits, in order — so a count claim
# can be asserted at the artifact boundary (what the PR body actually says), not only in the
# workflow's source text.
open(sys.argv[4], 'w').write('\n'.join(t for r in runs for t in emit(r)) + '\n')
# Every log/diff fence-close in the assembled body must be followed by a HEADING — a rule bullet
# or a `##` section — never by a continuation-only line: a renumbering that drops a bullet's
# header leaves exactly that orphan, printed with no rule id. Report every offending line.
FENCE = "echo '" + chr(96) * 3 + "'"
bad_fences = []
for i, l in enumerate(src):
    if FENCE in l and i + 1 < len(src):
        m = re.match(r'\s*echo\s*(.*)$', src[i + 1])
        if m:
            nxt = m.group(1).strip().strip('"')
            if nxt.startswith('  '): bad_fences.append(f"{i + 2}: {nxt}")
open(sys.argv[3], 'w').write('\n'.join(bad_fences) + ('\n' if bad_fences else ''))
PY
EMITTED="$WORK/emitted.txt"
HEAD="$WORK/emitted-head.txt"
if [ -s "$HEAD" ]; then
  bad "a fence-close is followed by a headerless body line: $(tr '\n' ';' < "$HEAD")"
else ok "every fence-close is followed by a heading, never an orphaned body line"; fi
dupes="$(grep -oE '^- \*\*R[0-9]+' "$EMITTED" | sort | uniq -d)"
[ -z "$dupes" ] && ok "no rule id is emitted twice" || bad "rule ids emitted twice: $dupes"
orphans=""
while IFS=: read -r n _; do
  prev="$(sed -n "$((n-1))p" "$EMITTED")"
  case "$prev" in '- **R'*|'  '*) ;; *) orphans="$orphans $n" ;; esac
done < <(grep -nE '^  ' "$EMITTED" || true)
[ -z "$orphans" ] && ok "every continuation line follows a rule bullet" \
  || bad "continuation lines with no rule bullet above them: line(s)$orphans"

# ---- the workflow's PROSE must not state the refs list's SIZE as a literal. A hand-written count
# about a list that changes on every refresh is a claim that drifts: refresh PR #534's body gave
# TWO different sizes for the same list — how many pins the run advanced, and how many the
# workflow still had to advance — and the validator read the contradiction there. The CLASS is
# what is forbidden (a count of pins or of refs, of the refs left over, or of the per-ref
# progress lines), not one instance of it, so a later list cannot re-introduce the same drift
# under a different number. The nouns are the sweep's own: the R1 sweep greps for a count of
# `pins?` OR `refs?`, so the guard covers both — a guard narrower than the sweep would let a
# "N refs" phrasing through the very hole the sweep is looking for.
COUNT_PATTERN='\b[0-9]{2,} +(hand-maintained +)?(pins?|refs?)\b|\bthe remaining +[0-9]+\b|\b[0-9]{2,} +of them\b'
COUNT_CLAIMS="$(grep -nE "$COUNT_PATTERN" "$WF" || true)"
if [ -z "$COUNT_CLAIMS" ]; then
  ok "the workflow states the refs list's size without a number"
else
  bad "the workflow states a count of the refs list: $(tr '\n' ';' <<<"$COUNT_CLAIMS")"
fi
EMITTED_CLAIMS="$(grep -nE "$COUNT_PATTERN" "$WORK/emitted-all.txt" || true)"
if [ -z "$EMITTED_CLAIMS" ]; then
  ok "the assembled body states the refs list's size without a number"
else
  bad "the assembled body states a count of the refs list: $(tr '\n' ';' <<<"$EMITTED_CLAIMS")"
fi

echo
if [ "$FAILS" -eq 0 ]; then echo "PASS — refresh publication block assertions passed"; exit 0; fi
echo "FAIL — $FAILS assertion(s) failed"; exit 1
