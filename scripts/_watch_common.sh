#!/usr/bin/env bash
# _watch_common.sh — shared helpers for the watcher family (SOURCED, never executed).
#
# This file exists so each helper lives ONCE (R3): pr_watch_many.sh and gh_watch.sh
# source it instead of each carrying its own copy. It is NOT a CLI — it prints nothing
# and has no argument parser. The calling script owns its own shell options
# (`set -uo pipefail`), PATH checks, and exit codes.
#
# Requires at call time (verified by the sourcing script): bash, gh, jq, flock.
#
# THE HARNESS CONSTRAINT THIS FILE EXISTS FOR
#   An agent is woken ONLY when a background command COMPLETES. So a watcher that never
#   exits produces NO wake, and a one-shot watcher that exits leaves NOTHING watching
#   until an agent re-arms it — a step that gets dropped. The resolution: keep a watch
#   ALIVE with `--auto-rearm` (each run, on exit, detaches a successor with the SAME
#   args, lock-guarded so exactly ONE is ever active) while the AGENT's re-arm keeps
#   NOTIFICATIONS alive. See `watch_install_trap` / `watch_rearm`.
#
# DETERMINISTIC TEST SEAMS (env overrides; all unset in production):
#   WATCH_SLEEP_HOOK <secs>              called INSTEAD of sleeping (assert backoff)
#   WATCH_REARM_HOOK <script> <args...>  called INSTEAD of the detached successor spawn
#   WATCH_RATE_HOOK                      prints the core API remaining, instead of gh
#   WATCH_RUNTIME_DIR                    where lock/holder/log files live
#   WATCH_RATE_MIN                       back off below this core quota (default 200)
#   WATCH_RATE_MAX_SLEEP                 backoff ceiling, seconds (default 600)

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
# <workflow-name> on <owner/repo>, as
#   "id|conclusion|branch|updatedAt|completedEpoch"
# or "" when there is none. `completedEpoch` is the run's COMPLETION time in Unix
# seconds and is the ONLY reliable newness gate: a run that completed at or before
# the watcher armed can never be a new event, however its id compares. An id
# compare ALONE false-fires when the "newest completed" run CHANGES to a different
# but still-old run (a seed/poll ordering shift, or a transient seed failure).
# gh's own --jq takes no --arg, so pipe to jq.
watch_run_latest() {
  gh run list -R "$1" --limit 30 \
    --json databaseId,name,status,conclusion,headBranch,updatedAt 2>/dev/null \
    | jq -r --arg n "$2" '
        [.[] | select(.name==$n and .status=="completed")][0]
        | if .==null then ""
          else "\(.databaseId)|\(.conclusion)|\(.headBranch)|\(.updatedAt)|\(.updatedAt | fromdateiso8601)" end' 2>/dev/null
}

# ── rate-limit discipline ─────────────────────────────────────────────────────
# The pollers share the account's 5000/hr core quota; unthrottled polling exhausts
# it (observed HTTP 403, watchers dead). The `/rate_limit` endpoint is FREE (GitHub
# does not count it against the primary limit), so it is safe to read every poll.

# watch_rate_remaining — the core-quota remaining as a bare integer, or "" if the
# read failed (treated as UNKNOWN → do not back off on an unknown).
watch_rate_remaining() {
  if [ -n "${WATCH_RATE_HOOK:-}" ]; then "$WATCH_RATE_HOOK"; return 0; fi
  gh api rate_limit --jq '.resources.core.remaining' 2>/dev/null || echo ""
}

# watch_rate_gate <interval-secs> — 0 = OK to poll NOW; 1 = the quota is below
# $WATCH_RATE_MIN, so we backed off (slept a longer interval) and the caller must
# `continue` without polling. Never exits; never hammers.
watch_rate_gate() {
  local base="$1" rem next
  rem="$(watch_rate_remaining)"
  [ -z "$rem" ] && return 0
  watch_is_uint "$rem" || return 0
  [ "$rem" -ge "${WATCH_RATE_MIN:-200}" ] && return 0
  next=$(( base * 4 ))
  [ "$next" -gt "${WATCH_RATE_MAX_SLEEP:-600}" ] && next="${WATCH_RATE_MAX_SLEEP:-600}"
  [ "$next" -lt 1 ] && next=1
  printf 'RATE-LIMIT  core remaining=%s < %s — backing off %ss\n' \
    "$rem" "${WATCH_RATE_MIN:-200}" "$next" >&2
  watch_sleep "$next"
  return 1
}

