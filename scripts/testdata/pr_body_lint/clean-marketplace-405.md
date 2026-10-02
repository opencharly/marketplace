## Summary

`scripts/pr_state_watch.sh` reported a **stale** BLOCK as terminal right after a re-run of the required validator was requested. It exited 2 while the re-run (which then PASSED) had not created its check run yet.

**The defect, measured on opencharly/docs#142:**
- The watcher was armed after the REST re-run of run `36933867704` and exited at once with `BLOCKED verdict BLOCK at head 041625863`.
- Attempt 2 started at 22:20:17Z, and its check run began at 22:20:21Z, both after the watcher had already exited.
- That attempt passed, and the PR merged.

**Mechanism:**
- The classifier reads only `commits/<head>/check-runs`. That view shows the newest check run per name, which until the re-run's job starts is the previous attempt's FAILURE.
- A queued re-run has no check run, so nothing marked it as in flight.

**Fix:**
- Before treating BLOCKED/POISON as terminal, the script reads `actions/runs?head_sha=<head>`.
- If a run of the required workflow is not `completed`, the verdict is PENDING and the watcher keeps polling.
- The workflow file defaults to `org-wide-pr-validator-required.yml` and can be overridden with `PR_STATE_REQUIRED_WORKFLOW`, mirroring `PR_STATE_REQUIRED_CHECK`.
- An `actions/runs` failure or rate limit takes the same exit-5 / FATAL paths as the existing reads.

The POISON branch's remedy text and the header comment pointed at the retired per-repo `.github/workflows/pr-validator.yml` dedupe. They now name the REST re-run (`gh api -X POST repos/<o>/<r>/actions/runs/<id>/rerun`) or a fresh commit; why `gh run rerun` can't be used is in opencharly/layer-charly-internals#71.

Closes #403.

## How tested

Head `95e35f8942ccbaa98544bc23ee6e2628e0652ac9`:

```
 scripts/pr_state_watch.sh    | 30 ++++++++++++++++++++++++++----
 scripts/watch_family_test.sh | 29 +++++++++++++++++++++++++++++
 2 files changed, 55 insertions(+), 4 deletions(-)
```

**New regression test `8g` in `watch_family_test.sh`.** The `gh` stub now answers `commits/<sha>/check-runs` and `actions/runs?head_sha=` from fixtures. The test has two cases:
- a FAILURE check run plus a **queued** attempt-2 run of the required workflow must **not** exit 2;
- the **control**: the same FAILURE with nothing in flight must still exit 2.

The suite with the fix:

```
$ bash scripts/watch_family_test.sh
ok   - pr_state_watch: a queued re-run keeps a stale FAILURE non-terminal (rc=124)
ok   - pr_state_watch: reports the queued re-run as WAIT/running
ok   - pr_state_watch: the actions/runs in-flight probe is exercised
ok   - pr_state_watch: a FAILURE with nothing in flight is still BLOCKED (exit 2)
PASS — all watcher-family assertions passed
suite exit=0
```

`rc=124` is the test's own `timeout`: the watcher kept polling (WAIT) instead of exiting 2.

The same suite with `pr_state_watch.sh` reverted to `origin/main` (the test fails without the fix; the control holds both ways):

```
FAIL - pr_state_watch queued re-run
FAIL - pr_state_watch queued re-run report
FAIL - in-flight probe exercised
ok   - pr_state_watch: a FAILURE with nothing in flight is still BLOCKED (exit 2)
FAIL — 3 assertion(s) failed
suite WITHOUT fix exit=1
```

**The changed path, executed live** against the real API (read-only) on an open PR whose newest verdict is a FAILURE, opencharly/charly#749. The full `bash -x` log is filtered with the `grep` shown:

```
$ gh api "repos/opencharly/charly/actions/runs?head_sha=8139626c8c8cc7427754c042b232181a032392a4&per_page=100" --jq '[.workflow_runs[]|select(.path|endswith("org-wide-pr-validator-required.yml"))|"\(.id) \(.status) \(.conclusion) attempt=\(.run_attempt)"]|.[]'
36942075094 completed failure attempt=1
$ bash -x scripts/pr_state_watch.sh opencharly/charly 749 --interval 60 --timeout 120 > psw-live.log 2>&1; echo "exit=$?"
exit=2
$ grep -E "^\+\+? (gh api .repos/opencharly/charly/actions/runs|inflight=|verdict=)|^[0-9:]+  opencharly" psw-live.log
+ verdict=BLOCKED
++ gh api 'repos/opencharly/charly/actions/runs?head_sha=8139626c8c8cc7427754c042b232181a032392a4&per_page=100'
+ inflight=0
02:49:55  opencharly/charly#749  BLOCKED  verdict BLOCK at head 8139626c8 (mergeState=BLOCKED)
```

With nothing in flight, the real-data verdict is unchanged: BLOCKED, exit 2. The queued branch is pinned by `8g`, because no live re-run was queued to observe.

`bash -n` passes on both files. The repo's corpus regeneration (`charly marketplace generate`) is not affected, because `scripts/` is hand-authored, not projected. It also cannot run today: no charly `main` binary loads a `charly.yml` until the schema-versioning-removal wave (opencharly/charly#749) lands, the condition tracked in #371.

## Rulebook compliance

- **R0 Skills first:** `/charly-internals:git-workflow` and `/charly-internals:root-cause-analyzer` were loaded.
- **R1 RCA:** the race was root-caused to the check-runs-only classification (the R1 analysis on #403, from the docs#142 timeline).
- **R2 Finish the cutover:** both terminal FAILURE branches (BLOCKED and POISON) consult the in-flight probe, and the stale remedy text is fixed in the message and the header.
- **R3 No duplication:** the probe reuses the script's existing rate-limit and error helpers (`watch_is_rate_limited`, `watch_fatal_rate_limit`).
- **R4 No workarounds:** no sleeps or retries are added; the classifier reads the authoritative run state.
- **R4a Product first:** N/A — no charly command changes.
- **R5 Delete legacy:** the retired per-repo `pr-validator.yml` dedupe advice is removed.
- **R6 Git safety:** a feat branch, one commit, one push, no force push.
- **R7 Prove behaviour:** `8g` fails without the fix (3 assertions) and passes with it; the control passes both ways.
- **R7a Live or skip:** the changed path ran against the real GitHub API; the stub covers only the unobservable queued window.
- **R8 Preserve emitted artifacts:** N/A — scripts emit no artifact.
- **R9 Binary equals source:** N/A — no binary.
- **R10 Fresh disposable proof:** N/A as a bed (repository tooling; there is no bed for `scripts/`). The family suite and the live run are the proof.
- **Rule 9 (umbrella):** the open marketplace PRs (#370, #398) don't touch `scripts/`; the issue is claimed by `readme-truth`.

## Change classification

- **Change class:** repository tooling (a watcher script and its test).
- **Verification gate:** `watch_family_test.sh`, with and without the fix, plus a live read-only run on a real BLOCKED PR.
- **Attribution tier:** analysed on a live system.

*Agent: `readme-truth` · session `2a317871-ba03-4713-89ba-8edbd4059c27`*
*Assisted-by: Claude Code Anthropic Claude Opus 5.5 (analysed on a live system)*
