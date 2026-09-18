# OpenCharly Marketplace

Claude Code, Codex, Kimi, and pi plugins for OpenCharly — the fully equipped factory floor for you and your agents.

This repository IS the marketplace: every plugin family lives flat at the repo root
(`<family>/skills/…`, `<family>/agents/…`, per-family manifests), and the root carries one
catalog per harness. Everything under the corpus trees is **GENERATED** from the
[opencharly/charly](https://github.com/opencharly/charly) candies by
`charly marketplace generate` — edit a `skill:`/`hook:`/`marketplace:` entity in charly's
`candy/`, regenerate, and land the corpus here. Hand-authored files are only
`README.md`, `CLAUDE.md`, `LICENSE`, `CHANGELOG/`, `scripts/squash_body.py`,
`scripts/refresh-refs.sh` and `kimi-user-config.toml` — everything else carries a
DO-NOT-EDIT header (`DISPATCHER.md` carries the generated-dispatcher markers in place
of that header).

## How this marketplace is organized

Plugins are sorted into **four use-case buckets**:

| Bucket | When to install | Plugins |
|---|---|---|
| **commands** | "I want to run charly verbs" | `charly-agent`, `charly-authoring`, `charly-automation`, `charly-bpf`, `charly-build`, `charly-cache`, `charly-candy-cli`, `charly-cardwire`, `charly-check`, `charly-core`, `charly-feature`, `charly-pipeline`, `charly-pod-verbs`, `charly-review` |
| **kind** | "I want to author the YAML schema for an entity" | `charly-image`, `charly-vm`, `charly-kubernetes`, `charly-local`, `charly-pod` |
| **development** | "I'm a contributor working on the charly source code itself" | `charly-internals` |
| **images** | "I want to deploy a specific image" | `charly-agentteams`, `charly-coder`, `charly-comfyui`, `charly-crabbox`, `charly-distros`, `charly-filebrowser`, `charly-hermes`, `charly-immich`, `charly-infrastructure`, `charly-jupyter`, `charly-languages`, `charly-ollama`, `charly-openclaw`, `charly-openwebui`, `charly-punktfunk`, `charly-selkies`, `charly-tools`, `charly-versa` |

The layout is **flat** — every plugin sits at `<family>/` (no `charly-` prefix in directory
names). The `charly-` prefix lives exclusively in each `plugin.json`'s `name:` field, which
means every skill invocation is `/charly-<plugin>:<skill>` (e.g. `/charly-core:ssh`,
`/charly-jupyter:jupyter`, `/charly-distros:arch`). The `category:` field in
`marketplace.json` provides the four-bucket grouping for the plugin manager UI.

## Install per harness

| Harness | Install |
|---|---|
| **Claude Code / Cursor** | `/plugin marketplace add opencharly/marketplace`, then `/plugin install <name>@charly-plugins` (or `claude plugin marketplace add opencharly/marketplace`) — the catalog is `.claude-plugin/marketplace.json`. No `version` fields anywhere: plugins version by the marketplace commit SHA, so every corpus update is picked up on `/plugin marketplace update`. |
| **Codex CLI / AGENTS** | register the repo by GitHub source (`codex plugin add opencharly/marketplace`) — the catalog is `.agents/plugins/marketplace.json`, entries `INSTALLED_BY_DEFAULT`. |
| **Kimi Code** | `/plugins marketplace https://opencharly.github.io/marketplace/kimi.json` (or `KIMI_CODE_PLUGIN_MARKETPLACE_URL`), or install the whole repo as one plugin: `/plugins install https://github.com/opencharly/marketplace` — `kimi.plugin.json` lists every family's `skills/` + `agents/`. |
| **pi** | add `"git:github.com/opencharly/marketplace"` to the project's `.pi/settings.json` `packages` — `package.json` declares the `pi` resource (`./*/skills` glob, `pi-package` keyword), installed automatically at startup. |
| **Docs** | the opencharly/docs repo pins this repo as a submodule and passes it to `charly docs generate --plugins` — the site's recipe pages are a projection of this corpus. |

The catalog mirror (the raw catalogs + the kimi JSON) is published to
[GitHub Pages](https://opencharly.github.io/marketplace/).

## Regeneration

The `deploy.yml` workflow is the SOLE owner of generation: it clones charly at the pinned
CI-time tag (this repo carries no charly submodule — a declared submodule is initialized on
every fetch, which dragged the whole charly repo into consumer trees), builds the binary,
regenerates the corpus, and **fails closed on any diff** (the drift gate — including untracked
files). A marketplace PR bumps the charly pin and carries the regenerated corpus in the same
change.

The generator produces the corpus and nothing else. It no longer writes charly's harness
surface (`.claude/hooks`, a `.claude/settings.json` merge, the R0 dispatcher splice), and the
`./setup` launcher it used to emit is gone with the local-generation workflow it existed for.

## Plugins by bucket

### commands — runtime CLI verbs

| Plugin | MCP server | Purpose |
|---|---|---|
| **charly-core** | — | Lifecycle: start, stop, service, charly-status, logs, shell, ssh, deploy, charly-update, remove, charly-config, cmd, charly-version, charly-doctor, clean. |
| **charly-build** | — | Build/authoring: build, generate, list, inspect, load, merge, new, pull, validate, secrets, settings, migrate, reconcile, charly-mcp-cmd, docs (the opencharly.ai site generator). |
| **charly-check** | — | Live-container evaluation: `check` orchestrator + cdp, wl, wl-overlay, dbus, vnc, spice, libvirt, record, adb, appium, punktfunk, quickshell, jetkvm probes + `android` (the `kind: android` device + `apk:` package format + Android-device deploy) + the `check-sway-browser-vnc-pod` R10 bed. |
| **charly-automation** | — | tmux verb, agent control plane (agent skill + agent-control-operator agent), host-side wrappers (alias, udev), crabbox-deploy + herdr (incl. herdr-box), topic flags (enc, sidecar, openclaw-deploy). |
| **charly-agent** | — | `charly tui` — the terminal UI for the agent control plane: browse and drive agent sessions, runs, and terminal channels interactively. |
| **charly-authoring** | — | The `charly box` authoring verbs (`set`, `add-candy`, `rm-candy`, `write`, `cat`, `fetch`, `refresh`) — mutate box manifests programmatically, fetch remote refs, refresh a project. |
| **charly-bpf** | — | The `charly bpf` eBPF kernel-feature readiness surface (status, lsm, config, probe) — read-only host/kernel inspection before BPF-LSM-gated tooling (e.g. cardwire). |
| **charly-cache** | — | The `charly cache` git-ref cache operator (status, clear, refresh, bypass) — for stale `@github` ref resolution or a pin that will not advance. |
| **charly-candy-cli** | — | `charly candy set` / `charly candy add-<fmt>` — mutate a candy's `charly.yml` safely instead of hand-editing manifests. |
| **charly-cardwire** | — | The `charly cardwire` GPU-manager surface (ogc/cardwire: status, list, config, gpu block/unblock, manager) — inspect or drive the eBPF/LSM GPU-blocking daemon. |
| **charly-feature** | — | `charly feature list\|pending\|validate` — inspect a project's plan-shaped entity descriptions (Agent Driven Evaluation). |
| **charly-pipeline** | — | The `charly pipeline` agent/workflow engine — run a declared plan, the bare agent runtime, deterministic probes, template rendering (`kind:pipeline` entities). |
| **charly-pod-verbs** | — | `charly cp` — copy a file between the host and a running container (app or sidecar); the charly-native replacement for ad-hoc `podman cp`. |
| **charly-review** | — | The `charly review` read-only GitHub PR review engine — the chat-completions review loop, `verb:pr` tools, a deterministic `Verdict: PASS\|BLOCK`. |

### kind — schema-kind authoring

| Plugin | MCP server | Purpose |
|---|---|---|
| **charly-image** | — | Schema for `kind: candy` (charly.yml authoring — `base:`/`from:` makes an image; neither makes a layer). |
| **charly-vm** | — | Schema for `kind: vm` + bootc VM catalog (cloud_image vs bootc, libvirt/QEMU). |
| **charly-kubernetes** | — | Schema for `kind: kubernetes` (k8s manifests, helm). |
| **charly-local** | — | Schema for `kind: local` (host-side templates). |
| **charly-pod** | — | Schema for `kind: pod` (podman-based multi-container pods). |

### development — contributor internals

| Plugin | MCP server | Purpose |
|---|---|---|
| **charly-internals** | — | The contributor rulebook skills: git-workflow, root-cause-analyzer, strict-policy, cutover-policy, agents, skills, plugin, disposable, go, go-quality, egress, generate-source, install-plan, local-infra, vm-deploy-target, vm-spec, ovmf, libvirt-renderer, cloud-init-renderer, marketplace, capabilities. |

### images — the deployable catalog

| Plugin | MCP server | Purpose |
|---|---|---|
| **charly-distros** | — | The distro image families (arch/cachyos/debian/fedora/ubuntu + their builders and bootstrap variants). |
| **charly-agentteams** | — | The AgentTeams multi-agent stack box (CachyOS base): decomposed minio / matrix / element / higress / controller candies + the `charly agentteams` management CLI. |
| **charly-crabbox** | — | The local Crabbox coordinator — remote software-testing/execution runtime (Node.js/PostgreSQL, supervised service on :8080 with `/v1/health` + `/v1/ready`). |
| **charly-languages** | — | Language images. |
| **charly-infrastructure** | — | Infrastructure services. |
| **charly-tools** | — | The CLI tools catalog (blogwatcher, charly, crabbox, cue, docs-site, dsh, dsh-cli, gifgrep, gogcli, goplaces, himalaya, mcporter, nano-pdf, ordercli, ripgrep, sag, sherpa-onnx, songsee, summarize, vscode, whisper, xurl, yay). |
| **charly-jupyter** | — | JupyterLab + jupyter-mcp. |
| **charly-coder** | — | Coder dev images. |
| **charly-selkies** | — | Selkies virtual-desktop streaming. |
| **charly-openclaw** | — | OpenClaw. |
| **charly-punktfunk** | — | Punktfunk streaming host (`punktfunk/1` QUIC + Moonlight compat). |
| **charly-versa** | — | versa. |
| **charly-ollama** | — | Ollama. |
| **charly-openwebui** | — | Open WebUI. |
| **charly-comfyui** | — | ComfyUI. |
| **charly-immich** | — | Immich. |
| **charly-hermes** | — | Hermes. |
| **charly-filebrowser** | — | Filebrowser. |

## Contributing

Skills, agents, hooks and catalog metadata are all generated — **edit the charly candy
entities** (`candy/<name>/charly.yml` in opencharly/charly) and regenerate. A skill that
must not be regenerated has no place here. The corpus validator (`charly marketplace drift
--root ./charly --out .`) must be a no-op on every commit, and the deploy workflow enforces
it.
<!-- drift gate proof: see the PR body (in-repo regeneration, clean status) -->
<!-- drift gate: in-repo regeneration must be a no-op (see PR body) -->
<!-- corpus regenerated from the pinned charly v2026.240.0831 -->
<!-- drift gate: in-repo regeneration is a no-op (verified) -->
