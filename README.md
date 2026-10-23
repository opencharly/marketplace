# OpenCharly Marketplace

Claude Code, Codex, Kimi, and pi plugins for OpenCharly — the fully equipped factory floor for you and your agents.

This repository IS the marketplace: plugin families live at the repo root
(`<family>/skills/…`, `<family>/agents/…`, per-family manifests), alongside the harness
catalogs. Skill and catalog sources live in standalone owning candy repositories,
selected by the canonical [refs list](candy/charly-marketplace/charly.yml).
`charly marketplace generate` projects those pinned sources into this repository.
Hand-authored repository infrastructure includes `README.md`, `AGENTS.md`, `LICENSE`,
`CHANGELOG/`, `scripts/`, workflows and `kimi-user-config.toml`.

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
| **Codex CLI / AGENTS** | register the catalog with `codex plugin marketplace add opencharly/marketplace`, then install a catalog entry with `codex plugin add <plugin-name>@charly-plugins` (for example, `codex plugin add charly-internals@charly-plugins`). The catalog is `.agents/plugins/marketplace.json`; `INSTALLED_BY_DEFAULT` entries are installed when the marketplace is added. See the canonical `charly-internals:marketplace` skill for Codex's skill-description budget and fallback when a catalog is too large. |
| **Kimi Code** | `/plugins marketplace https://opencharly.github.io/marketplace/kimi.json` (or `KIMI_CODE_PLUGIN_MARKETPLACE_URL`), or install the whole repo as one plugin: `/plugins install https://github.com/opencharly/marketplace` — `kimi.plugin.json` lists every family's `skills/` + `agents/`. |
| **pi** | add `"git:github.com/opencharly/marketplace"` to the project's `.pi/settings.json` `packages` — `package.json` declares the `pi` resource (`./*/skills` glob, `pi-package` keyword), installed automatically at startup. |

The catalog mirror (the raw catalogs + the kimi JSON) is published to
[GitHub Pages](https://opencharly.github.io/marketplace/).

## Regeneration

The `deploy.yml` workflow is the SOLE owner of generation: it clones charly at the pinned
CI-time tag (this repo carries no charly submodule — a declared submodule is initialized on
every fetch, which dragged the whole charly repo into consumer trees), builds the binary,
regenerates the corpus, and **fails closed on any diff** (the drift gate — including untracked
files). A refs-list change carries its regenerated corpus in the same change.

The generator produces the corpus and nothing else. It no longer writes charly's harness
surface (`.claude/hooks`, a `.claude/settings.json` merge, the R0 dispatcher splice), and the
`./setup` launcher it used to emit is gone with the local-generation workflow it existed for.

## Consumers

The repos that pin this corpus as a submodule and publish or load a projection of it. Each
one records the pin as a gitlink in its own `.gitmodules`, at the path in the table — the
path is what the refresh workflow reads, over the public API, to learn that consumer's
recorded pin.

| Consumer | Pin path | What it does with the corpus |
|---|---|---|
| `opencharly/docs` | `marketplace` | passes it to `charly docs generate --plugins` — the site's recipe pages are a projection of this corpus |
| `opencharly/opencharly` | `marketplace` | the umbrella's task surface splices this corpus's dispatcher and reads its refs list |

A corpus landing does not carry a consumer's leg: advancing a consumer's pin is a manual
act in that consumer's own repo. The refresh workflow therefore **reports** every consumer
whose recorded pin is behind this repo's merged main — an advance available now, in that
consumer's repo, never a failure here. A consumer that is behind is a normal state between
a corpus landing and the consumer's own PR.

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

Edit source entities in their owning standalone candy repositories, then advance the
[refs list](candy/charly-marketplace/charly.yml) and regenerate the affected corpus.
The generation root is this marketplace checkout. The canonical generation procedure
is in [AGENTS.md](AGENTS.md); the deploy workflow rejects drift, including untracked
regenerated files.
