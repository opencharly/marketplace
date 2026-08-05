## The per-plugin CUE schema — the single source, two consumers

**Every plugin WITH authored input ships its OWN `.cue` schema, and it is the SINGLE SOURCE for that
plugin's params.** This is the project rulebook "Schema Driven Design (SDD)" pillar (`AGENTS.md` / `CLAUDE.md`) applied per-plugin: the schema
comes BEFORE the plugin's code, and both consumers below are derived from that one source (the
cross-generator pipeline map + the generation-coverage current state live in `/charly-internals:go`
"Schema Driven Design (SDD)"). An INPUT-LESS plugin (no `input_def` on any capability) ships NO schema —
the load gate waives it (the former requirement forced dozens of near-identical stub files). The schema is
SELF-CONTAINED (package-less, references no base def) and used two ways — the SAME contract core `spec` uses:

1. **DEV-TIME → Go params.** `cue exp gengotypes` (driven by `task cue:gen`, which wraps the schema with
   `package params` + `@go(params)`) emits the plugin's `params/cue_types_gen.go`. The provider decodes
   `plugin_input` into that TYPED struct — never a hand-parsed `map[string]any`, never a hand-written struct.
2. **RUNTIME → schema-over-RPC.** The plugin SERVES its `.cue` source over the Provider **`Describe`**
   channel (the proto `Capabilities.schema_cue` field + structured `ProvidedCapability{class,word,input_def}`).
   The host splices it onto charly's base schema (`base ++ plugin`, via the public `spec/schemaconcat` — the SAME
   concat contract as the runtime `sharedCueSchema`, R3) and validates every authored verb input (the
   desugared internal `plugin_input`) against the plugin's def (e.g. `#MyprobeInput`). The host **never reads a candy's `schema/` dir from disk** — the
   schema travels WITH the plugin.

**A `class:step` plugin ALSO declares its install-step contract over Describe (F3).** A step plugin (a
PLUGIN-contributed install-step KIND, distinct from a `class:verb` step which rides the fixed
`ExternalPlugin` kind) sets `ProvidedCapability.StepContract{Scope,Venue,Gate,Emits}` (the proto
`step_contract` field; `sdk.ProvidedCapability.StepContract`) — the host carries that DECLARED contract so
a `run:` step carrying the word's `<word>: <input>` sugar lowers to an `externalStep` (kind
`external:<word>`, opaque Payload) the OPEN DEFAULT ARM dispatches via `OpExecute`, with NO compiled-in case. Reverse is NOT declared (an external
step's teardown ops are recorded dynamically from its `OpExecute` reply). **BUILD leg (F-STEP-EMIT):**
`StepContract.Emits=true` declares the step ALSO produces a build-context Containerfile FRAGMENT — served by
`Invoke(OpEmit)` → `spec.EmitReply.Fragment`. Composed into a POD overlay (add_candy), the pod-overlay
`deploykit.OCITarget` (in the candy `plugin-deploy-pod`) reaches the host's open external-step arm
(`ociEmitStep`, over `HostBuild("step-emit","oci-emit-step")`) which Invokes that OpEmit and splices the fragment (`Emits=false` → a
deploy-only step, skipped on the image build, like apk); a HOST-COUPLED step's OpEmit calls back
`HostBuild("step-emit", …)` for a host-engine-rendered fragment. A step plugin serving OpEmit is a PURE
step (self-contained fragment); the reference `candy/plugin-example-stepkind` serves BOTH legs (OpExecute at
deploy, OpEmit at build). A `class:step` plugin may ALSO serve ONLY the build-emit leg: the compiled-in
`candy/plugin-installstep` serves `OpEmit` for the compiler-emitted builtin InstallStep kinds, fed the
compiler-produced step VIEW as payload — those kinds keep their typed IR + `kit.WalkPlans` deploy leg
(so the plugin needs no `OpExecute`); the host routes them by `pluginEmitStepWords`, not the
`external:<word>` arm. Two sub-categories: the PURE kinds
(file/shell-hook/shell-snippet/service-packaged/service-custom/repo-change/apk-install, C1.1; + the
no-op-emit reboot, C1.6 — `apk-install`/`reboot` declare `Emits=false` and are skipped at build) format
their fragment directly from the view; the HOST-COUPLED `system-packages` (C1.2) + `builder` (C1.3) +
`local-pkg-install` (C1.4) + `op` (C1.5) kinds instead call back `HostBuild("step-emit", …)` (echoing the returned
`EmitReply`) because their render needs the host build engine (`system-packages`: DistroDef format templates;
`builder`: the multi-stage `buildStageContext` + `RenderTemplate` engine; `local-pkg-install` is DIFFERENT
(W3) — its render `deploykit.RenderLocalPkgImageInstall` is a PURE sdk/deploykit function needing no host
callback, routed through this seam only for `buildEngineContext` threading uniformity; `op`: the RICHEST — `Generator.emitTasks`, the
full per-verb render pipeline with COPY staging + op coalescing). Authoring + IR mechanism: `/charly-internals:install-plan` (the
`externalStep` row + the build-emit externalization note); reference: `candy/plugin-example-stepkind`,
`candy/plugin-installstep`.

**Zero builtin/external distinction in schema handling.** Both arrive at the host as a `PluginUnit`
(`Providers` + `Schema`) from `PluginTransport.Connect` — `InProcTransport` for a builtin, `LocalTransport`
(go-plugin exec) for an external. The host's load/gate/validate code NEVER branches on which kind it is. The
only difference is WHERE the plugin runs (compiled into charly vs a separate process), and therefore WHEN its
providers register (a builtin at `init()`, an external at deploy/check load) — a load-TIMING property, never a
schema-handling one.

### The load gate + the validator (one each, shared)

- `registerPluginUnitSchema(name, schema)` is THE load gate (`plugin_loader.go`), byte-identical for builtin
  and external: it rejects a schema that will not **splice** onto the base, a declared `input_def` the
  schema does not define, and an EMPTY schema from a plugin that DOES declare input defs — all LOUD failures
  at load. An input-less plugin (no `input_def` on any capability) legitimately serves NO schema and passes
  the gate. Builtins are gated at process start (`loadBuiltinPluginUnits`, a `sync.Once` pass over every
  registered unit); externals at connect (`loadPluginUnit` → build on host → `LocalTransport.Connect` →
  gate → register).
- `validateAuthoredPluginInput(class, word, json)` is THE validator: it looks the def up in the process-wide
  `pluginSchemas` set (filled by the gate) and unifies the authored input against it. Wired into
  `runPluginVerb` before dispatch — a missing/empty/typo'd field is a hard `TestFail`, not a silent surprise.

## Why self-contained schemas

A plugin's `#<Word>Input` references NO base def, so it compiles STANDALONE — the exact property
`cue exp gengotypes` needs to generate Go params, AND the property that lets the SDK compile it serve-side.
The host's `base ++ plugin` splice therefore exists to detect a def-name **collision** with the base, not to
resolve base references. (`TestExternalSchemaSelfContained` proves a base-referencing schema fails a standalone
compile.)

