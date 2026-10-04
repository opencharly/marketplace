#!/usr/bin/env bash
# coord_test.sh — self-contained coverage for coord.sh.
#
# LAYER 1 (always): a deterministic STUB `gh` + `jq` on PATH records every call, so
#   the verb/target/footer grammar is asserted on the REAL script logic with no
#   network. Every asserted branch (help, bad verb, bad tier, missing identity, the
#   canonical footer order, verb normalisation, both target forms, --assign) runs.
#
# LAYER 2 (opt-in, LIVE OR SKIP): with COORD_LIVE_ITEM=<owner/repo#num> set (and a
#   real authenticated `gh`), it posts a real STATUS comment to that DISPOSABLE
#   coordination-test item and deletes it again — the REAL GitHub boundary, never a
#   fake. Unset → SKIP visibly (never a silent pass; R7 live-or-skip).
#
# Run: ./scripts/coord_test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COORD="$HERE/coord.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILS=0
ok() { printf '  PASS  %s\n' "$1"; }
bad() {
  printf '  FAIL  %s\n' "$1" >&2
  FAILS=$((FAILS + 1))
}
eq() { [ "$1" = "$2" ] && ok "$3" || bad "$3 (want '$2' got '$1')"; }

# --- LAYER 1: deterministic stub gh + jq -----------------------------------
mkdir -p "$WORK/bin"
CALLS="$WORK/calls.log"
: > "$CALLS"

cat > "$WORK/bin/gh" <<'SH'
#!/usr/bin/env bash
printf 'gh' >> "$CALLS"
for a in "$@"; do printf ' %q' "$a" >> "$CALLS"; done
printf '\n' >> "$CALLS"
# --jq .html_url  → a deterministic URL;  --jq .login → a deterministic login.
for a in "$@"; do
  case "$a" in
    .html_url) printf 'https://github.com/stub/comment/1\n'; exit 0 ;;
    .login) printf 'stub-user\n'; exit 0 ;;
  esac
done
exit 0
SH
chmod +x "$WORK/bin/gh"

# A minimal `jq` real enough for `-Rs '{body: .}'` (read raw stdin → JSON object).
cat > "$WORK/bin/jq" <<'SH'
#!/usr/bin/env bash
# Only the one filter this script uses is supported.
filter=${1:-}
shift 2>/dev/null || true
if [ "$filter" = "-Rs" ]; then
  # `-Rs` reads the RAW stdin into a string; then the program is the next arg.
  prog=${1:-}
  if [ "$prog" = "{body: .}" ]; then
    python3 -c 'import json,sys; print(json.dumps({"body": sys.stdin.read()}))'
    exit 0
  fi
fi
# `--jq .login` / `.html_url` are handled by the stub gh, not here.
exit 0
SH
chmod +x "$WORK/bin/jq"

export PATH="$WORK/bin:$PATH" CALLS

common=(--agent slug-x --session ses_test --harness OpenCode --model "DeepSeek V4.1 Flash" --confidence "documentation reviewed")

# 1. --help exits 0 and names every verb (the EXACT canonical spaced labels).
"$COORD" --help > "$WORK/help.txt" 2>&1
eq "$?" 0 "coord.sh --help exits 0"
for v in CLAIM OWNING "HANDING OVER" "TAKING OVER" BLOCKS UNBLOCKS STATUS RESOLVED; do
  grep -qF "$v" "$WORK/help.txt" && ok "help lists the canonical label $v" || bad "help lists the canonical label $v"
done

# 2. unknown option → exit 2.
"$COORD" STATUS acme/widget#1 "${common[@]}" --bogus --dry-run >/dev/null 2>&1
eq "$?" 2 "unknown option exits 2"

