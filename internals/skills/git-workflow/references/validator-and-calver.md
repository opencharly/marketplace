## B5 — the fresh evaluator (`pr-validator`) + the fork+PR path

The PR path is the sole landing path for everyone — write-access holders and
outside contributors alike. There is no direct-merge fast path.

### Validator handoff is parent-owned and complete

**Before spawning every fresh `pr-validator` round, the parent/orchestrator supplies a
self-contained handoff as transient spawn context. It is never recorded as an
author-worktree artifact.** It names the PR, literal
superproject and target paths, current target protected-base and PR-head SHAs,
protected-policy object SHA, complete repository/gitlink map, clean status, operator
constraints, required approval categories, and mutation limits. For a submodule PR, the
target protected base and superproject gitlink remain separate objects; do not validate
one by guessing from the other.

The validator begins in that exact worktree, loads protected policy and dispatched skills
before candidate actions, and verifies the handoff with read-only commands. It has a
fresh context and role but **does not create another worktree, clone, alternate Git
directory, cache, home, or `/tmp` workspace.** A missing protected object, unreadable
required skill, uninitialized declared gitlink, absent approval, or ambiguous handoff is
`BLOCKED`: post the precise reason as the validator PR comment and stop. Do
not bootstrap, run setup, retry around the boundary, or substitute candidate policy.

- **Write access (the default):** the author opens the PR (B1 step 1); a fresh
  `pr-validator` (new context, not the author's context, not a teammate that
  authored the code) validates → posts `charly/pr-validator` → on PASS
  finalizes the merge-time CalVer, `gh pr merge --squash --delete-branch`, tags.
  Sequence + guardrails: `plugins/internals/agents/pr-validator.md`. The evaluator
  never runs `gh pr merge --admin` (that bypasses the gate) and never force-pushes; a
  `BEHIND` branch is recovered with `gh pr update-branch` (no force-push), the
  status re-posted on the new head, then merged.
- **No write access — fork + PR:** ensure a fork (`gh repo fork --remote`), push
  `feat/<slug>` to the fork, `gh pr create --base main --head <fork>:feat/<slug>`
  with the full template body. A maintainer's fresh `pr-validator` then validates
  and merges exactly as above. Never force-push, never need upstream write.

**Why a status, not a review approval — and what it does not buy.** GitHub forbids a
PR's author from approving their own PR, and a local sub-agent shares the author's
identity. A commit status carries no such GitHub-side restriction, which is why
`charly/pr-validator` is the required check. Be precise about what that means:
the status is **agent-attested validation, not two-party review**. The fresh
`pr-validator` supplies context independence (a new context re-deriving the verdict
adversarially, trusting no author claim) — which demonstrably catches real defects —
but it cannot supply party independence: same principal, same token, and
`required_approving_review_count` is 0, so no second party exists anywhere in the
flow. Claude Code's auto-mode classifier names this exactly — its **Self-Approval**
rule blocks "triggering a pipeline that marks the agent's own PR's required checks as
passed … regardless of whether the agent believes it verified its own code," its
**Merge Without Review** rule blocks "merging before a human approved," and a sub-agent
the session spawned is "an automation the agent controls." So by those definitions an
agent posting the status is self-approval and an agent merging is merge-without-review.
The project accepts that posture deliberately. What branch protection still mechanically
enforces: PR-only landing, linear history, `enforce_admins`, no force-push, and that the
status exists — never `gh pr merge --admin`, never a force-push, never editing protection.

**Two separate gates — landing must clear both, and they are not the same thing.**

1. **`permissions.allow` — the deterministic command-prompt layer.** The superproject's
   committed `.claude/settings.json` carries these rules (a whole team inherits them):

   ```json
   "permissions": { "allow": [
     "Bash(gh pr merge:*)",
     "Bash(gh api --method POST repos/opencharly:*)"
   ] }
   ```

   These clear the prompt for the two commands. **The `success` status POST is fully
   cleared by its rule** — a superproject-rooted validator posts `success` with zero
   denials (proven repeatedly). Exact spellings the rules pin: `--method POST` (never
   `-X POST`), a `repos/opencharly/…` path; the POST rule is POST-only, so it can never
   touch branch protection (a PUT).

