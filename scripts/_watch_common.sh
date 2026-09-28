#!/usr/bin/env bash
# _watch_common.sh — shared helpers for the watcher family (SOURCED, never executed).
#
# This file exists so each helper lives ONCE (R3): pr_watch_many.sh and gh_watch.sh
# source it instead of each carrying its own copy. It is NOT a CLI — it prints nothing
# and has no argument parser. The calling script owns its own shell options
# (`set -euo pipefail`), PATH checks, and exit codes.
#
# Requires at call time (verified by the sourcing script): bash, gh, jq.

# watch_usage <script-path> — print a script's leading comment block (shebang
# excluded) as its usage text, so `--help` is derived from the file itself and can
# never drift out of range the way a hardcoded `sed -n 'a,bp'` does.
watch_usage() {
  awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$1"
}

# watch_is_uint <value> — success (0) iff the value is a non-empty run of digits.
# Validates --interval/--stallmin/--timeout. Call as `watch_is_uint x || { …; exit 5; }`.
watch_is_uint() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# watch_has <event> <comma-list> — success iff <event> is a member of the comma list.
watch_has() { case ",$2," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

# watch_run_latest <owner/repo> <workflow-name> — the newest COMPLETED run of
# <workflow-name> on <owner/repo>, as "id|conclusion|branch|updatedAt", or "" when
# there is none. The progress signal is a COMPLETED run, never session activity.
# gh's own --jq takes no --arg, so pipe to jq.
watch_run_latest() {
  gh run list -R "$1" --limit 30 \
    --json databaseId,name,status,conclusion,headBranch,updatedAt 2>/dev/null \
    | jq -r --arg n "$2" '
        [.[] | select(.name==$n and .status=="completed")][0]
        | if .==null then "" else "\(.databaseId)|\(.conclusion)|\(.headBranch)|\(.updatedAt)" end' 2>/dev/null
}
