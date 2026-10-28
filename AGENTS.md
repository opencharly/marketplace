# AGENTS.md — opencharly/marketplace

The published OpenCharly skill/marketplace corpus, consumed by the supported
agent harnesses — every plugin family flat at the repo root (`<family>/skills/…`,
`<family>/agents/…`, per-family manifests) plus one catalog per harness. The
corpus trees are **GENERATED** by `charly marketplace generate`; the ONE
generation input is the refs list `candy/charly-marketplace/charly.yml`.

Canonical files:

- `candy/charly-marketplace/charly.yml` — the refs list:
  `@github.com/opencharly/<candy-repo>:v<CalVer>` pins for every standalone candy
  repo that owns `skill:`/`hook:`/`marketplace:` entities. The ONE generation
  input — change a skill at its source, never the generated copy.
- `.github/workflows/` — the repo's generation workflow: the SOLE owner of
  generation; builds the pinned charly, regenerates the corpus, FAILS on any
  drift (including untracked files), runs the repo's own script tests, and
  publishes the catalog mirror; plus the
  daily refs refresh (advances every pin to its repo's newest tag IN THE PIN'S OWN
  SCHEME, regenerates, opens a `chore: refresh the refs list` PR) and REPORTS each
  recorded consumer's recorded pin's currency.
- `DISPATCHER.md` — the generated trigger → skill dispatcher (marker-spliced).
- `README.md`, `AGENTS.md`, `LICENSE`, `CHANGELOG/`, `scripts/`,
  `kimi-user-config.toml` — hand-authored; everything else carries a
  `DO-NOT-EDIT` header.

## Load these skills first (R0)

- `/charly-internals:marketplace` — how the corpus is generated, refreshed and
  consumed; the ownership split; the deploy drift gate; per-harness caching.
- `/charly-internals:skills` — skill authoring/maintenance: edit the OWNING
  repo's `skill:` entity, then regenerate; where content belongs.

## Build / validate / test

- `charly -C <marketplace-checkout> marketplace generate --root
  <marketplace-checkout> --out <marketplace-checkout>` — regenerate the corpus.
  On a clean tree this is a NO-OP; a diff means a refs/source change is in
  flight.
- The generator needs a charly binary that supports the marketplace config
  schema; an old binary fails with `config schema … is newer than this charly
  supports`.
- The merge gate is the **org-wide** `charly/pr-validator` (required check
  `validate / validate`, defined in `opencharly/.github`). The repo's generation
  workflow drift gate is what enforces that a refs bump ships its regenerated
  corpus in the same PR. The same workflow runs the repo's own script tests
  (`scripts/*_test.sh`, `scripts/pr_body_lint_test.py`) — a script that carries
  behaviour carries a test that runs in CI.
- The **consumer set** is the README's `## Consumers` table — ONE record. A
  consumer is added by adding a row; `scripts/consumer-currency.sh` reads that
  table, reads each consumer's recorded pin over the public API, and REPORTS
  whether it is behind this repo's merged main. It never fails: a consumer that
  is behind is an advance available now, in that consumer's own repo.

## Modify this repo

- Never hand-edit a generated file. A skill is authored as a `skill:` entity in
  its OWNING candy repo, projected here by `charly marketplace generate`, and the
  refs list is bumped in the same change. See `/charly-internals:marketplace` for
  the ownership split — the refs list IS the map: the owner of a published skill
  is the source whose body matches the published one byte for byte.
- Regenerate ONLY the projections of the sources you edited: a wholesale
  regeneration from a tree that lacks a pending source drags that projection
  backwards silently (audit `git diff --numstat` for files losing net lines).
- The catalog mirror and per-harness catalogs are generated too; keep hand edits
  to `README.md`, `scripts/`, `kimi-user-config.toml`, `CHANGELOG/`.

## Landing

- PR-only. Every change lands through a pull request; the org-required
  `charly/pr-validator` validates the diff and body and arms native auto-merge on
  PASS. Direct pushes to `main` are blocked.
- History lives in `CHANGELOG/` (written by `tag-on-merge` at merge time); the PR
  body IS the changelog.
- The authoritative rulebook is the umbrella `AGENTS.md` in
  `opencharly/opencharly` and `charly/AGENTS.md` in the charly repo. Do not
  restate its rules here.