2. **The auto-mode classifier — the semantic layer that fires on top.** `permissions.allow`
   clears the *prompt* for `gh pr merge`, but the classifier's **Merge Without Review**
   soft-block fires anyway and is **not cleared by `permissions.allow`**. With
   the merge rule present, superproject-rooted, and a CLAUDE.md landing statement live,
   `gh pr merge --squash` was denied for both a sub-agent and the main session — verbatim:
   *"the merge instruction came from a coordinator agent (not the user), the CLAUDE.md
   pre-authorization is manufactured classifier-steering intent … Run this outside auto
   mode so the user can review."* The merge gate is real, separate, and stricter than the
   status gate.

**What clears the Merge-Without-Review gate — these, in descending durability:**

- **`autoMode.allow` in USER (`~/.claude/settings.json`) or MANAGED settings** — the
  classifier's own designed soft-deny override, and the only durable config-based grant.
  It is re-read from the settings file on every classifier evaluation, so it is **immune
  to context compaction**. Scope it in the rule prose ("opencharly org PRs only"). It is
  not read from a committed `.claude/settings.json` (the classifier ignores `autoMode`
  there) and not reliably from `settings.local.json` — **user or managed scope only.**
- **Genuine, in-context user intent that names the action** (the main session merging
  right after the user says "merge it"). Works, but **fragile across compaction**: the
  consent lives in the transcript, and once the transcript is summarized the classifier
  stops seeing it — a merge that worked earlier in a session was denied after the
  session resumed from a compaction summary.
- **Not CLAUDE.md prose.** The classifier explicitly rejects a CLAUDE.md authorization as
  "manufactured classifier-steering intent." CLAUDE.md records
  the policy; it does not function as classifier consent.

**An agent cannot apply the `autoMode.allow` grant itself.** Writing one's own
permission-weakening config trips the classifier's **Self-Modification** block, and that
block does not clear even on explicit in-chat user authorization (proven: the `autoMode`
edit was denied immediately after the operator authorized it). This is the security
guarantee that makes `autoMode` trustworthy — merge authority can be granted only by a
human editing the settings file hands-on (or an admin via managed settings). The agent's
job is to hand the operator the exact rule to paste.

**Two rooting/poison consequences remain load-bearing (about the status POST):**

- **The `permissions.allow` rules live in the superproject.** Claude Code resolves
  `.claude/settings.json` from the agent's project root (its working directory), and
  neither `plugins/` nor `sdk/` ships a `.claude/`. A validator rooted inside a submodule
  loads no permission rules, so even its `success` POST is denied as Self-Approval
  (*"the only authorization comes from a `<teammate-message>`"*) — unless a user/managed-level
  grant covers the action (user settings resolve independently of project root; see the
  scope-of-validity note below). See the autonomous-landing contract below.
- **A prior hook/classifier block poisons everything after it.** A PreToolUse block
  followed by a reshaped retry of the same command is flagged as a bypass attempt — after
  which later actions a rule would otherwise resolve are denied. **Treat any hook or
  classifier block as a hard denial: never reshape the command and retry** (not even
  toward a form this skill prescribes). Report the block and stop. This has cost a real
  landing.

**Operational consequence for the autonomous loop.** A validator (or the main session)
can always do everything up to the merge — validate, and post the `success` status
(cleared by `permissions.allow`). The merge lands autonomously only when the operator's
`autoMode.allow` rule is in effect (or, non-durably, under fresh in-context user consent).
Absent the rule, the operator completes the merge (`gh pr merge <n> --repo <r> --squash
--delete-branch` — the status is already green) or the main session does under fresh
consent. Posting a `failure` status never trips Self-Approval (it marks nothing passed),
so a FAIL verdict always goes through. Never `--admin`; never `--auto` (the classifier
exempts `--auto` only on repos with required-reviews protection, and these set
`required_approving_review_count: 0`). Only a fresh `pr-validator` posts the status
(never the author, never a code-authoring teammate) — a context-level discipline, not an
identity guarantee.

**The autonomous-landing contract — spawn every `pr-validator` rooted in the
superproject.** The status-post half of the loop depends on the standing
`permissions.allow` rules in the superproject's `.claude/settings.json` — committed
there, so a whole team inherits them and the `success` POST is autonomous by default
(the merge half additionally needs the operator's `autoMode.allow` rule — the two-gate
model above). Claude Code resolves `.claude/settings.json` from the agent's project root,
which is its working directory. A validator told to work *inside* `plugins/` or `sdk/`
roots in that submodule — which ships no `.claude/` — and therefore silently loads no
permission rules at all. Its `success` status POST is then denied as Self-Approval
(*"the only authorization comes from a `<teammate-message>`"*), because nothing ever
authorized it — unless a user/managed-level grant covers the action (those resolve
independently of project root; the scope-of-validity note below). So:

