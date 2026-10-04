#!/usr/bin/env bash
# coord.sh — post ONE verb-labelled coordination comment (or claim) on a GitHub
# issue or PR, carrying the canonical two-line agent footer.
#
# WHY THIS EXISTS
#   `AGENTS.md` ("Agent identity & comment coordination", extends rule 9) defines a
#   comment grammar every agent must use the moment two or more agents work the same
#   issue/PR, or the scope is a blocking dependency:
#     * the FIRST non-blank line is exactly ONE label from the closed set
#       CLAIM · OWNING · HANDING OVER · TAKING OVER · BLOCKS · UNBLOCKS · STATUS · RESOLVED;
#     * the comment ENDS with two italic identity lines in the canonical order —
#       `Agent:` FIRST, `Assisted-by:` LAST (the order the pr-validator accepts).
#   Hand-writing that footer is exactly where agents drift (wrong order, a missing
#   session, an invented confidence tier). This script is the SINGLE generic
#   implementation of that grammar (R3): used by humans, by agents, and by the
#   opencode `coord_comment` tool in `.opencode/plugins/coord.ts`.
#
# FULLY GENERIC: no org, repo, session, or date is baked in — everything is args
#   or the COORD_* environment.
#
# USAGE
#   coord.sh <VERB> <owner/repo#num> [--body TEXT | --body-file FILE] [OPTIONS]
#
#   <VERB>        one of CLAIM OWNING HANDING OVER TAKING OVER BLOCKS UNBLOCKS
#                 STATUS RESOLVED. Case-insensitive; `-`, `_` and runs of spaces
#                 all normalise to the canonical spaced upper-case label.
#
#                 <VERB> IS ONE ARGUMENT. Write a two-word verb with `_` or `-`
#                 (one word, so no quoting is needed), or QUOTE the spaced form.
#                 Left unquoted, the shell splits it and `OVER` is read as the
#                 TARGET, so the repo ref lands as an unexpected argument:
#                   coord.sh taking_over    owner/repo#123    # OK
#                   coord.sh "TAKING OVER"  owner/repo#123    # OK
#                   coord.sh TAKING OVER    owner/repo#123    # FAILS, see below
#   <owner/repo#num>
#                 also accepts `owner/repo/pull/num`, `owner/repo/issues/num`, and
#                 a full `https://github.com/owner/repo/(pull|issues)/num` URL.
#                 Works on a PR or an issue alike (a PR is an issue to the API).
#
# OPTIONS
#   --body TEXT          comment body (GitHub Markdown). May be omitted (verb-only).
#   --body-file FILE     read the body from FILE instead.
#   --agent SLUG         the work slug for the `Agent:` line.       env COORD_AGENT
#   --session SES_ID     this session's id (the `Agent:` line).     env COORD_SESSION
#   --harness NAME       e.g. OpenCode.                             env COORD_HARNESS
#   --model NAME         the provider model name.                   env COORD_MODEL
#   --confidence TIER    one of:
#                          fully tested and validated
#                          analysed on a live system
#                          documentation reviewed
#                          syntax check only
#                          theoretical suggestion
#                                                                   env COORD_CONFIDENCE
#   --assign             also assign the posting account (the CLAIM action).
#   --dry-run, --print   print the comment, do NOT call GitHub.
#   -h, --help           print this help and exit 0.
#
# OUTPUT  the posted comment URL (or, with --dry-run, the comment itself).
# EXIT    0 posted/previewed · 2 usage error · 3 missing gh/jq · 5 GitHub/gh error.
set -euo pipefail

PROG=${0##*/}

VERBS=(CLAIM OWNING "HANDING OVER" "TAKING OVER" BLOCKS UNBLOCKS STATUS RESOLVED)
TIERS=(
  "fully tested and validated"
  "analysed on a live system"
  "documentation reviewed"
  "syntax check only"
  "theoretical suggestion"
)

usage() { sed -n '/^# USAGE/,/^# EXIT/p' "$0" | sed 's/^# \{0,1\}//'; }
die() { printf '%s: %s\n' "$PROG" "$*" >&2; exit 2; }
miss() { printf '%s: %s\n' "$PROG" "$*" >&2; exit 3; }
fail() { printf '%s: %s\n' "$PROG" "$*" >&2; exit 5; }
need() { [ "$#" -ge 2 ] || die "option $1 needs a value"; }
have() { command -v "$1" >/dev/null 2>&1; }
in_list() { local needle=$1; shift; local x; for x in "$@"; do [ "$x" = "$needle" ] && return 0; done; return 1; }

verb= target= body= body_file=
agent=${COORD_AGENT:-} session=${COORD_SESSION:-}
harness=${COORD_HARNESS:-} model=${COORD_MODEL:-}
confidence=${COORD_CONFIDENCE:-}
assign=0 dry=0 literal=0

positional() {
  if [ -z "$verb" ]; then verb=$1
  elif [ -z "$target" ]; then target=$1
  else
    # A two-word verb written with a SPACE and left unquoted lands here: the verb
    # slot took its first word, the target slot took the second (`OVER`), and the
    # repo ref is the leftover argument. Name THAT — the old message blamed the
    # repo ref the caller actually typed, which points at the wrong half of the
    # command line and sends them looking for a quoting bug in the target.
    local up w
    up=$(printf '%s' "$verb" | tr '[:lower:]' '[:upper:]' | tr '_-' '  ' | tr -s ' ')
    for w in "${VERBS[@]}"; do
      case "$w" in
        *" "*) [ "${w%% *}" = "$up" ] && \
          die "unexpected argument: $1 — '$verb' begins the two-word verb '$w', which is ONE argument: coord.sh \"$w\" <owner/repo#num> (or write it as ${w%% *}_${w#* }, which needs no quoting)" ;;
      esac
    done
    die "unexpected argument: $1"
  fi
}