# 2b. `--` ends option parsing (flags first, then `--`, then the positionals).
out=$("$COORD" --agent slug-x --session ses_test --harness OpenCode --model M \
  --confidence "documentation reviewed" --dry-run -- STATUS acme/widget#1 2>/dev/null)
eq "$(printf '%s\n' "$out" | head -1)" "STATUS" "-- ends option parsing; the verb parses positionally after it"

# 2c. missing gh on PATH → exit 3.
BASH_BIN=$(command -v bash)
mkdir -p "$WORK/min"
for t in sed tr cat mktemp dirname; do
  src=$(command -v "$t" 2>/dev/null) && ln -sf "$src" "$WORK/min/$t"
done
PATH="$WORK/min" "$BASH_BIN" "$COORD" STATUS acme/widget#1 "${common[@]}" >/dev/null 2>&1
eq "$?" 3 "a missing gh on PATH exits 3 (the missing-tool class)"

# 2. invalid verb → exit 2.
"$COORD" NONSENSE acme/widget#1 "${common[@]}" --dry-run >/dev/null 2>&1
eq "$?" 2 "invalid verb exits 2"

# 3. invalid confidence tier → exit 2.
"$COORD" STATUS acme/widget#1 --agent a --session s --harness h --model m --confidence bogus --dry-run >/dev/null 2>&1
eq "$?" 2 "invalid confidence exits 2"

# 4. missing identity → exit 2.
"$COORD" STATUS acme/widget#1 --session s --harness h --model m --confidence "documentation reviewed" --dry-run >/dev/null 2>&1
eq "$?" 2 "missing --agent exits 2"

# 5. missing target → exit 2.
"$COORD" STATUS "${common[@]}" --dry-run >/dev/null 2>&1
eq "$?" 2 "missing target exits 2"

# 6. canonical footer ORDER: verb first line, Agent before Assisted-by, last line.
out=$("$COORD" BLOCKS "acme/widget#7" --body "waiting on the producer pin" "${common[@]}" --dry-run 2>/dev/null)
eq "$(printf '%s\n' "$out" | head -1)" "BLOCKS" "first line is the verb label"
eq "$(printf '%s\n' "$out" | tail -1)" "*Assisted-by: OpenCode DeepSeek V4.1 Flash (documentation reviewed)*" "last line is the Assisted-by trailer"
agent_line=$(printf '%s\n' "$out" | grep -n '^\*Agent:' | cut -d: -f1)
assist_line=$(printf '%s\n' "$out" | grep -n '^\*Assisted-by:' | cut -d: -f1)
[ -n "$agent_line" ] && [ -n "$assist_line" ] && [ "$agent_line" -lt "$assist_line" ] \
  && ok "Agent: line precedes Assisted-by: line (canonical order)" \
  || bad "Agent: line precedes Assisted-by: line"
printf '%s\n' "$out" | grep -q 'session `ses_test`' && ok "Agent: line carries the session" || bad "Agent: line carries the session"
printf '%s\n' "$out" | grep -q 'waiting on the producer pin' && ok "the body is included" || bad "the body is included"

# 7. verb normalisation: handing-over / handing_over / handing over → HANDING OVER.
for form in "handing-over" "handing_over" "Handing Over"; do
  got=$("$COORD" "$form" acme/widget#1 "${common[@]}" --dry-run 2>/dev/null | head -1)
  eq "$got" "HANDING OVER" "normalises '$form' → HANDING OVER"
done

# 7b. a two-word verb left unquoted and split across two arguments is caught by the
#     diagnostic in `positional()` — and stderr must name the two-word verb plus both
#     spellings that need no quoting. That is the whole point of the branch: the older
#     message was `unexpected argument: <repo ref>` alone, which points at the target and
#     sends the caller hunting for a quoting bug in the wrong half of the command line.
#     The lowercase case passes only if the diagnostic runs the SAME normalisation as the
#     closed-set validation (R3): `handing` + `OVER` reaches the label 'HANDING OVER' only
#     through `canon_verb`, never through a raw string compare.
assert_two_word() { # assert_two_word <first-word> <second-word> <expected label>
  local err rc under="${3%% *}_${3#* }"
  err=$("$COORD" "$1" "$2" acme/widget#1 "${common[@]}" --dry-run 2>&1 >/dev/null)
  rc=$?
  eq "$rc" 2 "an unquoted two-word verb ('$1 $2') exits 2"
  printf '%s' "$err" | grep -qF "$3" && ok "  … and its message names the two-word verb '$3'" \
    || bad "  … and its message names the two-word verb '$3' (got: $err)"
  printf '%s' "$err" | grep -qF "$under" && ok "  … and its message names the '$under' form" \
    || bad "  … and its message names the '$under' form (got: $err)"
  printf '%s' "$err" | grep -qF "\"$3\"" && ok "  … and its message shows the quoted one-argument form" \
    || bad "  … and its message shows the quoted one-argument form '\"$3\"' (got: $err)"
}
assert_two_word TAKING OVER "TAKING OVER"
assert_two_word HANDING OVER "HANDING OVER"
assert_two_word handing OVER "HANDING OVER"

# 8. verb-only comment (no body) is well-formed.
got=$("$COORD" STATUS acme/widget#1 "${common[@]}" --dry-run 2>/dev/null | head -1)
eq "$got" "STATUS" "verb-only comment's first line is the verb"

# 9. both target forms parse and hit the right API path.
: > "$CALLS"
"$COORD" CLAIM "acme/widget#12" "${common[@]}" >/dev/null 2>&1
grep -q 'repos/acme/widget/issues/12/comments' "$CALLS" && ok "owner/repo#num posts to /issues/12/comments" || bad "owner/repo#num posts to /issues/12/comments"
grep -q 'method POST' "$CALLS" && ok "the post uses --method POST" || bad "the post uses --method POST"

: > "$CALLS"
"$COORD" CLAIM "https://github.com/acme/widget/pull/34" "${common[@]}" >/dev/null 2>&1
grep -q 'repos/acme/widget/issues/34/comments' "$CALLS" && ok "a pull URL posts to the issue endpoint 34" || bad "a pull URL posts to the issue endpoint 34"

# 10. --assign claims by assigning the posting account.
: > "$CALLS"
"$COORD" CLAIM "acme/widget#12" "${common[@]}" --assign >/dev/null 2>&1
grep -q 'repos/acme/widget/issues/12/assignees' "$CALLS" && ok "--assign assigns the posting account" || bad "--assign assigns the posting account"
grep -q 'stub-user' "$CALLS" && ok "--assign resolves the account via gh api user" || bad "--assign resolves the account via gh api user"

# 11. --body-file reads the body.
printf 'from a file\n' > "$WORK/b.md"
out=$("$COORD" STATUS acme/widget#1 --body-file "$WORK/b.md" "${common[@]}" --dry-run 2>/dev/null)
printf '%s\n' "$out" | grep -q 'from a file' && ok "--body-file reads the body" || bad "--body-file reads the body"

# 12. --dry-run makes NO gh call.
: > "$CALLS"
"$COORD" STATUS acme/widget#1 "${common[@]}" --dry-run >/dev/null 2>&1
[ ! -s "$CALLS" ] && ok "--dry-run makes no gh call" || bad "--dry-run makes no gh call"

# --- LAYER 2: the REAL GitHub boundary (opt-in, live-or-skip) --------------
echo
if [ -z "${COORD_LIVE_ITEM:-}" ]; then
  echo "  SKIP  live GitHub layer (set COORD_LIVE_ITEM=<owner/repo#num> to post+delete a real comment)"
else
  if ! command -v gh >/dev/null 2>&1; then
    bad "COORD_LIVE_ITEM set but no real gh on PATH"
  else
    # Post a real comment, then delete it. Uses the REAL gh (unset the stub PATH).
    real_path=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v "$WORK/bin" | paste -sd:)
    posted=$(PATH="$real_path" "$COORD" STATUS "$COORD_LIVE_ITEM" --body "coord_test live probe" \
      --agent coord-test --session "ses_live" --harness OpenCode --model "DeepSeek V4.1 Flash" \
      --confidence "documentation reviewed" 2>/dev/null)
    if [[ $posted =~ (https://github.com/.*/issues/[0-9]+#issuecomment-[0-9]+) ]]; then
      ok "live: posted a real comment ($posted)"
      cid=${posted##*#issuecomment-}
      slug=${COORD_LIVE_ITEM#https://github.com/}
      slug=${slug#*github.com/}
      owner_repo=${slug%%#*}
      repo_num=${slug##*#}
      PATH="$real_path" gh api --method DELETE "repos/$owner_repo/issues/comments/$cid" >/dev/null 2>&1 \
        && ok "live: deleted the probe comment" || bad "live: could not delete the probe comment"
    else
      bad "live: posting did not return a comment URL (got '$posted')"
    fi
  fi
fi

echo
if [ "$FAILS" -eq 0 ]; then
  echo "PASS — all coord.sh assertions passed"
  exit 0
else
  echo "FAIL — $FAILS assertion(s) failed"
  exit 1
fi
