#!/usr/bin/env bash
# refresh-elide.sh — the ONE implementation of the refresh PR body's evidence elision.
#
# WHY THIS EXISTS. GitHub rejects a PR body over 65536 BYTES, so the body cannot paste
# the generator's log wholesale. On a full refresh that log is ~180 KB, and ~161 KB of it
# is routine per-ref progress that says nothing the body does not already publish.
#
#   * opencharly/marketplace#413 (fixed by #414) elided ONE progress shape — the
#     `Downloading <ref>…` line — and added a byte-size assertion. That was true on
#     2026-10-04, when the log was ~62 KB and the elided share was 40 %.
#   * The generator emits TWO per-ref progress shapes, from two different modules, both
#     on stderr:
#       `Downloading <repo>:<tag>…`            opencharly/spec, refs/git.go
#       `charly: resolving <repo>:<tag> (…)`   opencharly/sdk, candywalk/candywalk.go
#     The second was never in scope, so it was pasted whole. The org grew to ~890 refs
#     and ~180 KB of log; the elided share fell to 40 % and the un-elided share
#     rose to 49 %, so the fix's own arithmetic inverted. Five consecutive daily runs
#     (2026-10-24 … 2026-10-28) then assembled a 117 KB body and were rejected:
#     `117183 bytes; the limit is 65536`. The corpus was frozen for five days.
#     opencharly/marketplace#451.
#
# MEASURED, on the 2026-10-28 run's own log (run 74, 2 278 lines, 179 835 bytes):
#   1 780 progress lines  160 742 bytes   elided
#     496 artifact paths    19 006 bytes   elided
#       2 lines                 87 bytes   KEPT — the toolchain line and the report line
#
# WHAT IS ELIDED, and why each class is safe to elide. The classes are declared HERE, in
# one place, so a new shape is one line rather than a re-derivation.
#
#   CLASS 1 — routine per-ref progress: `Downloading <ref>…` and `charly: resolving
#     <ref> (N resolved, M queued)`. One pair per ref, on stderr. Every ref they name is
#     already listed by the body's pins-advanced section and by its changed-file list, so
#     they carry no information the body does not already publish.
#
#   CLASS 2 — the generator's own artifact-path list. The generator prints every artifact
#     it wrote as `  <path>` (plugin-marketplace, generate.go: `fmt.Printf("  %s\n", …)`).
#     Every artifact that CHANGED is already named by the body's changed-file list, and
#     the full list grows with the corpus — which is exactly what must never be able to
#     push the body over GitHub's cap.
#     The line must be a PATH: two spaces, then one whitespace-free token. The rule is
#     deliberately narrow, because the elision errs toward KEEPING — a line it is not
#     sure about is pasted, and a false negative costs body space while a false positive
#     hides evidence. The real log carries exactly one two-space line that is not a
#     path — `  GOTOOLCHAIN: local`, the generator's toolchain line — and it is KEPT.
#
# EVERYTHING ELSE IS PASTED VERBATIM: the generator's report lines, every warning, every
# error. A warning is the one thing this section exists to surface, so it is never elided
# by a class that is not declared above. The elision is measured, not assumed: the notice
# names each class's line count and byte count, and the count of lines actually shown.
#
# usage: refresh-elide.sh <log-file> <block-out> <notice-out>
#   <block-out>   the elided block, verbatim
#   <notice-out>  the elision notice (Markdown)
# exit 0 · 1 when the log is missing or empty (the evidence is gone, and the run must fail
# loud rather than publish a body that claims it) · 2 on a usage error
set -uo pipefail
export LC_ALL=C

LOG="${1:-}"
BLOCK="${2:-}"
NOTICE="${3:-}"
if [ -z "$LOG" ] || [ -z "$BLOCK" ] || [ -z "$NOTICE" ]; then
  echo "usage: refresh-elide.sh <log-file> <block-out> <notice-out>" >&2
  exit 2
fi
if [ ! -s "$LOG" ]; then
  echo "refresh-elide: $LOG is missing or empty — the generator's output IS this body's" >&2
  echo "  evidence; the run must fail loud here rather than publish a body that claims it." >&2
  exit 1
fi

# CLASS 1 — the two routine per-ref progress shapes.
progress_lines=0
progress_bytes=0
# CLASS 2 — the generator's artifact-path list.
artifact_lines=0
artifact_bytes=0
# What is actually shown.
kept_lines=0
kept_bytes=0
total_lines=0
total_bytes=0

: > "$BLOCK"
while IFS= read -r line || [ -n "$line" ]; do
  total_lines=$((total_lines + 1))
  # +1 for the newline the file carries (the last line may not have one; the byte
  # totals are an upper bound either way, and an upper bound is the safe direction).
  n=$(( ${#line} + 1 ))
  total_bytes=$((total_bytes + n))
  case "$line" in
    "Downloading "*|"charly: resolving "*)
      progress_lines=$((progress_lines + 1))
      progress_bytes=$((progress_bytes + n))
      continue
      ;;
  esac
  # CLASS 2: exactly two spaces, then ONE whitespace-free token — the generator's
  # `  <path>` lines. A two-space line holding anything else (`  GOTOOLCHAIN: local`)
  # is NOT a path and is kept: the elision errs toward keeping.
  if [[ "$line" =~ ^\ \ ([^[:space:]]+)$ ]]; then
    artifact_lines=$((artifact_lines + 1))
    artifact_bytes=$((artifact_bytes + n))
    continue
  fi
  kept_lines=$((kept_lines + 1))
  kept_bytes=$((kept_bytes + n))
  printf '%s\n' "$line" >> "$BLOCK"
done < "$LOG"

{
  echo "> **Elision notice — read this before quoting the block above.** The generator's log is"
  echo "> **${total_bytes} bytes** in **${total_lines} lines**; **${kept_lines} of them are shown"
  echo "> above, verbatim** (${kept_bytes} bytes). The elided lines are exactly two declared"
  echo "> classes, and nothing else:"
  echo ">"
  echo "> - **routine per-ref progress** — ${progress_lines} line(s), ${progress_bytes} byte(s):"
  echo ">   \`Downloading <ref>…\` and \`charly: resolving <ref> (N resolved, M queued)\` — one line"
  echo ">   per ref from each of the two emitters. Every ref they name is already listed above"
  echo ">   — by the pins advanced and by the changed-file list — so they carry no information"
  echo ">   the body does not publish."
  echo "> - **the generator's own artifact-path list** — ${artifact_lines} line(s),"
  echo ">   ${artifact_bytes} byte(s): every artifact the generator wrote. Every artifact that"
  echo ">   CHANGED is named in the changed-file list above, and the full list grows with the"
  echo ">   corpus, so it must not be able to push this body over GitHub's cap."
  echo ">"
  echo "> Every other line of the log is shown **verbatim** — any warning and any error among"
  echo "> them included: a warning is what this section exists to surface, and nothing outside"
  echo "> the two classes above is ever elided. The complete, unelided log is this run's step"
  echo "> log for *Regenerate the corpus at the new pins*."
} > "$NOTICE"

# The counts go to stderr as well, so the run's log carries the measurement even when
# the body is not read.
printf 'refresh-elide: %s bytes / %s lines in; %s bytes / %s lines shown; elided %s progress line(s) (%s bytes) and %s artifact-path line(s) (%s bytes)\n' \
  "$total_bytes" "$total_lines" "$kept_bytes" "$kept_lines" \
  "$progress_lines" "$progress_bytes" "$artifact_lines" "$artifact_bytes" >&2