while [ "$#" -gt 0 ]; do
  if [ "$literal" = 1 ]; then
    positional "$1"; shift; continue
  fi
  case "$1" in
    -h | --help) usage; exit 0 ;;
    --body) need "$@"; body=$2; shift 2 ;;
    --body-file) need "$@"; body_file=$2; shift 2 ;;
    --agent) need "$@"; agent=$2; shift 2 ;;
    --session) need "$@"; session=$2; shift 2 ;;
    --harness) need "$@"; harness=$2; shift 2 ;;
    --model) need "$@"; model=$2; shift 2 ;;
    --confidence) need "$@"; confidence=$2; shift 2 ;;
    --assign) assign=1; shift ;;
    --dry-run | --print) dry=1; shift ;;
    --) literal=1; shift ;;
    -*) die "unknown option: $1 (try --help)" ;;
    *) positional "$1"; shift ;;
  esac
done

[ -n "$verb" ] || { usage >&2; exit 2; }
[ -n "$target" ] || die "missing <owner/repo#num> (try --help)"

# --- canonicalise + validate the verb (the closed set) ----------------------
canon=$(printf '%s' "$verb" | tr '[:lower:]' '[:upper:]' | tr '_-' '  ' | tr -s ' ')
canon=${canon# }
canon=${canon% }
in_list "$canon" "${VERBS[@]}" || die "invalid verb '$verb' — one of: ${VERBS[*]}"

# --- validate the confidence tier -------------------------------------------
[ -n "$confidence" ] || die "missing --confidence (or COORD_CONFIDENCE); one of: ${TIERS[*]}"
in_list "$confidence" "${TIERS[@]}" || die "invalid --confidence '$confidence' — one of: ${TIERS[*]}"

# --- require the full identity (the footer is not optional) -----------------
for pair in "agent:$agent" "session:$session" "harness:$harness" "model:$model"; do
  key=${pair%%:*}
  val=${pair#*:}
  [ -n "$val" ] || die "missing --$key (or COORD_$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]'))"
done

# --- body (optional; --body-file wins) --------------------------------------
if [ -n "$body_file" ]; then
  [ -f "$body_file" ] || die "no such --body-file: $body_file"
  body=$(cat "$body_file")
fi

# --- parse the target -------------------------------------------------------
item=${target#https://github.com/}
if [[ $item =~ ^([^/]+)/([^/#]+)#([0-9]+)$ ]]; then
  owner=${BASH_REMATCH[1]} repo=${BASH_REMATCH[2]} num=${BASH_REMATCH[3]}
elif [[ $item =~ ^([^/]+)/([^/]+)/(pull|issues)/([0-9]+)$ ]]; then
  owner=${BASH_REMATCH[1]} repo=${BASH_REMATCH[2]} num=${BASH_REMATCH[4]}
else
  die "unrecognised target '$target' — want owner/repo#num or owner/repo/pull/num"
fi

# --- build the comment (canonical order: Agent FIRST, Assisted-by LAST) -----
footer_agent="*Agent: \`$agent\` · session \`$session\`*"
footer_assisted="*Assisted-by: $harness $model ($confidence)*"
if [ -n "$body" ]; then
  comment=$(printf '%s\n\n%s\n\n%s\n%s' "$canon" "$body" "$footer_agent" "$footer_assisted")
else
  comment=$(printf '%s\n\n%s\n%s' "$canon" "$footer_agent" "$footer_assisted")
fi

if [ "$dry" = 1 ]; then
  printf '%s\n' "$comment"
  exit 0
fi

# --- post ---------------------------------------------------------------
have gh || miss "gh not found on PATH"
have jq || miss "jq not found on PATH"

payload=$(mktemp)
trap 'rm -f "$payload"' EXIT
printf '%s' "$comment" | jq -Rs '{body: .}' > "$payload"

if ! url=$(gh api --method POST "repos/$owner/$repo/issues/$num/comments" --input "$payload" --jq '.html_url'); then
  fail "gh api failed posting the comment on $owner/$repo#$num"
fi

if [ "$assign" = 1 ]; then
  login=$(gh api user --jq .login)
  gh api --method POST "repos/$owner/$repo/issues/$num/assignees" -f "assignees[]=$login" >/dev/null
fi

printf '%s\n' "$url"
