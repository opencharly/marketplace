---
name: docs
description: |
  The `charly docs generate` verb — the generator that renders the reference half of the
  opencharly.ai documentation site from this repo's canonical sources.
  MUST be invoked before any work involving the `charly docs` command, the docs/ submodule's
  generated trees, `task docs:sync` / `task docs:drift`, the candy/plugin-docs runtime plugin,
  or the cross-reference rewriting that turns `/charly-<plugin>:<skill>` into site links.
---

# docs — generate the opencharly.ai site

`charly docs generate` emits the generated half of the documentation site published at
**opencharly.ai** from the sources that already exist in this repository. It is served by
`candy/plugin-docs`.

## Placement: a RUNTIME plugin, deliberately

`plugin-docs` is **not** listed in `charly/charly.yml`'s `compiled_plugins:`. A dev-time
documentation generator has no business inside every shipped `charly` binary — it is run on a
contributor's machine to regenerate the site and nowhere else.

charly prescans the declared `docs` word into the Kong grammar before parse and syscall.Exec's
the plugin binary in CLI mode on the first actual `charly docs` invocation. Nothing about the
generator needs the host reverse channel (it reads files and writes markdown), which is exactly
what makes the out-of-process placement free here — the same property that lets `charly candy`
and `charly migrate` run in either placement.

Because it is not in `compiled_plugins:`, the plugin is **not in `go.work`**. Build and test it
with `GOWORK=off`:

```bash
cd candy/plugin-docs && GOWORK=off go build ./... && GOWORK=off go test ./...
```

## Usage

```bash
task docs:sync     # regenerate into docs/ (runs build:binary first)
task docs:drift    # FAIL if the committed site is stale — regeneration must be a no-op
task docs:dev      # local preview at http://localhost:4321
task docs:build    # production build into docs/dist

# the underlying verb
charly docs generate --out docs/src/content/docs --root .
```

| Flag | Meaning |
|---|---|
| `--out` | docs content root to write into (required) |
| `--root` | repo root holding `charly.yml`, `candy/`, `box/`, `plugins/` (default: cwd) |

## What it emits

The generator owns four trees and rewrites them wholesale each run, so a deleted source entity
disappears from the site instead of lingering as an orphan page. The hand-authored narrative
(`index.mdx`, `start/`, `concepts/`, `guides/`) is never read or written.

| Tree | Source |
|---|---|
| `vision.md` | `VISION.md` verbatim, repo-relative links rewritten for a web reader |
| `reference/cli/` | one page per `command:` provider word |
| `reference/candy/` | every defined candy: packages, services, and its `plan:` as an acceptance spec |
| `reference/box/` | every defined box |
| `reference/plugin/` | providers, placement, rendered `schema/*.cue` |
| `reference/providers.md` | the inverted index: every reserved word → its owning plugin |
| `recipes/` | every skill plus its `references/*.md` detail pages |

Every emitted file carries a `DO-NOT-EDIT` header, and **regeneration on a clean tree is a
no-op** — the same drift gate SDD applies to generated Go.

## Defined, not default-active

The catalog enumerates what is **defined**, never what happens to be switched on. This is not a
stylistic preference; the obvious surfaces are actively wrong for the purpose:

- `charly box list boxes` lists **enabled** boxes, and resolves through main's `import:` closure —
  which pulls arch, cachyos and fedora but **not** debian or ubuntu. A catalog built on it omits
  every `debian.*` and `ubuntu.*` box (ten definitions that are checked out and have their own
  skills) while duplicating ten arch boxes under transitive `cachyos.arch.*` aliases.
- A plugin absent from `compiled_plugins:` still loads out-of-process when a plan references its
  word, so "in the binary" is not the same set as "exists".

So the generator walks **each repo as its own project root** — the superproject plus every
`box/<distro>` submodule — and unions the results.

## Cross-reference rewriting

The skill corpus is densely self-linked in harness syntax (`/charly-check:check` alone appears
277 times). Every reference is rewritten to a site link, and **an unresolvable reference fails
the build** rather than emitting a dead link — which makes the docs build a corpus-wide integrity
check. Three guards keep real content from being mangled into links, each earned from an actual
corpus case:

1. the skill part must start with a letter — else `redis://charly-redis:6379` matches;
2. the reference must not follow `/` — URL authorities;
3. it must not follow a word character — image tags like `localhost/charly-selkies-kde:latest`.

`references/<file>.md` pointers (backticked paths, never markdown links) resolve to the skill's
own child page.

### Authoring consequence: you cannot write a fake reference

Because the gate fails closed, a **well-formed reference in prose must resolve** — there is no
escape syntax. A skill therefore cannot write `/charly-` followed by two real-looking lowercase
words as a throwaway example: that shape matches, resolves to nothing, and fails the docs build.

Write generic forms with angle-bracket placeholders instead — `<` is not a letter, so the
pattern never matches:

```
/charly-<plugin>:<skill>     ✅ safe in prose
```

This is not hypothetical, and it bit twice in one sitting. The first draft of
`/charly-tools:docs-site` used a made-up two-word reference as its example of an unresolvable
one, and the generator dutifully aborted — the skill documenting the gate tripped the gate. The
fix's own "don't do this" example then tripped it a second time. Failing closed is still the
right behaviour (a typo'd real reference is far likelier than a deliberate fake one), so
describe the bad shape rather than spelling it.

## Why declarative sources, not the CLI's help output

The host renders every dynamic command word with a generic stub description, intercepts the
depth-1 `--help` itself, and plugin-served help arrives in at least three mutually incompatible
formats with no machine-readable dump. Parsing that would be the fragile shim R4 forbids. Every
fact the site needs is already declared: `plugin.providers`, the per-plugin `schema/*.cue`, and
each candy's `description:`.

The trade-off is stated rather than hidden: command PARENTHOOD is a Go method
(`CommandParent()`), not a manifest field, so CLI pages name the word and its owning plugin
without asserting where it nests. The narrative CLI guide covers the nesting and the three
core-spine words (`box`, `version`, `reap-orphans`) that are not `command:` providers.

## Cross-References

- `/charly-tools:docs-site` — the candy + `check-docs` bed that builds and proves the site.
- `/charly-internals:plugin` — placement, the provider model, the CUE-schema contract.
- `/charly-internals:skills` — the skill corpus this site publishes.

## When to Use This Skill

Invoke before running or modifying `charly docs`, editing `candy/plugin-docs`, touching the
`docs/` submodule's generated trees, or changing anything the generator reads (a candy's
`description:`, a plugin's `providers:` or CUE schema, a skill's frontmatter or cross-references).
