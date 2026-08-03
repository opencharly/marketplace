## B1 — the two-step branch-per-change loop

**Step 1 — Author** (opens the PR; NEVER merges it):

```bash
# sync-before-start (see B4): branch off up-to-date main
git fetch origin --prune --tags
git switch main && git merge --ff-only origin/main
git switch -c feat/<slug>            # slug = kebab summary of the change

# ... implement the whole cutover; run beds freely throughout to VERIFY
#     (Risk Driven Development: prove high-risk assumptions on a bed first) ...

# on R10 PASS, open the PR (do NOT merge):
# write the cutover narrative to CHANGELOG/<placeholder>.md — a PLACEHOLDER CalVer
#   (any valid YYYY.DDD.HHMM; the evaluator OVERWRITES it with the merge-time VER).
git add <only the cutover's files> CHANGELOG/<placeholder>.md
git commit -m "<conventional commit>" \
  -m "Assisted-by: <Harness> <Provider Full Model Name> (<confidence>)"
git push origin feat/<slug>                       # feat push — allowed by the gate
gh pr create --base main --head feat/<slug> \     # fill the PR template completely (single org source: opencharly/.github/.github/PULL_REQUEST_TEMPLATE.md — no per-repo copy)
  --title "<subject>" \
  --body-file <pr-body.md>
# STOP. Do NOT merge your own PR. Hand off to a FRESH pr-validator (Step 2).
```

**Step 2 — Fresh evaluator** (`plugins/internals/agents/pr-validator.md`, spawned
with NEW context): it independently re-validates the PR vs R0–R10 + the relevant
skills, posts `charly/pr-validator` on the head SHA, and ONLY on PASS
generates the merge-time CalVer, rewrites the version surfaces on `feat/` (the
`CHANGELOG` rename + any schema bump), re-posts the status on the new head,
`gh pr merge --squash --delete-branch`, and tags. Its inputs include the PR's
FULL comment thread, per the pr-validator spec's comment-intake rule — every
comment is investigated independently and considered in the verdict, never
granted or denied authority merely by existing (see
`plugins/internals/agents/pr-validator.md` "Comment intake", never restated
here). The author pastes the evaluator's verbatim verdict + what it
merged/tagged (paste-proof survives delegation). On FAIL the PR stays OPEN
and is **UPDATED IN PLACE** → the author R1-RCAs, fixes in the same tree,
APPENDS a fix commit, and pushes it fast-forward (status resets) → the
evaluator re-runs. **Never close a PR and open a replacement to carry a fix.**

Because the merge is a SQUASH and `main` is protected linear, `main` gains exactly
ONE commit per cutover — the author's change, any review-round fix commits, and the
version stamp, folded together.

### Concurrent landings — N open cutovers do NOT serialize beyond git itself

With several cutovers in flight (a multi-cutover program), **only two things are
inherently ordered: the merge instants (git — seconds each) and any real dependency
DAG between cutovers.** Everything else runs CONCURRENTLY, and no doc may mandate
more serialization than that without a technical reason:

- **Implementation** — one git worktree per cutover, per-worktree binaries for
  verification (`/charly-internals:agents` "Per-worktree binaries", proven), bed
  gates from multiple branches overlapping under the shared hardware ceiling.
- **Validation** — fresh `pr-validator`s run CONCURRENTLY across all ready PRs
  (each is an independent context; nothing couples them before the merge instant).
- **After each merge** — every still-open PR goes `BEHIND` (all three repos set
  `strict: true` require-up-to-date — KEPT deliberately: one shared Go package with
  no CI on `main` means merging a stale-base green PR opens a semantic-conflict
  blind spot; that is the technical reason, not doctrine). Recover with
  `gh pr update-branch` (never force-push), then a **risk-proportional DELTA
  RE-GATE** re-posts the per-commit status: compute the overlap
  `git diff --name-only <old-main>..main` ∩ the branch's touched files —
  EMPTY → rebuild + `go test ./...` + `golangci-lint run` + re-post (minutes);
  NON-EMPTY → additionally re-run the cutover's primary beds; a full roster re-run
  only when the overlap hits the cutover's risky paths. The ORIGINAL full R10
  against the branch's final code remains mandatory before the FIRST validation —
  the delta re-gate covers only the mechanical update-branch merge on top of an
  already-R10'd `main`.