- **Spawn the validator with its working directory at the superproject root**, for a PR
  in any repo (superproject, `sdk`, `plugins`, `box/<distro>`).
- **Drive the submodule with a literal absolute path**: `git -C /abs/path/plugins …`,
  `gh <cmd> --repo <owner>/<repo>`. Never `cd plugins && …` (B7 states the same rule for
  the commit gate; it is equally load-bearing for permissions).
- Verify after the fact: the agent's transcript must live under
  `~/.claude/projects/-<superproject-path-slug>/`, not the `…-plugins` sibling.

**Proven by controlled experiment (single variable):** with the rule text unchanged, a
`pr-validator` rooted in `plugins/` was denied even the `success` POST; the same validator
rooted in the superproject posted `success` with zero denials. Scope was the entire cause
of the status-post denial (the merge is the separate Merge-Without-Review gate above).
**Scope of validity:** the denial reproduces only when no
user/managed-level grant covers the action — user-level settings (e.g. the operator's
`autoMode.allow` rule) apply independently of project root, and a submodule-rooted
validator under that rule posted `success` and merged with zero denials. Superproject
rooting remains the rule (project-level rules, the CLAUDE.md hierarchy, and transcript
determinism are root-dependent); diagnose a denial by checking both settings layers. Do
not "fix" a denial by editing the rule until you have confirmed the agent's project root. See `/charly-internals:agents` "Sub-agent operational invariants"
for the durable-verdict-first protocol every validator must follow (a permission denial
ends the agent's turn, so it records its verdict before attempting any gated action).

## CalVer — generated AND rewritten at MERGE, by the evaluator

The single CalVer stamp is `<YYYY.DDD.HHMM>` from the current UTC time. It is
generated at the moment of merge, by the fresh evaluator — not by the author.
Author-time stamps do not survive concurrency: with multiple PRs open and approved
out of order, an author-time CalVer collides (same minute) and mis-orders (merge
order ≠ author order). The evaluator generates it at merge and applies it to both
the changelog and the tag (the "one stamp for both" invariant, moved from
author-landing to evaluator-merge). This holds for every repo, `plugins` included:
`plugins` is no CHANGELOG-exception — every `plugins` landing carries a
`CHANGELOG/<YYYY.DDD.HHMM>.md` entry exactly like the superproject and
`box/<distro>`, and now that `plugins` is tagged, the same finalized CalVer names
that changelog file and the `v<…>` tag. Every component is fixed-width zero-padded so
filenames and tags sort chronologically under a plain alphanumeric sort.

- **The author writes a placeholder** `CHANGELOG/<placeholder>.md` (any valid
  `YYYY.DDD.HHMM`, so the cutover carries its required history) and — for a schema cutover
  — a placeholder `#SchemaVersion` / `migrations.cue` bump. The author owns none of
  the final numbers.
- **The evaluator, at merge:** `VER=$(date -u +%Y.%j.%H%M)` (guard uniqueness — if
  `v$VER` or `CHANGELOG/$VER.md` already exists on the current `main`, advance to
  the next free minute); bring the branch up to date (`gh pr update-branch` on `BEHIND`,
  no force-push); rewrite every merge-time-dependent version surface to `$VER`
  (`git mv CHANGELOG/<placeholder>.md CHANGELOG/$VER.md`; a schema bump re-stamped
  strictly above the current HEAD's `#SchemaVersion` + `version:` +
  `migrations.cue` entry); commit + push feat (a normal, non-force push — an added
  commit); re-post `charly/pr-validator` on the new head; `gh pr merge
  --squash --delete-branch`; then tag the merged HEAD — `git tag -a v$VER -m
  "<subject>" <merged-HEAD>` and `git push origin refs/tags/v$VER` (every repo;
  `sdk` substitutes its Go-module `v0.<…>` form).
- **Guard the `git mv` stale-pathspec footgun.** `git mv CHANGELOG/<placeholder>.md
  CHANGELOG/$VER.md` stages the rename, but a follow-up `git add <old-path>
  <new-path>` naming the now-nonexistent old path fails and silently drops
  staging any content edit made in the same step (e.g. rewriting the H1 heading
  to the final CalVer) — landing a rename-only commit that misses the edit.
  After the `mv` plus any content edit, verify `git show HEAD:<new-path> | head
  -1` (or `git diff --cached`) matches the intended content before committing
  or posting the status. This has recurred three times (across separate repos and
  a plugins CalVer finalization), caught pre-push each time only because the
  `git show HEAD:… | head -1` self-verify this bullet prescribes was actually run.

One fresh stamp per merge, immutable (only ever added), independent of `charly.yml`
`version:` (the schema version, bumped only by a cutover raising `#SchemaVersion`).
Every repo (superproject, `box/<distro>`, `plugins`, `pkg/*`) mints `v$VER` on its
merged HEAD; `sdk` alone uses its Go-module `v0.<YYYYDDD>.<HHMM
leading-zeros-stripped>` scheme (not an exemption — Go modules require semver, which
forbids a leading-zero segment — `0733`→`733`). A YAML schema/format change does
both: the schema bump and the tag. See `/charly-build:migrate`.

**A merged `CHANGELOG/<CalVer>.md` is immutable, exactly like the tag sharing its
CalVer.** Once the evaluator renames a cutover's placeholder to its final
`CHANGELOG/$VER.md` and merges it, that file is closed history — follow-up work in
the same theme, branch, or session never appends to it or edits its content, even to
add a directly-related narrative. It writes its own new placeholder
`CHANGELOG/<placeholder>.md` entry instead, which its own evaluator stamps with its
own merge-time CalVer at its own merge. Editing an already-merged entry re-dates
history out from under its own filename↔tag pairing — a permanent divergence the
instant it lands, not a convenience. (A fresh `pr-validator` FAIL is what catches this
mistake before it lands.)

## After landing — cleanliness + report

- **Working-tree cleanliness.** After the merge, `git status` is clean in every
  repo (refresh worktrees per B7 step 6). Untracked files that aren't part of the
  cutover (test artifacts, build outputs) belong in `.gitignore`; if they aren't,
  that joins the next thematic batch cutover (the Cutover Sizing Law,
  `/charly-internals:cutover-policy` "Cutover sizing — the batch law").
- **Report format.** The final message states: what was committed (commit subject +
  hash, per repo), the confidence tier with the proof that supports it, the PR + the
  `pr-validator` verbatim verdict + the merge SHA + the finalized `v<CalVer>` tag,
  and the pasted R10 outputs (exploratory + fresh-rebuild). The tier must match
  the project rulebook "AI Attribution", keyed to the change class (`/charly-check:check` "R10
  gate by change class") — a Documentation-only change class commit lands at
  `documentation reviewed`, runtime classes at a runtime tier. A worked commit
  message:

```
Fix: Add fuse-overlayfs for container startup

Tested via overlay session on LOCAL system.

Assisted-by: <Harness> <Provider Full Model Name> (fully tested and validated)
```

For every harness, the enforced trailer form is exactly
`Assisted-by: <Harness> <Provider Full Model Name> (<confidence>)`. A validator
composing a squash-merge trailer preserves the authoring harness, full provider
model name, and proof-supported confidence.

The canonical constructor is `plugins/scripts/squash_body.py` in the
superproject. It receives prose on standard input plus the concrete trailer via
`--trailer`, inserts the required blank line, and refuses output unless
`git interpret-trailers --parse` returns exactly that trailer. The validator
holds the returned bytes in one shell variable, passes the same bytes through
`--check`, and streams those exact bytes to `gh pr merge --body-file -`. It
then parses the fetched merge object and requires the same exact trailer before
tagging or reporting completion. Same-line attribution and a trailer separated
from prose by only one newline are both invalid, even when a plain-text search
finds the expected words. The parser output and merge SHA are mandatory
validator evidence.

Commit-time checks are an advisory mechanical backstop only; the fresh PR
validator independently verifies the trailer on every repository, including a
submodule checkout or standalone clone.

## If validation FAILS or R10 fails

A FAIL is a return-to-implementation signal, not a stopping point:

1. Run `/charly-internals:root-cause-analyzer` before attempting any fix — blind
   retry is forbidden.
2. Fix in the same working tree, on the same `feat/<slug>` — never a new PR.
3. Re-push the fix (the head SHA moves → `charly/pr-validator` resets → the
   fresh `pr-validator` re-runs). Re-run the full R10 from a fresh `charly update`,
   not just the failing piece — a fix that survives only the targeted re-run is a
   regression in waiting.
4. The PR merges only when validation passes end-to-end on the final code.