# watch_sleep <secs> — an interval sleep that a trapped signal INTERRUPTS (so a
# takeover's SIGTERM does not wait out a long sleep: `sleep` in the background +
# `wait`, which a trap cuts short). `9>&-` is ESSENTIAL: the sleep child must not
# inherit the lock fd, or it would hold the lock after we exit. Honors
# WATCH_SLEEP_HOOK for deterministic tests.
watch_sleep() {
  local secs="${1:-1}"
  if [ -n "${WATCH_SLEEP_HOOK:-}" ]; then "$WATCH_SLEEP_HOOK" "$secs"; return 0; fi
  command sleep "$secs" 9>&- &
  wait $! 2>/dev/null || true
}

# ── single-instance lock + the auto-rearm handoff ─────────────────────────────
# A per-args lockfile (flock) guarantees EXACTLY ONE watcher per identical
# invocation: repeated arms never stack, and a detached successor never doubles the
# watch. The holder's PID is recorded so a foreground arm can TAKE OVER a detached
# successor (or a stale duplicate) cleanly.

# watch_key <script> <args...> — a stable, short key for one watcher invocation.
watch_key() {
  local s
  if command -v sha1sum >/dev/null 2>&1; then s="$(printf '%s' "$*" | sha1sum)"
  elif command -v md5sum >/dev/null 2>&1; then s="$(printf '%s' "$*" | md5sum)"
  else s="$(printf '%s' "$*" | cksum)"; fi
  printf '%s' "${s%% *}"
}

watch_runtime_dir() { printf '%s' "${WATCH_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}}"; }
watch_lock_file()   { printf '%s/charly-watch-%s.lock' "$(watch_runtime_dir)" "$1"; }
watch_holder_file() { printf '%s/charly-watch-%s.pid'  "$(watch_runtime_dir)" "$1"; }
watch_log_file()    { printf '%s/charly-watch-%s.log'  "$(watch_runtime_dir)" "$1"; }

WATCH_LOCK_KEY=""

# watch_lock <key> [--wait SECS | --takeover] — acquire the single-instance lock.
#   (no mode)      fail-fast: return 1 if another watcher holds it
#   --wait SECS    block up to SECS for the holder to release (the successor handoff)
#   --takeover     displace a LIVE PEER WATCHER (same family) holding it, then acquire
# On success fd 9 holds the flock for the process lifetime and the holder PID is
# recorded. Returns 0 on acquire, 1 if not acquired.
watch_lock() {
  local key="$1" mode="${2:-}" secs="${3:-0}" holder pid
  WATCH_LOCK_KEY="$key"
  exec 9>"$(watch_lock_file "$key")" || return 1
  if flock -n 9 2>/dev/null; then printf '%s' "$$" > "$(watch_holder_file "$key")"; return 0; fi
  case "$mode" in
    --wait)
      if flock -w "$secs" 9 2>/dev/null; then printf '%s' "$$" > "$(watch_holder_file "$key")"; return 0; fi
      return 1 ;;
    --takeover)
      holder="$(cat "$(watch_holder_file "$key")" 2>/dev/null || echo '')"
      if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then
        pid="$holder"
        # Displace ONLY a live PEER (same family) — never an unrelated recycled PID.
        # A peer's cmdline names the watcher script (`…/gh_watch.sh …`), or the lock key.
        if [ -r "/proc/$pid/cmdline" ] \
           && tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q "watch\|$key"; then
          kill -TERM "$pid" 2>/dev/null || true
        fi
      fi
      # Wait for the LOCK to free (a peer's TERM → `exit 143` → EXIT trap releases fd 9)
      # via the flock PRIMITIVE itself — `flock -w` blocks up to the bound; there is no
      # hand-rolled sleep-poll of the peer's PID (R4).
      if flock -w 5 9 2>/dev/null; then printf '%s' "$$" > "$(watch_holder_file "$key")"; return 0; fi
      return 1 ;;
    *) return 1 ;;
  esac
}

# watch_lock_auto <key> — acquire the lock with the RIGHT policy for this process's
# role: a detached successor (WATCH_REARMED=1) WAITS for the predecessor to release;
# a foreground arm TAKES OVER a live peer. ONE implementation (R3) — the two watchers
# call this and differ only in their error-message prefix.
# Returns 0 on acquire; 1 if not acquired (the caller prints its message + exit 6).
watch_lock_auto() {
  if [ "${WATCH_REARMED:-0}" = "1" ]; then
    watch_lock "$1" --wait 120 || watch_lock "$1" --takeover
  else
    watch_lock "$1" --takeover
  fi
}