**Gitlink ANCESTOR bump → `gh pr update-branch` flags CONFLICTING (recover
locally).** When the just-merged delta and a still-open PR both bump the SAME
submodule gitlink and one bump is an ANCESTOR of the other, GitHub's
`gh pr update-branch` does NOT auto-resolve it — it conservatively reports the PR
CONFLICTING instead of fast-forwarding the gitlink to the descendant. The
compliant recovery is the update-branch EQUIVALENT done LOCALLY: in the feat
worktree, `git merge origin/main` (git resolves the gitlink to the descendant
commit automatically), then push the result FAST-FORWARD. A MERGE, never a rebase;
no force-push — the exact constraints `gh pr update-branch` itself honors. **Then
VERIFY the merge resolved the gitlink FORWARD** — `git ls-tree HEAD <sub>` (or
`git diff --submodule=short origin/main..HEAD`) must show the DESCENDANT commit, never
the ancestor: a recovery that silently re-pins the OLDER submodule bump is the exact
regression this class produces (a sibling merge advances `main` mid-validation, then a
naive recovery reverts the gitlink to the older pointer). Only after the descendant-wins
check re-post the status and delta-re-gate as above.

**Multi-committer main advances — out-of-tree PRs from other committers.** The
orchestrator is NOT the sole source of `main` advances: another committer (a human
maintainer, a parallel session, an outside contributor via the fork+PR path) may
land an unrelated PR on `main` WHILE this plan's `feat/` branches are in flight. The
discipline above is main-advance-agnostic and applies to ANY merge regardless of
source — treat an out-of-tree merge IDENTICALLY to an internal one:
- **Detect proactively, not only reactively.** Fetch `origin/main` (and each
  submodule's `main`) before opening EACH PR and before each merge — do not rely
  solely on the orchestrator's own-merge broadcast. A `feat/` branch that goes
  `BEHIND` from an external merge is recovered exactly as above (`gh pr
  update-branch`, delta re-gate, forward-gitlink verify). `strict: true` is KEPT
  precisely for this: a stale-base green PR merged over an external advance opens a
  semantic-conflict blind spot, so the delta re-gate's overlap check
  (`git diff --name-only <old-main>..main` ∩ branch-files) is what makes an
  out-of-tree merge safe — EMPTY overlap → re-post; NON-EMPTY → re-run the primary
  beds. A teammate pushing while `BEHIND` an external merge updates its branch and
  reports the overlap for the orchestrator's delta-re-gate call.
- **Divergent-lineage submodule bump (not ancestor/descendant).** The
  descendant-wins rule above covers the common case (the external merge bumped a
  submodule to a DESCENDANT of our feat's pin). If an out-of-tree merge bumps a
  submodule to a commit NOT in our feat's gitlink ancestry (a divergent lineage — a
  different branch merged, or a revert), do NOT blindly descendant-wins:
  re-resolve the feat to the new `main`'s submodule commit, RE-RDD the affected
  cross-repo composition (the composition-at-latest-versions high-risk unknown —
  prove it on a `disposable: true` bed), and only then re-post status. A naive
  update-branch that re-pins the OLDER or divergent gitlink is the exact regression.
- **The rebase broadcast covers external advances too.** When the orchestrator
  detects ANY `main` advance — internal OR external — it broadcasts the rebase to
  every in-flight teammate and re-runs the per-merge delta re-gate over the
  external delta; the orchestrator OWNS external-advance detection (it is the one
  actor that fetches `origin/main` across all lanes).

### The cross-repo WIP landing sequence — commit-to-rebase without shipping unproven code

A multi-repo cutover hits a genuine tension: the WIP must be COMMITTED before a
rebase onto freshly-advanced mains (a submodule-spanning working tree makes
`git stash` unsafe — a gitlink stash can silently drop a submodule's in-progress
pointer, R6), yet a runtime-class commit gate demands LIVE proof of the FINAL code,
which does not exist until AFTER the rebase. Resolve it by committing at the tier
that is HONEST at each stage on an UNPUSHED branch, then re-stamping the tier once
the final code is proven — never by shipping anything pre-bed:

- **(a) Freeze + exploratory roster.** Freeze the WIP and run the EXPLORATORY bed
  roster against that frozen state (the `disposable: true` beds whose kinds match
  the change).
- **(b) Commit LOCALLY at the then-honest tier — do NOT push.** With the live
  runner having actually run and its output pasted, the honest tier is
  `analysed on a live system` (the project rulebook "AI Attribution"). Commit at that tier to
  create the rebase-able base. The commit stays LOCAL.
- **(c) Rebase onto the current mains.** Bring the branch onto the just-advanced
  `origin/main` of every repo, and REGENERATE every generated file from the merged
  sources (`task cue:gen`, codegen) — never hand-merge a generated artifact
  (generated-artifact drift is an R1 incident).
- **(d) Re-run the gates, re-freeze.** `go test` / `golangci-lint` / build /
  `charly box validate` on the rebased tree, then freeze again.
- **(e) FINAL roster on the rebased FINAL code.** The R10 acceptance roster runs on
  the rebased, transitional-free code — the state that will actually ship.
- **(f) Amend/reword to the EARNED tier, then push + open the PRs.** Re-stamp the
  commit's attribution tier to what the FINAL roster earned (`fully tested and
  validated` on a clean full pass). This amend is legal ONLY because the branch is
  UNPUSHED — the "amend only before the first push" invariant above. THEN push
  `feat/<slug>` and open the PRs (B1 step 1; multi-repo order = B2).

Nothing pre-bed ever ships, and every intermediate commit passes the PreToolUse
tier gate TRUTHFULLY at the stage it was made — the tier only ever moves UP, to
match proof that now exists.

## B4 — sync to upstream + prune (per repo: main, sdk, plugins, box/*, pkg/*)

- **Sync-before-start.** `git fetch origin --prune --tags`; ff local `main` to
  `origin/main`. Never force-reset a diverged local `main` — if it cannot
  fast-forward, STOP + run `/charly-internals:root-cause-analyzer`. (Local `main`
  now only ever fast-forwards to what agent-validated PRs merged remotely.)
- **Switch-to-upstream check.** Before opening the PR, confirm `origin` is the
  canonical upstream and the PR targets the upstream `main` (not a stale
  fork/branch). On mismatch, STOP and surface it.
- **Prune merged branches.** `feat/` is deleted at merge (`--delete-branch` +
  `delete_branch_on_merge`). Sweep leftovers: `git branch --merged main` → delete
  local; `git fetch --prune` drops remote-tracking refs deleted upstream. **Only
  ever delete branches confirmed `--merged`**; never `-D` an unmerged/abandoned
  branch without operator confirmation — it may hold unlanded work.
- **Worktree hygiene.** `git worktree list` to inventory; `git worktree prune` to
  clear stale admin entries. Remove an agent `isolation: worktree` after its change
  lands. Before reusing a long-lived worktree, ff its base to `origin/main`. A linked
  superproject worktree shares superproject objects but not submodule objects:
  initialize only the submodules the cutover needs, and initialize each from the
  common Git directory's matching `modules/<path>` reference so its clone records a
  Git alternate instead of duplicating object packs. Verify the alternate and the
  exact gitlink before use; never compensate with `/tmp`, a user cache, or an
  unrelated recursive submodule checkout.

