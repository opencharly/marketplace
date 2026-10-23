#!/usr/bin/env bash
# refresh-refs.sh — advance every @github pin in the refs list to that repo's newest tag
# IN THE PIN'S OWN SCHEME.
#
# The refs list (candy/charly-marketplace/charly.yml) is the ONE generation input since the
# candy de-submodule cutover, and every entry is a hand-written CalVer pin. Hand-written pins
# go stale silently: the corpus keeps building, every gate stays green, and the published
# skill is simply an old one. That is the failure the whole cutover exists to remove, and it
# comes straight back if the list is maintained by hand.
#
# This resolves each pinned repo's newest tag and rewrites the pin. It does NOT regenerate
# and it does NOT commit — the caller does both, so the script is safe to run and inspect.
#
# WHY A SCHEME AND NOT "THE NEWEST TAG". A pin in this list is a Go-module version, and two
# tag schemes live in this org: the superproject's `v<YYYY>.<DDD>.<HHMM>` and the Go-module
# `v0.<YYYYDDD>.<HHMM>`. A repo can publish BOTH — `spec` and `sdk` do. Taking the newest
# tag of ANY scheme moved those two pins to a superproject tag, which is not a valid Go
# module version, and moved them BACKWARD in time while doing so: the Go-module scheme's
# first component is the fixed major `0`, which sorts below the year `2026`. The resolver is
# `scripts/resolve_pin_tag.py`, and the SCHEME it resolves in is the one the pin already
# carries — so a Go-module pin stays a Go-module version, and no pin ever moves backward.
#
# Output: a one-line-per-change report on stdout; exit 0 whether or not anything moved.
# Set REFRESH_DRY_RUN=1 to report without writing.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REFS="${1:-candy/charly-marketplace/charly.yml}"
[[ -f "$REFS" ]] || { echo "refresh-refs: no refs list at $REFS" >&2; exit 1; }

# Every pin looks like `@github.com/opencharly/<repo>[/candy/<name>]:v<CalVer>`. The optional
# /candy/<name> subpath belongs to plugin repos and must be preserved verbatim — only the tag
# after the final colon moves.
mapfile -t PINS < <(grep -oE "@github\.com/opencharly/[A-Za-z0-9._/-]+:v[0-9]+\.[0-9]+\.[0-9]+" "$REFS" | sort -u)

printf 'refresh-refs: %d distinct pin(s) in %s\n' "${#PINS[@]}" "$REFS"

# The resolver's explanation for a pin that does not move, and the API's, land here. One file,
# reused: it is truncated by each redirect that writes to it.
ERRFILE="$(mktemp)"
trap 'rm -f "$ERRFILE"' EXIT

changed=0
unresolved=0
for pin in "${PINS[@]}"; do
  path="${pin%:*}"                 # @github.com/opencharly/<repo>[/candy/<name>]
  old="${pin##*:}"                 # v<CalVer>
  rest="${path#@github.com/opencharly/}"
  repo="${rest%%/*}"               # the REPO is the first segment; the rest is a subpath

  # The repo's tags, and the resolver's decision about them. Newest by VERSION, not by
  # creation order: `gh api .../tags` is push-ordered, and a backfilled tag on an older commit
  # would otherwise look newest. Newest WITHIN THE PIN'S SCHEME, not newest overall.
  if tags="$(gh api "repos/opencharly/$repo/tags" --paginate --jq '.[].name' 2>"$ERRFILE")"; then
    if new="$(printf '%s\n' "$tags" | python3 "$HERE/resolve_pin_tag.py" --old "$old" 2>"$ERRFILE")"; then
      [[ "$new" == "$old" ]] && continue
      printf '  %-44s %s -> %s\n' "$repo" "$old" "$new"
      changed=$((changed + 1))
      if [[ "${REFRESH_DRY_RUN:-0}" != "1" ]]; then
        # Anchor on the FULL old pin so a repo whose name is a prefix of another cannot be hit.
        python3 - "$REFS" "$pin" "$path:$new" <<'PY'
import sys
from pathlib import Path
p, old, new = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
t = p.read_text()
if old not in t:
    sys.exit(f"anchor vanished: {old}")
p.write_text(t.replace(old, new))
PY
      fi
    else
      # A pin that cannot be advanced safely is REPORTED, and the count of unresolved pins
      # carries it into the run's summary line. The reason says which case it was: the repo
      # publishes no tag in the pin's scheme, or the newest one it has is older than the pin.
      printf '  UNRESOLVED %-44s (%s; pin left at %s)\n' "$repo" "$(cat "$ERRFILE")" "$old"
      unresolved=$((unresolved + 1))
      continue
    fi
  else
    printf '  UNRESOLVED %-44s (cannot list the tags: %s; pin left at %s)\n' \
      "$repo" "$(cat "$ERRFILE")" "$old"
    unresolved=$((unresolved + 1))
    continue
  fi
done

printf 'refresh-refs: %d pin(s) advanced, %d unresolved\n' "$changed" "$unresolved"