# watch_cleanup_lock — remove the holder file IFF it is still ours (so a takeover's
# new holder is never clobbered by the displaced process's exit).
watch_cleanup_lock() {
  [ -n "${WATCH_LOCK_KEY:-}" ] || return 0
  local hp; hp="$(watch_holder_file "$WATCH_LOCK_KEY")"
  [ -f "$hp" ] && [ "$(cat "$hp" 2>/dev/null)" = "$$" ] && rm -f "$hp" 2>/dev/null
  return 0
}

# watch_rearm <script> <args...> — detach a successor with the SAME args, so the
# watch survives this process exiting. The successor (env WATCH_REARMED=1) waits for
# the lock handoff rather than taking over. Prints the successor PID + log path to
# stderr so the event line on stdout stays clean.
watch_rearm() {
  local script="$1"; shift
  local key log
  key="$(watch_key "$script" "$@")"
  log="$(watch_log_file "$key")"
  if [ -n "${WATCH_REARM_HOOK:-}" ]; then "$WATCH_REARM_HOOK" "$script" "$@"; return 0; fi
  # 9>&- is ESSENTIAL: the successor must NOT inherit our flock fd (fd 9), or it would
  # hold its own lock and deadlock on its own `watch_lock --wait`. The successor
  # re-acquires the lock fresh AFTER we exit and release it.
  if command -v setsid >/dev/null 2>&1; then
    WATCH_REARMED=1 setsid nohup "$script" "$@" </dev/null >>"$log" 2>&1 9>&- &
  else
    WATCH_REARMED=1 nohup "$script" "$@" </dev/null >>"$log" 2>&1 9>&- &
  fi
  disown 2>/dev/null || true
  printf 'RE-ARMED  successor pid %s → %s\n' "$!" "$log" >&2
}

# ── exit-trap plumbing (the auto-rearm decision lives HERE, once) ─────────────
WATCH_REARM_FLAG=0        # 1 = --auto-rearm
WATCH_REARM_SCRIPT=""
WATCH_REARM_ARGS=()
WATCH_DONE=0              # 1 = a TERMINAL fire (nothing left to watch → no re-arm)
WATCH_REARMED=0           # 1 = a successor was already spawned this run

# watch_set_rearm <rearm 0|1> <script> [args...] — record the re-arm policy and the
# exact command line a successor must re-run. Installs no trap (the script owns it).
watch_set_rearm() {
  WATCH_REARM_FLAG="$1"; WATCH_REARM_SCRIPT="$2"; shift 2
  WATCH_REARM_ARGS=("$@")
}

# watch_rearm_now — spawn the successor NOW, BEFORE the event line prints and we exit,
# so a watch is ALWAYS alive the instant the agent is woken. Idempotent per run.
watch_rearm_now() {
  [ "${WATCH_REARM_FLAG:-0}" = "1" ] || return 0
  [ "${WATCH_DONE:-0}" = "1" ] && return 0
  [ "${WATCH_REARMED:-0}" = "1" ] && return 0
  WATCH_REARMED=1
  watch_rearm "$WATCH_REARM_SCRIPT" "${WATCH_REARM_ARGS[@]}" 2>/dev/null || true
}

# watch_install_trap <rearm> <script> [args...] — the standard policy for a script
# with no other EXIT cleanup. TERM/INT exit 143 (a takeover is NOT a fire → no re-arm).
watch_install_trap() {
  watch_set_rearm "$@"
  trap 'watch_on_exit_common $?' EXIT
  trap 'exit 143' TERM INT
}

# watch_on_exit_common <exit-code> — the ONE catch-all re-arm decision for exits that
# did NOT already spawn a successor (a fire site calls watch_rearm_now itself). Runs
# the lock cleanup, then detaches a successor IFF: re-arm is on AND the exit was not a
# usage/lock error (5/6) or a takeover (143) AND the run did not end on a TERMINAL fire
# (WATCH_DONE=1) AND a successor was not already spawned (WATCH_REARMED=1). So a
# non-terminal fire, a TIMEOUT, or an unexpected exit all re-arm — a watch is ALWAYS
# alive independent of the agent.
watch_on_exit_common() {
  local code="${1:-0}"
  watch_cleanup_lock
  [ "${WATCH_REARM_FLAG:-0}" = "1" ] || return 0
  case "$code" in 5|6|143) return 0 ;; esac
  [ "${WATCH_DONE:-0}" = "1" ] && return 0
  [ "${WATCH_REARMED:-0}" = "1" ] && return 0
  watch_rearm "$WATCH_REARM_SCRIPT" "${WATCH_REARM_ARGS[@]}" 2>/dev/null || true
  return 0
}
