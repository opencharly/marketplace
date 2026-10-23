#!/usr/bin/env bash
# refresh_refs_test.sh — drive scripts/refresh-refs.sh against a stubbed `gh` and FIXTURE refs
# lists, so the resolver's decisions are PROVEN rather than argued (opencharly/marketplace#553).
#
# WHY. The resolver used to take every `vN.N.N` tag in a repo, sort the components NUMERICALLY
# and take the last one. The Go-module scheme's first component is the fixed major `0`, so `0`
# sorts BELOW the year `2026`: a Go-module pin was moved to the superproject's newest tag —
# not a valid Go module version at all — and moved BACKWARD in time while doing so. The two
# contract repos in the refs list, `spec` and `sdk`, are Go modules, and that is what the
# refresh did to them.
#
# THE RULE THIS HOLDS. A pin's SCHEME is a property of the pin the list already carries: the
# shape of the tag the pin holds decides which tags are eligible. And a pin never moves
# BACKWARD. The fixtures below are the two real corruption cases (a Go-module pin in a repo
# that publishes both schemes, and a repo whose newest in-scheme tag is older than the pin),
# plus the ordinary advances.
#
# THE RED ARMS mutate a COPY of the shipped resolver and require each mutation to turn this
# suite RED. A test that cannot fail proves nothing (R7), and the two mutations are the two
# rules above: the scheme filter and the backward guard.
#
# usage: bash scripts/refresh_refs_test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
FAILS=0
CASE_FAILS=0
ok()  { printf '  PASS  %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1" >&2; FAILS=$((FAILS + 1)); }

# ---------------------------------------------------------------- the fixture repos
# repo -> the tags it publishes, one per line. `spec` and `sdk` publish BOTH schemes, exactly
# as they do in the org: the Go-module tags and the superproject tags side by side.
write_tags() {
  local dir="$1"
  mkdir -p "$dir/tags"
  cat > "$dir/tags/spec" <<'EOF'
v0.2026295.700
v0.2026296.734
v2026.240.1944
v2026.296.1436
EOF
  cat > "$dir/tags/sdk" <<'EOF'
v0.2026296.803
v0.2026297.101
v2026.232.1949
EOF
  cat > "$dir/tags/layer-charly-internals" <<'EOF'
v0.2026296.734
v2026.296.0218
v2026.297.0500
EOF
  cat > "$dir/tags/eval-omarchy" <<'EOF'
v2026.295.0943
EOF
  cat > "$dir/tags/plugin-marketplace" <<'EOF'
v2026.294.0800
v2026.295.0900
EOF
  cat > "$dir/tags/plugin-task" <<'EOF'
v2026.290.1000
v2026.291.1100
EOF
  cat > "$dir/tags/plugin-strata" <<'EOF'
v2026.293.1253
v2026.294.0100
EOF
}

# The fixture refs list — the same shape the real one has.
write_refs() {
  local dir="$1"
  cat > "$dir/refs.yml" <<'EOF'
charly-marketplace:
    candy:
        candy:
            - '@github.com/opencharly/eval-omarchy:v2026.295.0943'
            - '@github.com/opencharly/layer-charly-internals:v2026.296.0218'
            - '@github.com/opencharly/plugin-marketplace:v2026.296.1000'
            - '@github.com/opencharly/plugin-strata/candy/plugin-strata:v2026.293.1253'
            - '@github.com/opencharly/plugin-task:v0.2026296.500'
            - '@github.com/opencharly/sdk:v0.2026296.803'
            - '@github.com/opencharly/spec:v0.2026296.734'
EOF
}

# A case directory: the shipped scripts (or a mutated copy of them), the fixture refs list, the
# fixture tags, and a stub `gh` that answers the ONE call the resolver makes.
make_case() {
  local dir="$1" resolver="$2"
  mkdir -p "$dir/scripts" "$dir/bin"
  cp "$HERE/refresh-refs.sh" "$dir/scripts/refresh-refs.sh"
  cp "$resolver" "$dir/scripts/resolve_pin_tag.py"
  write_tags "$dir"
  write_refs "$dir"
  cat > "$dir/bin/gh" <<SH
#!/usr/bin/env bash
# The stub: the resolver asks for one repo's tags and nothing else.
if [ "\$1" = "api" ]; then
  repo="\${2#repos/opencharly/}"
  repo="\${repo%/tags}"
  if [ -f "$dir/tags/\$repo" ]; then cat "$dir/tags/\$repo"; fi
  exit 0
fi
exit 0
SH
  chmod +x "$dir/bin/gh"
}

run_case() {
  local dir="$1"
  ( cd "$dir" && PATH="$dir/bin:$PATH" bash scripts/refresh-refs.sh "$dir/refs.yml" ) \
    > "$dir/out.log" 2>&1
  echo $? > "$dir/rc"
}

# The expectations. Each one is a rule the resolver must hold; a failure is printed with the
# line that broke it.
assert_case() {
  local dir="$1" label="${2:-}"
  CASE_FAILS=0
  _ck() {  # _ck <description> <condition-result 0/1>
    if [ "$2" -eq 0 ]; then
      [ -n "$label" ] || ok "$1"
    else
      printf '  FAIL  %s%s\n' "${label:+$label: }" "$1" >&2
      CASE_FAILS=$((CASE_FAILS + 1))
    fi
  }
  local out="$dir/out.log" refs="$dir/refs.yml"
  local rc; rc="$(cat "$dir/rc")"

  # The Go-module pins stay Go-module versions. `spec` is ALREADY at the newest tag in its
  # own scheme, so it must not move at all — and it must not be handed the superproject's
  # newer tag, which is what the broken resolver did.
  grep -q "@github.com/opencharly/spec:v0.2026296.734" "$refs"
  _ck "the Go-module pin spec stays at v0.2026296.734" $?
  grep -q "@github.com/opencharly/spec:v2026" "$refs"
  _ck "the Go-module pin spec is NOT moved to a superproject tag" $((1 - $?))
  grep -qE "^  sdk +v0\.2026296\.803 -> v0\.2026297\.101" "$out"
  _ck "the Go-module pin sdk advances WITHIN its own scheme" $?
  grep -q "@github.com/opencharly/sdk:v0.2026297.101" "$refs"
  _ck "the rewritten refs list carries the Go-module tag" $?

  # A superproject pin advances within the superproject scheme, and the presence of a
  # Go-module tag in the same repo does not confuse it.
  grep -qE "^  layer-charly-internals +v2026\.296\.0218 -> v2026\.297\.0500" "$out"
  _ck "a superproject pin advances within its own scheme" $?

  # A pin already at the newest tag in its scheme does not move, and is NOT reported.
  grep -q "eval-omarchy" "$out"
  _ck "a pin that is already current is not reported as advanced" $((1 - $?))

  # A pin whose newest in-scheme tag is OLDER does not move, and says so.
  grep -qE "^  UNRESOLVED plugin-marketplace +.*OLDER.*pin left at v2026\.296\.1000" "$out"
  _ck "a pin whose newest in-scheme tag is OLDER stays and is reported" $?
  grep -q "@github.com/opencharly/plugin-marketplace:v2026.296.1000" "$refs"
  _ck "the backward-refused pin is left at its own tag" $?

  # A repo that publishes no tag in the pin's scheme does not get a tag of another scheme.
  grep -qE "^  UNRESOLVED plugin-task +.*no tag in the scheme.*pin left at v0\.2026296\.500" "$out"
  _ck "a pin with no tag in its scheme stays and is reported" $?
  grep -q "@github.com/opencharly/plugin-task:v0.2026296.500" "$refs"
  _ck "the scheme-less pin is left at its own tag" $?

  # A plugin pin's /candy/<name> subpath is preserved verbatim; only the tag moves.
  grep -q "@github.com/opencharly/plugin-strata/candy/plugin-strata:v2026.294.0100" "$refs"
  _ck "the plugin pin's subpath is preserved and its tag advanced" $?

  # The summary line carries the counts the refresh PR body parses.
  grep -q "refresh-refs: 3 pin(s) advanced, 2 unresolved" "$out"
  _ck "the summary line counts the advances and the unresolved pins" $?

  # Exactly the three advancing pins are reported as advancing.
  [ "$(grep -cE '^  [a-z].* -> ' "$out")" -eq 3 ]
  _ck "exactly three pins are reported as advanced" $?

  [ "$rc" -eq 0 ]
  _ck "the resolver exits 0" $?
}

# A RED ARM: mutate a COPY of the shipped resolver and require this suite to go red under it.
# The mutation must apply to exactly one line — a mutation that silently matched nothing would
# make the arm vacuous, and the arm is what proves the suite can fail.
red_arm() {
  local label="$1" from="$2" to="$3"
  local dir="$WORK/arm-$label"
  make_case "$dir" "$HERE/resolve_pin_tag.py"
  if ! python3 - "$dir/scripts/resolve_pin_tag.py" "$from" "$to" <<'PY'
import sys
p, frm, to = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(p, encoding="utf-8").read()
n = src.count(frm)
if n != 1:
    sys.exit(f"the mutation target matched {n} lines, want exactly 1: {frm!r}")
open(p, "w", encoding="utf-8").write(src.replace(frm, to))
PY
  then
    bad "the $label mutation did not apply to the resolver"
    return
  fi
  run_case "$dir"
  printf '  ARM  %s: the suite must turn RED under this mutation\n' "$label"
  assert_case "$dir" "$label"
  if [ "$CASE_FAILS" -gt 0 ]; then
    ok "the $label arm turns the suite RED ($CASE_FAILS expectation(s) broken)"
  else
    bad "the $label arm left the suite GREEN — the suite cannot fail"
  fi
}

# ---------------------------------------------------------------- the suite itself
make_case "$WORK/main" "$HERE/resolve_pin_tag.py"
run_case "$WORK/main"
assert_case "$WORK/main"
[ "$CASE_FAILS" -eq 0 ] || FAILS=$((FAILS + 1))

# The two rules, each proved to be load-bearing by removing it.
red_arm "scheme-filter-removed" \
  '        if not same_scheme(old_parts, cand):' \
  '        if False:'
red_arm "backward-guard-removed" \
  '    if compare(best_parts, old_parts) < 0:' \
  '    if False:'

echo
if [ "$FAILS" -eq 0 ]; then echo "PASS — refresh-refs resolver assertions passed"; exit 0; fi
echo "FAIL — $FAILS assertion(s) failed"; exit 1
