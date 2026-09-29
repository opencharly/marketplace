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
# DETERMINISTIC TEST SEAMS (env overrides; all unset in production):
#   WATCH_SLEEP_HOOK <secs>              called INSTEAD of sleeping (assert backoff)
#   WATCH_REARM_HOOK <script> <args...>  called INSTEAD of the detached successor spawn
#   WATCH_RATE_HOOK                      prints the core API remaining, instead of gh
#   WATCH_RUNTIME_DIR                    where lock/holder/log files live
#   WATCH_RATE_MIN                       back off below this core quota (default 200)
#   WATCH_RATE_MAX_SLEEP                 backoff ceiling, seconds (default 600)
#   ALLOW_FAST_POLL=1                    the ONLY escape hatch for --interval < POLL_FLOOR,
#                                        for deterministic TESTS ONLY — never a production
#                                        setting (see the poll-floor section below)
#
# ── THE HARNESS CONSTRAINT (why --auto-rearm exists) ── ONE canonical statement here ──
#   An agent is woken ONLY when a background command COMPLETES. A watcher that never
#   exits therefore gives NO wake, and a one-shot watcher that exits leaves NOTHING
#   watching until an agent re-arms it — a step that gets dropped (field evidence:
#   nothing was watching; duplicate watchers stacked; the API budget was exhausted).
#   Two supported patterns:
#     * PER-EVENT notify — a one-shot run (default `--no-rearm`): it exits on the event,
#       the harness wakes the agent, and the AGENT re-arms.
#     * DURABILITY — `--auto-rearm`: on a non-terminal exit the watcher DETACHES a
#       successor with the SAME args, lock-guarded so EXACTLY ONE stays active, so a
#       watch is ALWAYS alive independent of the agent.
#   `--auto-rearm` keeps a WATCH alive; the AGENT's re-arm keeps NOTIFICATIONS alive (a
#   detached successor's event line goes to its log, so the agent is woken only by the
#   watcher the AGENT armed). A durable supervisor never exits ⇒ never wakes, so it is
#   NOT the answer.
#   SINGLE INSTANCE: a per-args lockfile (flock) — repeated arms NEVER stack; a
#   foreground arm TAKES OVER a live peer cleanly.
#   RATE LIMITS: pollers share the account's 5000/hr core budget; the remaining quota is
#   read from the FREE `/rate_limit` endpoint and the watcher BACKS OFF below
#   $WATCH_RATE_MIN instead of hammering into the observed HTTP-403 wall.
# ── The two watcher scripts carry only a one-line pointer to this block. ──

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

# ── the poll floor ────────────────────────────────────────────────────────────
# ONE watcher, at most one poll per minute. MEASURED (2026-09-28): the pre-floor
# defaults (30s gh_watch / 20s pr_watch_many / 15s pr_state_watch) with gh_watch's
# ~5 gh calls per item per poll exhausted the account's shared 5000/hr core budget
# (repeated HTTP 403) and contributed to host load. A 20s watcher over 5 items is
# ~5400 calls/hr ALONE — a budget incident. So the default interval is 60s AND a
# hard floor of 60s rejects faster cadences at argument parse time, so no silent
# sub-floor polling ever ships. Tests that must run fast opt in LOUDLY and
# explicitly via ALLOW_FAST_POLL=1 (never a committed default).
POLL_FLOOR=60

# watch_interval <label> <interval> <raw-source> — validate an interval against the
# floor and print the accepted value on stdout (call as `X="$(watch_interval …)" || exit 5`).
# <raw-source> is "the INTERVAL env/default" or "--interval", for the error message.
# On a non-integer or a sub-floor interval WITHOUT ALLOW_FAST_POLL=1 it prints the
# refusal to stderr and returns 1 — the CALLER exits, never a silent clamp (a clamp
# would hide the intent). The `$(…)` subshell is why this `return`s rather than exits.
watch_interval() {
  local label="$1" iv="$2" source="$3"
  # Always require >= 1 second (a 0-second interval busy-loops); the floor then
  # raises that to 60 unless ALLOW_FAST_POLL=1.
  if ! watch_is_uint "$iv" || [ "$iv" -lt 1 ]; then
    echo "$label: $source must be an integer >= 1, got '$iv'" >&2
    return 1
  fi
  if [ "$iv" -lt "$POLL_FLOOR" ] && [ "${ALLOW_FAST_POLL:-0}" != "1" ]; then
    echo "$label: $source must be >= $POLL_FLOOR seconds (one poll per minute — the shared API budget)," >&2
    echo "  got '$iv'. Fast polling is reserved for tests: set ALLOW_FAST_POLL=1 to override." >&2
    return 1
  fi
  printf '%s' "$iv"
}

