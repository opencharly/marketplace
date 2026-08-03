---
name: plugin
description: |
  Use when authoring or modifying a charly PLUGIN — a candy with a `plugin:` block that contributes
  Providers (verbs/kinds/deploy-targets/steps/builders/commands), its own CUE schema, builtin (compiled-in) or
  external (out-of-tree git repo). Covers the unified Provider model, the per-plugin CUE-schema contract
  (single source → Go params for dev + schema-over-Describe RPC for runtime), the SDK, and the loader.
---

# Plugins — the unified Provider + per-plugin CUE-schema model

A **plugin is a candy** (`candy/<name>/charly.yml`) carrying a `plugin:` block. The single addition that
makes a candy a plugin is that block:

```yaml
my-plugin:
  candy:
    version: 2026.180.1200          # mandatory CalVer (any candy)
    description: |-                 # mandatory (ADE)
      What this plugin provides.
    plugin:
      providers: [verb:myprobe]     # "<class>:<word>" — class ∈ kind|verb|deploy|step|builder|command|build
      source: builtin               # OR github.com/org/repo/candy/<name>  (out-of-tree)
      primary:
        myprobe: marker             # scalar sugar target: `myprobe: hello` == {marker: hello}
    plan:
      - check: the myprobe verb dispatches and passes   # ADE: ≥1 deterministic check
        myprobe: { marker: hello }  # the verb sugar — map value = the plugin input verbatim
        context: [runtime]
```

A candy with no `plugin:` block is an ordinary candy; one WITH it is a plugin. Full candy authoring surface
applies (`/charly-image:layer`), including the mandatory `version:`/`description:`/`plan:`+`check:` (ADE).

## Reference Index

| Topic | File |
|---|---|
| The kernel/plugin boundary law (E/M/B/D/R, the decision procedure, the incomplete-seam self-test, the host-boundary-object trap, the resolve-to-envelope canonical shape) — sole owner of this doctrine — plus the v2 target architecture end-state | `references/boundary-law.md` |
| The unified Provider model (transport-invisible dispatch, the `build` class, lifecycle phases, flat vs structural kind decode), placement (builtin/external × in-proc/out-of-process at build and deploy time), and the four authoring recipes (external, compiled-in, host-coupled kit, external command) | `references/authoring-recipes.md` |
| The per-plugin CUE schema contract (dev-time Go params, runtime schema-over-Describe RPC), the load gate + validator, and why plugin schemas are self-contained | `references/cue-schema-contract.md` |

## Verification

- `go test ./...` — the registry/transport/schema seams (`TestPluginGRPCRoundTrip`,
  `TestExternalPluginEndToEnd` proves the schema travels over RPC, `TestPluginSchemaSpliceValidation`,
  `TestBuiltinPluginSchemasSplice` is the CI gate that every builtin schema splices).
- `task cue:gen` — regenerates spec + every plugin's params; reproducible (a second run is a no-op).
- `charly box validate` — the candy + `plugin:` block (`candy/plugin-box/validate_rules.go`'s
  `IsPlugin` check — an explicit, documented 1:1 port of the former core `validatePluginCandy`, deleted
  as dead code in the 2026-07-22 dead-code-radical-removal batch once its call site moved here —
  verifies each capability is well-formed and, for `source: builtin`, that the provider is actually
  compiled in).
- R10: a disposable bed composing a builtin AND an external plugin, driven to a fresh `charly update` — the
  builtin's baked check + the external's out-of-process check both pass.

## Cross-References

- `/charly-internals:go` — the provider registry + the reserved-word spine (verbs/kinds/deploy/steps/builders/commands).
- `/charly-image:layer` — the candy authoring surface the `plugin:` block extends.
- `/charly-check:check` — the plugin-verb check steps (`<word>: <input>` sugar) + ADE (a plugin's own acceptance plan).
- `/charly-build:validate` — `charly box validate` rules.
- `/charly-internals:install-plan` — the `pluginDeployTarget` deploy lifecycle (`OpExecute` reverse channel, ledger record) + the `OpEmit` build-time fragment; the deploy wire types CUE-sourced at `sdk/schema/deploy.cue` / `sdk/schema/buildwire.cue` / `sdk/schema/seam.cue`.
- `/charly-build:generate` + `/charly-internals:generate-source` — the build-time plugin connect seam + the `emitTasks` placement-agnostic plugin-verb dispatch (`OpEmit` → fragment).

## When to Use This Skill

Invoke before authoring or editing any `plugin:` block, any `sdk/**` code, the plugin SDK, a
compiled-in plugin candy (`compiled_plugins:`) or host-coupled kit candy, an external plugin module, or the
plugin schema/param gen pipeline.
