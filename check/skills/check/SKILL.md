---
name: check
description: |
  MUST be invoked for every `charly check` mode, candy or box plan authoring,
  disposable test beds, R10 runs, agent grading, baked plan labels, or check
  operation. Covers image/live/run, the plugin-provided live probe verbs,
  deterministic verb catalog, runtime variables, overlays, plan inclusion,
  cross-deployment probing, and the bounded AI-iteration harness.
---

# Check — unified declarative + AI-iteration evaluation

## Overview

`charly` ships a goss-inspired declarative testing framework built into the
CLI. Plan steps — each one intent keyword (`run:`/`check:`/`agent-run:`/
`agent-check:`/`include:`) carrying prose, plus at most one verb-position key for
`run:`/`check:` — are authored as an ordered unnamed list under `plan:` inside a
`candy:` entity (layer or image) in `charly.yml`; an optional `id:` names a step.
They are baked into the `ai.opencharly.description` OCI label
(`LabelDescriptionSet`, which carries the collected plan steps with
`candy:`/`box:`/`deploy` origin annotations) so any pulled image is self-testable
without its source repo. A local `charly.yml` overlay can add steps or override
baked ones by `id:`. The runner resolves deploy-time variables (actual host port
mappings, volume backings, env vars, container IP, DNS) at execution time, so a
check written once works unchanged when `charly.yml` remaps ports.

The surface is three orthogonal verbs: **`charly check box <image>`** evaluates
the built image artifact in an isolated disposable container (build-context
`check:` steps only); **`charly check live <name>`** evaluates a running
deployment (deploy-context steps too, with full runtime-variable resolution);
**`charly check run <bed>`** runs a `disposable: true` R10 deploy end to end —
or, when the bed carries an `iterate:` block, drives an AI runner through
plateau-bounded iterations instead. Mode is explicit in the verb; there is no
autodetect. Full detail: `references/beds-and-r10.md`.

Agent Driven Evaluation (ADE) runs an entity's own baked plan as acceptance
tests: a `check:` step's inline verb is graded deterministically, while an
`agent-check:` step (prose only) is graded by an AI agent via `charly box/check
feature run`. Every candy MUST ship a non-empty `description:` + at least one
deterministic `check:` step (`charly box validate` enforces it); the live agent
grader stays opt-in. Full detail: `references/authoring-gotchas.md`.

## Quick Reference

| Action | Command | Description |
|--------|---------|-------------|
| Pure-box check (disposable, build-context) | `charly check box <image>` | Candy + box sections only, in `podman run --rm` (no host port mappings, no volumes attached) |
| Live full-stack check (running deployment) | `charly check live <name> [-i instance]` | All three sections run via `podman exec` / SSH / nested chain, with full runtime variable resolution |
| R10 bed (full sequence) | `charly check run <bed>` | Build → check image → deploy → check live → fresh update → tear down on a `disposable: true` deploy (ONE bed per invocation). Canonical R10 gate; for a whole roster fan the short beds out via `/verify-beds` and own each long bed (`vm`/`android`, or last run ≥600s) as a persistent-session `run_in_background` task |
| AI iteration loop | `charly check run <bed>` | Drives an AI through plateau-bounded iterations against a bed carrying an `iterate:` block |
| Validate authored tests at config time | `charly box validate` | Schema, context/variable consistency, id uniqueness |
| Inspect effective spec | `charly box inspect <image>` | JSON includes merged check structure |
| Filter by verb | `charly check live <name> --filter file --filter port` | Repeatable |
| Filter by section | `charly check live <name> --section deploy` | One of: candy / box / deploy |
| Output format | `charly check live <name> --format json\|tap\|text` | Default text |

## Reference index

Detail lives in sibling `references/*.md` files, loaded on demand:

| Topic | Reference | Covers |
|---|---|---|
| Disposable beds, R10 acceptance gate | `references/beds-and-r10.md` | The bed roster, the "R10 gate by change class" matrix (sole owner), the 10 Testing Standards, "Flag discipline" (sole owner), exit codes, the three primary modes, wall-clock/timing data |
| Deterministic verb catalog | `references/verb-catalog.md` | The `plan:` authoring model, the file/package/service/port/process/command/http/... verb catalog, shared modifiers, matcher forms, verb routing (executor selection), runtime variables, `charly.yml` overlay rules |
| Live-container probe verbs | `references/live-probe-verbs.md` | The out-of-process `cdp`/`wl`/`dbus`/`vnc`/`mcp` verbs — method allowlists, worked examples, artifact-validation modifiers |
| Authoring gotchas, ADE, AI harness | `references/authoring-gotchas.md` | Agent Driven Evaluation (the six-stage loop, the agent-grader contract), the 12 numbered authoring gotchas, the AI-iteration harness pgrep-deadlock defense |
| Cross-deployment probing | `references/cross-deployment-probing.md` | Image preflight (host-target runs), venue-from-position members, `${HOST:...}` addressing, the pod→pod and host→pod/VM worked examples |