# watch_rate_backoff_factor — the rate-guard multiplier/divisor, env-tunable for tests
# only. Default 2: back the sleep off 2x when the quota is low. `1` disables the
# factor and leaves a fixed sleep (the deterministic test seam).
watch_rate_backoff_factor() {
  local f="${WATCH_RATE_BACKOFF_FACTOR:-2}"
  watch_is_uint "$f" && [ "$f" -ge 1 ] || f=2
  printf '%s' "$f"
}

# gql_alias <item> — the GraphQL alias for one "owner/repo#num" item. GraphQL alias
# names allow only [A-Za-z0-9_], so the whole item is sanitized to that set. It is
# derived the SAME way in gh_watch.sh's request builder AND response parser (and in
# the test fixtures) so the two can never drift.
gql_alias() { printf 'r_%s' "$(printf '%s' "$1" | tr -c 'A-Za-z0-9_' '_')"; }

# watch_run_latest <owner/repo> <workflow-name> — the newest COMPLETED run of
# <workflow-name> on <owner/repo>, as
#   "id|conclusion|branch|updatedAt|completedEpoch"
# or "" when there is none. `completedEpoch` is the run's COMPLETION time in Unix
# seconds and is the ONLY reliable newness gate: a run that completed at or before
# the watcher armed can never be a new event, however its id compares. An id
# compare ALONE false-fires when the "newest completed" run CHANGES to a different
# but still-old run (a seed/poll ordering shift, or a transient seed failure).
# Runs a `gh` child, so it closes the lock fd (9) FIRST — a poll child must not inherit
# the flock, or a hung `gh` would hold the lock after we exit (called in a `$(…)`
# subshell, so the parent's fd 9 is untouched). gh's own --jq takes no --arg, so pipe to jq.
watch_run_latest() {
  { exec 9>&-; } 2>/dev/null || true
  local out rc
  out="$(gh run list -R "$1" --limit 30 \
    --json databaseId,name,status,conclusion,headBranch,updatedAt 2>&1)"; rc=$?
  # A rate-limit signal in the output is a STOP: abort (7) rather than report "no run"
  # (which a caller would treat as a benign empty seed and keep polling). Because this
  # helper is called INSIDE a `$(…)`, `exit 7` ends the whole watcher (the caller's
  # assignment runs in a subshell) — the correct hard abort.
  if watch_is_rate_limited "$out"; then
    watch_fatal_rate_limit "watcher" "$(printf '%s' "$out" | head -c 200)"
  fi
  [ "$rc" -eq 0 ] || { printf '%s' "$out" >&2; return 1; }
  printf '%s' "$out" \
    | jq -r --arg n "$2" '
        [.[] | select(.name==$n and .status=="completed")][0]
        | if .==null then ""
          else "\(.databaseId)|\(.conclusion)|\(.headBranch)|\(.updatedAt)|\(.updatedAt | fromdateiso8601)" end' 2>/dev/null
}

# ── rate-limit discipline ─────────────────────────────────────────────────────
# The pollers share the account's 5000/hr core quota; unthrottled polling exhausts
# it (observed HTTP 403, watchers dead). The `/rate_limit` endpoint is FREE (GitHub
# does not count it against the primary limit), so it is safe to read every poll.
# The guard reads that endpoint BEFORE each poll; below $WATCH_RATE_MIN (default
# 200) it MULTIPLIES the interval by $WATCH_RATE_BACKOFF_FACTOR (default 2, capped
# at $WATCH_RATE_MAX_SLEEP=600s) and skips the poll entirely. The floor (60s) alone
# bounds the steady-state draw; the guard is the second line that turns a shared
# budget into a soft back-off instead of a 403 wall.

