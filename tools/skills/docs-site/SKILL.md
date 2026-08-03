---
name: docs-site
description: |
  The Astro + Starlight toolchain candy for the opencharly.ai documentation site, and the
  check-docs R10 bed that builds and proves it.
  Use when working with the docs-site candy, the docs-site-app box, the check-docs bed, or when
  the documentation site fails to build.
---

# docs-site — build the opencharly.ai site inside a box

## Candy Properties

| Property | Value |
|---|---|
| Requires | `nodejs` |
| Packages | `git` (fedora section) |
| Builds into | `/srv/docs` (source), `/srv/docs/dist` (built site) |
| Consumed by | the `docs-site-app` box → the `check-docs` bed |

`docs-site` clones the published `opencharly/docs` repository, runs `npm ci` against its
committed lockfile, and runs the production Astro build. A build failure — a bad frontmatter
scalar, a Starlight config a version bump invalidated, a page whose markdown will not parse —
fails the **image build**, from the same input Cloudflare Pages builds, so the box catches it
before a deploy can.

## Why it clones instead of copying the submodule

The `docs/` submodule sits right beside `candy/docs-site/` in the working tree, and the candy
still cannot read it. Both escapes are closed by design:

- `copy:` rejects `..` — `copy: "../../docs/x" may not contain .. (no traversal)` at validate.
- There is **no** field for pointing a candy at another directory. (An older revision of
  `/charly-image:layer` documented a `directory:` field for exactly this; that field does not
  exist in `spec/schema/candy.cue`, in the generated spec types, or in the loader, and
  `charly box validate` rejects it as `field not allowed`.)

Cloning the published repo is the schema-legal path, and it tests the more useful thing: the
exact source Cloudflare builds.

**Ordering consequence.** The candy fetches an IMMUTABLE COMMIT, never a branch, so `DOCS_REF`
must be re-pinned to each new docs merge before this box — and the `check-docs` bed above it —
prove the new content. `task docs:pin` fails if it drifts from the `docs` gitlink.

A branch name here is a correctness bug, not a convenience: `var:` values are emitted as `ENV`
above the steps, so with `main` the clone layer's cache key never moves and the bed silently
rebuilds whatever commit that layer first captured. That shipped once, and four consecutive PASS
runs proved stale content before it was caught.

| Var | Default |
|---|---|
| `DOCS_REPO` | `https://github.com/opencharly/docs.git` |
| `DOCS_REF` | the `docs` gitlink sha — an immutable commit, **never a branch** (see above) |

## Verification

Every check is build-context, so `charly check box docs-site-app` proves the whole site builds
and has the right shape without deploying anything.

| Check | Asserts |
|---|---|
| `docs-site-node-present` | node reports a parseable major version |
| `docs-site-index-built` | `/srv/docs/dist/index.html` exists |
| `docs-site-cli-page` | a generated CLI reference page rendered |
| `docs-site-candy-acceptance-plan` | a candy page publishes its `plan:` as an acceptance spec |
| `docs-site-recipe-card` | a recipe card rendered with its cross-references rewritten to site links |
| `docs-site-runtime-plugin-page` | **the load-bearing one** — see below |
| `docs-site-provider-index` | the provider cross-index rendered |

### The load-bearing check

`docs-site-runtime-plugin-page` reads the page of `plugin-cdp`, which is **not** in
`compiled_plugins:` — it loads out-of-process over gRPC — and asserts both its rendered placement
and its CUE parameter schema.

That step is what fails if the generator ever narrows to documenting only the default-active set
(the binary's own command model, or the enabled-boxes list). It is deliberately the assertion
that breaks first, because silently omitting everything that is not compiled in is the most
plausible way for this catalog to go quietly wrong.

## The check-docs bed

```bash
charly check run check-docs
```

A `disposable: true` pod deploy of `docs-site-app`. Reaching steady state proves the box builds,
starts and stays up; the shape assertions already ran at image build.

The generator's own cross-reference integrity gate (an unresolvable
`/charly-<plugin>:<skill>` reference fails generation) is covered by the plugin's Go tests plus
`task docs:drift` on the host — this bed covers the artifact those produce.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `docs-site-pinned-commit` FAILS | the clone layer is stale, or `DOCS_REF` was re-pinned without rebuilding |
| `task docs:pin` fails | `DOCS_REF` (or the check's literal sha) drifted from the `docs` gitlink |
| fetch fails `upload-pack: not our ref <sha>` | `DOCS_REF` names a commit not reachable from ANY ref in the docs repo — never pushed, or garbage-collected |
| fetch fails `couldn't find remote ref <name>` | `DOCS_REF` holds a ref NAME rather than a sha, which the pinned-commit contract forbids |
| `npm ci` fails on a lockfile mismatch | `package.json` and `package-lock.json` disagree — regenerate the lockfile in the docs repo |
| a shape check fails but `index.html` exists | the generator emitted a different tree layout; re-run `task docs:sync` and check the diff |

## Cross-References

- `/charly-build:docs` — the `charly docs generate` verb that produces the content this builds.
- `/charly-coder:nodejs` — the node runtime this candy requires.
- `/charly-check:check` — the bed model and the check-verb catalog.

## When to Use This Skill

Invoke when working with the `docs-site` candy, the `docs-site-app` box, the `check-docs` bed, or
when the documentation site fails to build.
