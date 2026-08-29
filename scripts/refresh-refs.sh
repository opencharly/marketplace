#!/usr/bin/env bash
# refresh-refs.sh — advance every @github pin in the refs list to that repo's newest tag.
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
# Output: a one-line-per-change report on stdout; exit 0 whether or not anything moved.
# Set REFRESH_DRY_RUN=1 to report without writing.
set -euo pipefail

REFS="${1:-candy/charly-marketplace/charly.yml}"
[[ -f "$REFS" ]] || { echo "refresh-refs: no refs list at $REFS" >&2; exit 1; }

# Every pin looks like `@github.com/opencharly/<repo>[/candy/<name>]:v<CalVer>`. The optional
# /candy/<name> subpath belongs to plugin repos and must be preserved verbatim — only the tag
# after the final colon moves.
mapfile -t PINS < <(grep -oE "@github\.com/opencharly/[A-Za-z0-9._/-]+:v[0-9]+\.[0-9]+\.[0-9]+" "$REFS" | sort -u)

printf 'refresh-refs: %d distinct pin(s) in %s\n' "${#PINS[@]}" "$REFS"

changed=0
unresolved=0
for pin in "${PINS[@]}"; do
  path="${pin%:*}"                 # @github.com/opencharly/<repo>[/candy/<name>]
  old="${pin##*:}"                 # v<CalVer>
  rest="${path#@github.com/opencharly/}"
  repo="${rest%%/*}"               # the REPO is the first segment; the rest is a subpath

  # Newest tag by CalVer, not by creation order: `gh api .../tags` is push-ordered, and a
  # backfilled tag on an older commit would otherwise look newest.
  new=$(gh api "repos/opencharly/$repo/tags" --paginate --jq '.[].name' 2>/dev/null \
        | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
        | sort -t. -k1.2,1n -k2,2n -k3,3n \
        | tail -1) || true

  if [[ -z "$new" ]]; then
    printf '  UNRESOLVED %-44s (no CalVer tag; pin left at %s)\n' "$repo" "$old"
    unresolved=$((unresolved + 1))
    continue
  fi
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
done

printf 'refresh-refs: %d pin(s) advanced, %d unresolved\n' "$changed" "$unresolved"