# watch_rate_remaining — the core-quota remaining as a bare integer, or "" if the
# read failed (treated as UNKNOWN → do not back off on an unknown).
# Runs a `gh` child, so it closes the lock fd (9) FIRST — every poll child must not
# inherit the flock, or a hung `gh` would hold the lock after we exit (this function is
# only ever called in a `$(…)` subshell, so the parent's fd 9 is untouched).
watch_rate_remaining() {
  { exec 9>&-; } 2>/dev/null || true
  if [ -n "${WATCH_RATE_HOOK:-}" ]; then "$WATCH_RATE_HOOK"; return 0; fi
  gh api rate_limit --jq '.resources.core.remaining' 2>/dev/null || echo ""
}

# watch_rate_gate <interval-secs> — 0 = OK to poll NOW; 1 = the quota is below
# $WATCH_RATE_MIN, so we backed off (slept a longer interval) and the caller must
# `continue` without polling. Never exits; never hammers.
watch_rate_gate() {
  local base="$1" label="${2:-watcher}" rem next factor
  rem="$(watch_rate_remaining)"
  [ -z "$rem" ] && return 0
  watch_is_uint "$rem" || return 0
  # A genuine ZERO is a rate-limit STOP, not a slow down: abort (never sleep into the
  # 403 wall, never treat it as a skipped poll).
  [ "$rem" -eq 0 ] && watch_fatal_rate_limit "$label" "core quota exhausted (remaining=0)"
  [ "$rem" -ge "${WATCH_RATE_MIN:-200}" ] && return 0
  factor="$(watch_rate_backoff_factor)"
  next=$(( base * factor ))
  [ "$next" -gt "${WATCH_RATE_MAX_SLEEP:-600}" ] && next="${WATCH_RATE_MAX_SLEEP:-600}"
  [ "$next" -lt 1 ] && next=1
  printf 'RATE-LIMIT  core remaining=%s < %s — backing off %ss\n' \
    "$rem" "${WATCH_RATE_MIN:-200}" "$next" >&2
  watch_sleep "$next"
  return 1
}

# ── rate-limit HARD ABORT (a stop condition, never a retry) ───────────────────
# A rate limit is not a transient: retrying hammers the wall and hides the cause.
# The moment a poll observes a rate-limit signal — HTTP 403/429, a body/header
# `x-ratelimit-remaining: 0`, or a GraphQL `errors[].type == RATE_LIMIT` — the
# watcher prints a FATAL naming the reset instant and exits NON-ZERO (7). MEASURED
# trap: `gh api graphql` exits 0 while its JSON body carries the RATE_LIMIT error,
# so a caller that trusted the exit code alone would silently treat the empty body
# as "no event" — hence `watch_is_rate_limited` inspects the PAYLOAD too.
WATCH_EXIT_RATE_LIMIT=7

# watch_rate_reset — the core-quota reset as a Unix epoch, or "" if unknown. Prefers
# the legacy top-level `.rate.reset`; falls back to `.resources.core.reset`.
watch_rate_reset() {
  { exec 9>&-; } 2>/dev/null || true
  local r
  r="$(gh api rate_limit --jq '.rate.reset // .resources.core.reset' 2>/dev/null || echo "")"
  printf '%s' "$r"
}

# watch_is_rate_limited <text> — success (0) iff <text> (a poll's combined output)
# carries a rate-limit signal. Matches the REST 403/429 wall AND the GraphQL
# RATE_LIMIT error type (case-insensitive on the message), so both transports are
# covered by ONE predicate.
watch_is_rate_limited() {
  local t="$1"
  case "$t" in
    *'"type":"RATE_LIMIT"'*|*'"type": "RATE_LIMIT"'*|*RATE_LIMITED*|*'rate limit already exceeded'*|*'API rate limit exceeded'*|*'HTTP 403'*|*'HTTP 429'*|*'x-ratelimit-remaining: 0'*) return 0 ;;
  esac
  return 1
}