## Related skills

- **Live-container probe verbs — ALL out-of-process** — the `wl:` Wayland verb (`/charly-check:wl`), the `cdp:` Chrome-DevTools verb (`/charly-check:cdp`), the `vnc:` VNC-framebuffer verb (`/charly-check:vnc`), the `dbus:` D-Bus verb (`/charly-check:dbus`), the `mcp:` MCP-protocol verb (`/charly-build:charly-mcp-cmd`), the `record:` recording verb (`/charly-check:record`), the `kube:` cluster-probe verb (`/charly-kubernetes:check-k8s`), the `adb:` ADB verb (`/charly-check:adb`), the `appium:` Android-UI verb (`/charly-check:appium`), the `spice:` SPICE-wire verb (`/charly-check:spice`), and the `libvirt:` VM-probe verb (`/charly-check:libvirt`) are NOT host `charly check` subcommands — each is a declarative check verb served out-of-process by its plugin (`candy/plugin-wl`, `candy/plugin-cdp`, `candy/plugin-vnc`, `candy/plugin-dbus`, `candy/plugin-mcp`, `candy/plugin-record`, `candy/plugin-kube`, `candy/plugin-adb`, `candy/plugin-appium`, `candy/plugin-spice`, `candy/plugin-vm`). See `references/live-probe-verbs.md`.
- `/charly-image:layer` — layer authoring; the ordered `plan:` step list is part of every `charly.yml`.
- `/charly-image:image` — image-level plan steps at composition time.
- `/charly-core:deploy` — local `charly.yml` overlay rules and the plan-step merge.
- `/charly-build:validate` — static schema + cross-scope variable checks; the first
  gate before `charly box build`.
- `/charly-build:build` — how check entries are embedded into the OCI label at build
  time; LABELs-at-end cache behavior.
- `/charly-build:inspect` — view the merged plan / description structure as JSON.
- `/charly-build:migrate` — `charly migrate` brings legacy configs up to the
  current schema (one flat ordered `plan:` list per entity).
- `/charly-internals:go` — implementation map. Core keeps the check-harness
  host seams + verb-catalog semantics: `checkspec.go` (`opActsInBuildDeploy`),
  `planrun_adapter.go` (the op-context grammar `opEffectiveContexts`/`opInContext`
  + `hostVerbResolver`/`hostCheckCarrier`), `checkrun.go` (verdict helpers +
  committed-APK anchoring data), `checkrun_charly_verbs.go`,
  `check_endpoint_resolve.go`, `check_graphics_endpoint.go`, `checkrun_act.go`,
  `check_venue_resolve.go`, `provider_checkenv.go`, the `host_build_check_*.go`
  check seams (`host_build_check_load_plugins.go`, `host_build_check_bed_gpu_prereq.go`),
  plus the `LabelDescriptionSet` type in `labels.go`. The
  op-level check validation (`validateOps` / `validateCheck`) moved out of core
  to `candy/plugin-box/validate_check.go`. The
  `charly check` CLI + AI-iteration harness (the management Cmds, the iteration
  loop, the watchdog, clone/note/synccreds/runlocal) + EVERY check-run mode body
  (box/live/feature-live/feature-box/score/preflight) live in the compiled-in
  `command:check` plugin `candy/plugin-check/` (the former "check-run" HostBuild
  seam is DELETED, K-wave 2 cone R4).
- `/charly-internals:generate-source` — how `LabelDescriptionSet` is written into the Containerfile
  via `writeJSONLabel`, and why the LABEL block lives at the end of the
  final stage.
- `/charly-internals:capabilities` — the `ai.opencharly.description` label (`LabelDescriptionSet`) carrying the baked plan is
  part of the same capability contract as `LabelService`.
- `/charly-internals:agents` — the sub-agents (`check-bed-runner`,
  `deploy-verifier`) and dynamic workflows (`/verify-beds`,
  `/audit-deploy-configs`) that drive these beds, and the R10/disposable/
  paste-proof rules that bind any agent or workflow running `charly check run`.
- `/charly-internals:plugin` — a `check:` step's `<word>: <input>` verb sugar dispatches
  to a plugin-provided verb (built-in or out-of-tree); the desugared internal input is
  validated at runtime against the plugin's served CUE schema before `runPluginVerb`
  invokes it.

## When to Use This Skill

**MUST be invoked** before authoring, running, or debugging check
behavior at any level. Triggers: `charly check` (any subcommand), `charly check
run`, `charly check box`, `charly check live`, the plan steps / `description:`
field in a candy/box `charly.yml`, the disposable test-bed deploys, the
`ai.opencharly.description` OCI label, `kind: agent` (the agent grader) or a
`disposable: true` deploy (+ its `iterate:` block),
`charly check run <bed>` (disposable R10 deploys; roster fan-out via `/verify-beds`), or any check
verb by name (file/port/http/command/package/service/cdp/wl/dbus/vnc/mcp/...).
