#!/usr/bin/env bash
# consumer_currency_test.sh — drive scripts/consumer-currency.sh against FIXTURES, so the
# states the report can report are PROVEN rather than argued (opencharly/marketplace#543).
#
# WHY. A report is only worth what it says. A report that reads nothing is a dead control; a
# report that calls a squash-advance a divergence sends the reader after the wrong remedy; a
# report that cannot say "undecidable" guesses. So every state gets a fixture, and the
# refresh workflow's own wiring is driven too — the step that runs on EVERY refresh and
# writes the job summary.
#
# The GitHub boundary is STUBBED (a fixture `gh` on PATH), and the git boundary is REAL (a
# fixture repository with a real main line, a real side branch and a real shallow clone).
#
# usage: bash scripts/consumer_currency_test.sh [<workflow-file>]
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILS=0
ok()  { printf '  PASS  %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1" >&2; FAILS=$((FAILS + 1)); }

# ---- the fixture corpus repo: a real main line, a real side branch ------------------
FIX="$WORK/fixture"
mkdir -p "$FIX/scripts"
cp "$HERE/consumer-currency.sh" "$FIX/scripts/consumer-currency.sh"
(
  cd "$FIX" || exit 1
  git init -q -b main . >/dev/null 2>&1
  git config user.email t@example.invalid
  git config user.name fixture
  cat > README.md <<'MD'
# Fixture corpus

## Consumers

| Consumer | Pin path | What it does with the corpus |
|---|---|---|
| `acme/cur` | `marketplace` | pinned at the tip |
| `acme/behind` | `marketplace` | pinned two commits back |
| `acme/side` | `marketplace` | pinned on a side branch |
| `acme/foreign` | `marketplace` | pinned at a commit this repo never had |
| `acme/gone` | `marketplace` | a consumer that cannot be read |
MD
  git add README.md scripts/consumer-currency.sh >/dev/null
  git commit -qm one >/dev/null
  echo two > two.txt; git add .; git commit -qm two >/dev/null
  echo three > three.txt; git add .; git commit -qm three >/dev/null
  git checkout -q -b side >/dev/null 2>&1
  echo side > side.txt; git add .; git commit -qm side >/dev/null
  git checkout -q main >/dev/null 2>&1
  # the merged main, as the remote sees it
  git update-ref refs/remotes/origin/main HEAD
) || { echo "could not build the fixture repo" >&2; exit 2; }

TIP="$(git -C "$FIX" rev-parse HEAD)"
BEHIND="$(git -C "$FIX" rev-parse HEAD~2)"
SIDE="$(git -C "$FIX" rev-parse side)"
FOREIGN="0123456789012345678901234567890123456789"

# ---- the stubbed `gh`: the GitHub boundary ------------------------------------------
BIN="$WORK/bin"
mkdir -p "$BIN"
PINS="$WORK/pins.txt"
{
  echo "repos/acme/cur/contents/marketplace $TIP"
  echo "repos/acme/behind/contents/marketplace $BEHIND"
  echo "repos/acme/side/contents/marketplace $SIDE"
  echo "repos/acme/foreign/contents/marketplace $FOREIGN"
} > "$PINS"
cat > "$BIN/gh" <<SH
#!/usr/bin/env bash
# The stubbed GitHub boundary: it answers the contents API for the recorded pins, and
# fails for every consumer it does not know — which is what a deleted or renamed consumer
# looks like from here.
if [ "\$1" = "api" ]; then
  target="\$2"
  sha="\$(awk -v t="\$target" '\$1==t{print \$2}' "$PINS" 2>/dev/null)"
  if [ -n "\$sha" ]; then
    echo "\$sha"
    exit 0
  fi
  echo "gh: not found (fixture stub)" >&2
  exit 1
fi
exit 0
SH
chmod +x "$BIN/gh"

# ---- run the report against the fixture ---------------------------------------------
OUT="$WORK/report.txt"
PATH="$BIN:$PATH" bash "$FIX/scripts/consumer-currency.sh" "$FIX" > "$OUT" 2> "$WORK/report.err"
RC=$?

if [ "$RC" -eq 0 ]; then ok "the report exits 0"; else bad "the report exits $RC (it must never fail)"; fi

line() { grep -E "^  $1 " "$OUT" || true; }

CUR_LINE="$(line acme/cur)"
BEHIND_LINE="$(line acme/behind)"
SIDE_LINE="$(line acme/side)"
FOREIGN_LINE="$(line acme/foreign)"
GONE_LINE="$(line acme/gone)"

if grep -q "cur — at the corpus's merged main" <<< "$CUR_LINE"; then
  ok "a pin at the tip is reported cur"
else bad "a pin at the tip is not reported cur: $CUR_LINE"; fi

# The NEGATIVE control: a consumer that is current must NOT be reported as behind. The
# header line carries the count of behind consumers, so the assertion is per line.
if grep -q "behind" <<< "$CUR_LINE"; then
  bad "a current consumer is reported as behind: $CUR_LINE"
else ok "a current consumer is NOT reported as behind"; fi

if grep -q "behind — 2 commit(s) behind" <<< "$BEHIND_LINE"; then
  ok "a pin two commits back is reported behind, with the count"
else bad "a pin two commits back is not reported behind: $BEHIND_LINE"; fi

if grep -q "not-on-the-served-line" <<< "$SIDE_LINE"; then
  ok "a pin on a side branch is reported not-on-the-served-line"
else bad "a pin on a side branch is misreported: $SIDE_LINE"; fi
if grep -q "it is not a divergence" <<< "$SIDE_LINE"; then
  ok "a squash-advance is NOT called a divergence (the pin contract's remedy)"
else bad "a squash-advance is called a divergence: $SIDE_LINE"; fi

if grep -q "not-on-the-served-line" <<< "$FOREIGN_LINE"; then
  ok "a pin at a commit this repo never had is reported not-on-the-served-line"
else bad "a foreign pin is misreported: $FOREIGN_LINE"; fi

if grep -q "unreadable" <<< "$GONE_LINE"; then
  ok "a consumer whose pin cannot be read is reported unreadable"
else bad "an unreadable consumer is misreported: $GONE_LINE"; fi

if grep -q "5 consumer(s) read, 1 behind, 2 not-on-the-served-line, 0 undecidable, 1 unreadable" "$OUT"; then
  ok "the summary counts every state"
else bad "the summary counts are wrong: $(head -1 "$OUT")"; fi

# ---- a SHALLOW history cannot decide ancestry, and must say so -----------------------
if git clone -q --depth 1 "file://$FIX" "$WORK/shallow" >/dev/null 2>&1; then
  SOUT="$WORK/shallow-report.txt"
  PATH="$BIN:$PATH" bash "$WORK/shallow/scripts/consumer-currency.sh" "$WORK/shallow" > "$SOUT" 2>&1
  SRC=$?
  if [ "$SRC" -eq 0 ]; then ok "the report exits 0 on a shallow history"; else bad "the report exits $SRC on a shallow history"; fi
  if grep -q "undecidable — this repo's history is shallow" "$SOUT"; then
    ok "a shallow history is reported undecidable, never as a squash-advance"
  else bad "a shallow history is not reported undecidable: $(head -2 "$SOUT")"; fi
else
  bad "could not build the shallow fixture clone"
fi

# ---- a record that cannot be parsed is reported LOUDLY, and still never fails ---------
cp -r "$FIX" "$WORK/norecord" >/dev/null 2>&1
printf '# Fixture corpus\n\nNo consumer table here.\n' > "$WORK/norecord/README.md"
NOUT="$WORK/norecord-report.txt"
PATH="$BIN:$PATH" bash "$WORK/norecord/scripts/consumer-currency.sh" "$WORK/norecord" > "$NOUT" 2> "$WORK/norecord.err"
NRC=$?
if [ "$NRC" -eq 0 ]; then ok "the report exits 0 on a broken record"; else bad "the report exits $NRC on a broken record"; fi
if grep -q "no consumer row" "$WORK/norecord.err"; then
  ok "a broken consumer record is reported loudly (the report is EMPTY)"
else bad "a broken consumer record is silent: $(cat "$WORK/norecord.err")"; fi
if grep -q "0 consumer(s) read" "$NOUT"; then
  ok "a broken consumer record reports zero consumers"
else bad "a broken consumer record does not report zero: $(head -1 "$NOUT")"; fi

# ---- the refresh workflow's wiring: the step that always runs, and the job summary ----
WF="${1:-$ROOT/.github/workflows/refresh.yml}"
[ -r "$WF" ] || { echo "no refresh workflow at $WF" >&2; exit 2; }

python3 - "$WF" "$WORK/step.sh" "$WORK/step-meta.txt" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read().split("\n")
# The step that reports, and the step that opens the PR — their ORDER matters: the PR body
# pastes the report, so the report must have run first.
name = next((i for i, l in enumerate(src) if "Report the recorded consumers' pin currency" in l), None)
pr = next((i for i, l in enumerate(src) if "Open the refresh PR" in l), None)
if name is None or pr is None:
    sys.exit("the refresh workflow no longer carries the consumer-currency step")
step = []
for l in src[name + 1:]:
    if l.strip() and not l.startswith("        "):
        break
    step.append(l)
# the run: block of that step
run = []
inside = False
for l in step:
    if l.strip().startswith("run:"):
        inside = True
        continue
    if inside:
        if l.strip() and not l.startswith("          "):
            break
        run.append(l[10:] if len(l) > 10 else "")
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(run) + "\n")
open(sys.argv[3], "w", encoding="utf-8").write(
    f"name={name}\npr={pr}\nconditional={'yes' if any('if:' in l for l in step) else 'no'}\n"
    f"summary={'yes' if any('GITHUB_STEP_SUMMARY' in l for l in step) else 'no'}\n"
)
PY
if [ $? -ne 0 ]; then bad "could not extract the consumer-currency step from refresh.yml"; else
  . "$WORK/step-meta.txt"
  if [ "$conditional" = "no" ]; then
    ok "the consumer-currency step is UNCONDITIONAL (it runs on every refresh)"
  else bad "the consumer-currency step is conditional — a corpus landing that moved no refs still moved the corpus"; fi
  if [ "$name" -lt "$pr" ]; then
    ok "the consumer-currency step runs BEFORE the PR step (the PR body pastes the report)"
  else bad "the consumer-currency step runs after the PR step"; fi
  if [ "$summary" = "yes" ]; then
    ok "the consumer-currency step writes the job summary"
  else bad "the consumer-currency step writes no job summary"; fi

  # The PR body must paste the report — the report's second home.
  if grep -q "cat /tmp/consumer-currency.log" "$WF"; then
    ok "the refresh PR body pastes the consumer-currency report"
  else bad "the refresh PR body does not paste the consumer-currency report"; fi

  # Drive the extracted step: a stubbed gh, a fixture root, and a job summary to read.
  SUM="$WORK/summary.md"
  ( cd "$FIX" && PATH="$BIN:$PATH" GITHUB_STEP_SUMMARY="$SUM" bash "$WORK/step.sh" ) > "$WORK/step.out" 2>&1
  SRC=$?
  if [ "$SRC" -eq 0 ]; then ok "the workflow step exits 0"; else bad "the workflow step exits $SRC: $(cat "$WORK/step.out")"; fi
  if [ -s "$SUM" ] && grep -q "## Consumer currency" "$SUM"; then
    ok "the workflow step writes the report into the job summary"
  else bad "the job summary carries no report: $(cat "$SUM" 2>/dev/null)"; fi
  if grep -q "consumer-currency:" "$SUM"; then
    ok "the job summary carries the report's own output"
  else bad "the job summary carries no report output"; fi
fi

echo
if [ "$FAILS" -eq 0 ]; then echo "PASS — consumer-currency assertions passed"; exit 0; fi
echo "FAIL — $FAILS assertion(s) failed"; exit 1