# watch_rc_guard <rc> — re-raise a rate-limit abort that happened INSIDE a `$(…)`
# subshell. A gh helper cannot `exit 7` the parent (the subshell traps its own exit),
# so callers capture the subshell's rc and pass it here: 7 → the parent exits 7 too
# (the hard abort survives the command-substitution boundary); any other rc is left to
# the caller's own handling.
watch_rc_guard() {
  [ "${1:-0}" -eq "$WATCH_EXIT_RATE_LIMIT" ] && exit "$WATCH_EXIT_RATE_LIMIT"
  return 0
}

# watch_fatal_rate_limit <script-label> <detail> — print the FATAL (with the reset
# instant) and exit 7. Called from a poll the moment a rate-limit signal is seen, so
# the process stops rather than hammering. The reset read uses the FREE `/rate_limit`
# endpoint, which still answers while the primary quota is exhausted.
watch_fatal_rate_limit() {
  local label="$1" detail="$2" reset when
  reset="$(watch_rate_reset)"
  if watch_is_uint "$reset" && [ "$reset" -gt 0 ]; then
    when="$(date -u -d "@$reset" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "$reset")"
  else
    when="unknown"
  fi
  printf 'FATAL %s: GitHub rate limit reached — ABORTING (never retry a rate limit).\n' "$label" >&2
  printf '  signal: %s\n' "$detail" >&2
  printf '  quota resets at: %s\n' "$when" >&2
  printf '  poll floor is %ss by default; raise --interval or wait for the reset.\n' "$POLL_FLOOR" >&2
  exit "$WATCH_EXIT_RATE_LIMIT"
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

# watch_lock <key> [--takeover] — acquire the single-instance lock.
#   (no mode)      fail-fast: return 1 if another watcher holds it
#   --takeover     displace a LIVE PEER WATCHER (same family) holding it, then acquire
# On success fd 9 holds the flock for the process lifetime and the holder PID is
# recorded. Returns 0 on acquire, 1 if not acquired.
# NOTE: there is deliberately NO `--wait` mode. A successor never WAITS — it INHERITS
# fd 9 from the process that spawned it (see `watch_rearm`/`watch_lock_auto`), so the
# waiting variant has no caller and was removed (R5).
watch_lock() {
  local key="$1" mode="${2:-}" holder pid
  WATCH_LOCK_KEY="$key"
  exec 9>"$(watch_lock_file "$key")" || return 1
  if flock -n 9 2>/dev/null; then printf '%s' "$$" > "$(watch_holder_file "$key")"; return 0; fi
  case "$mode" in
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
# role. TWO cases:
#
#   1. WATCH_INHERITED_LOCK=1 — a DETACHED SUCCESSOR, which INHERITED fd 9 (the flock)
#      from the process that spawned it. It ALREADY holds the lock (the flock lives on
#      the open file description the parent and child share) — so it does NOT acquire,
#      does NOT wait, and does NOT close the fd. The lock is therefore held CONTINUOUSLY
#      across the hand-off: no gap (a new arm can never slip in) and no WAITER (so no
#      second live process). It only refreshes the holder PID so a later takeover
#      targets it. THIS is what makes `--auto-rearm` "exactly ONE live watcher".
#   2. otherwise (a FOREGROUND arm) — it TAKES OVER a live peer cleanly.
#
# Returns 0 on acquire; 1 if not acquired.
watch_lock_auto() {
  local key="$1"
  if [ "${WATCH_INHERITED_LOCK:-0}" = "1" ]; then
    WATCH_LOCK_KEY="$key"
    printf '%s' "$$" > "$(watch_holder_file "$key")" 2>/dev/null || true
    return 0
  fi
  watch_lock "$key" --takeover
}

# watch_lock_or_exit <argv0> <name> [args...] — compute the per-args key, acquire the
# lock with the role-appropriate policy, and on failure print `<name>: …` and exit 6.
# ONE shared implementation (R3) — the two watchers differ only in the <name> prefix.
watch_lock_or_exit() {
  local argv0="$1" name="$2"; shift 2
  local key
  key="$(watch_key "$argv0" "$@")"
  if ! watch_lock_auto "$key"; then
    echo "$name: could not acquire the watch lock for key $key" >&2
    exit 6
  fi
  watch_wait_predecessor
}

# watch_wait_predecessor — a successor holds the lock (inherited), but its PREDECESSOR
# may still be in its exit path. Wait (bounded) for the predecessor PID to vanish so
# that AT MOST ONE process is ever in the poll loop — the invariant that makes
# `--auto-rearm` "exactly ONE live watcher". The lock is already held, so this wait
# introduces NO gap and is NOT a lock contention (no other process can slip in). A
# no-op for a foreground arm (no WATCH_PREDECESSOR_PID). Bound: WATCH_PREDECESSOR_WAIT
# (default 15s).
watch_wait_predecessor() {
  local pp="${WATCH_PREDECESSOR_PID:-}"
  [ -n "$pp" ] || return 0
  [ "$pp" = "$$" ] && return 0
  local tries=0 max=$(( ${WATCH_PREDECESSOR_WAIT:-15} * 50 ))
  while [ "$tries" -lt "$max" ] && kill -0 "$pp" 2>/dev/null; do
    command sleep 0.02
    tries=$((tries + 1))
  done
  return 0
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
# watch survives this process exiting. ATOMIC LOCK HAND-OFF: the successor INHERITS our
# flock fd (fd 9, NOT closed) and is told so via WATCH_INHERITED_LOCK=1, so it already
# holds the lock — the lock is held CONTINUOUSLY across the swap, with NO waiter and NO
# gap (a new arm can never slip in, and there is never a second live watcher).
# Prints the successor PID + log to stderr so the event line on stdout stays clean.
watch_rearm() {
  local script="$1"; shift
  local key log
  key="$(watch_key "$script" "$@")"
  log="$(watch_log_file "$key")"
  if [ -n "${WATCH_REARM_HOOK:-}" ]; then "$WATCH_REARM_HOOK" "$script" "$@"; return 0; fi
  # NOTE: fd 9 is deliberately INHERITED (no `9>&-`): the child shares the open file
  # description, so the flock is held across the hand-off with no gap and no waiter.
  # WATCH_PREDECESSOR_PID lets the successor wait for US to exit before it polls, so at
  # most ONE process is ever in the poll loop.
  if command -v setsid >/dev/null 2>&1; then
    WATCH_INHERITED_LOCK=1 WATCH_PREDECESSOR_PID="$$" \
      setsid nohup "$script" "$@" </dev/null >>"$log" 2>&1 &
  else
    WATCH_INHERITED_LOCK=1 WATCH_PREDECESSOR_PID="$$" \
      nohup "$script" "$@" </dev/null >>"$log" 2>&1 &
  fi
  disown 2>/dev/null || true
  printf 'RE-ARMED  successor pid %s → %s\n' "$!" "$log" >&2
}

# ── exit-trap plumbing (the auto-rearm decision lives HERE, once) ─────────────
WATCH_REARM_FLAG=0        # 1 = --auto-rearm
WATCH_REARM_SCRIPT=""
WATCH_REARM_ARGS=()
WATCH_DONE=0              # 1 = a TERMINAL/STATE fire (nothing left to watch → no re-arm)
WATCH_REARMED=0           # 1 = a successor was ALREADY spawned by THIS run (a latch)
# WATCH_INHERITED_LOCK=1 marks a successor that INHERITED fd 9 (the flock) and already
# holds the lock — the atomic hand-off that makes `--auto-rearm` "exactly ONE live
# watcher". It NEVER resets (a bare `WATCH_INHERITED_LOCK=0` would clobber the child's
# env): it arrives from the detached child's environment (set by `watch_rearm`).
: "${WATCH_INHERITED_LOCK:=0}"

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
