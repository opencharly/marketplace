#!/usr/bin/env bash
# Regression proof at the real GitHub boundary. PR465 retains the incident
# response: a provider HTTP 429 in a comment is not a GitHub quota failure.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/_watch_common.sh"

if ! gh auth status; then
  echo 'SKIPPED: live watcher regression requires authenticated GitHub access.' >&2
  exit 3
fi

comments="$(gh api --paginate repos/opencharly/opencharly/issues/465/comments)"
if ! jq -se 'add | any(.[]; .id == 6106838448 and (.body | contains("HTTP 429")))' \
    <<<"$comments" >/dev/null; then
  echo 'FAIL: the real incident comment no longer supplies the regression precondition.' >&2
  exit 1
fi

if watch_is_rate_limited "$comments" 0; then
  echo 'FAIL: successful GitHub comments were classified as a GitHub quota failure.' >&2
  exit 1
fi

echo 'PASS: real PR465 comments retain the provider HTTP 429 and are not GitHub throttling.'
