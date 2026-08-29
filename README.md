# OpenCharly Marketplace

Claude Code, Codex, Kimi, and pi plugins for OpenCharly — the fully equipped factory floor for you and your agents.

This repository IS the marketplace: every plugin family lives flat at the repo root
(`<family>/skills/…`, `<family>/agents/…`, per-family manifests), and the root carries one
catalog per harness. Everything under the corpus trees is **GENERATED** from the
[opencharly/charly](https://github.com/opencharly/charly) candies by
`charly marketplace generate` — edit a `skill:`/`hook:`/`marketplace:` entity in charly's
`candy/`, regenerate, and land the corpus here. Hand-authored files are only
`README.md`, `CLAUDE.md`, `LICENSE`, `CHANGELOG/`, `scripts/squash_body.py` and
`kimi-user-config.toml` — everything else carries a DO-NOT-EDIT header.

## How this marketplace is organized

Plugins are sorted into **four use-case buckets**:

| Bucket | When to install | Plugins |
|---|---|---|
| **commands** | "I want to run charly verbs" | `charly-core`, `charly-build`, `charly-check`, `charly-automation` |
| **kind** | "I want to author the YAML schema for an entity" | `charly-image`, `charly-vm`, `charly-kubernetes`, `charly-local`, `charly-pod` |
| **development** | "I'm a contributor working on the charly source code itself" | `charly-internals` |
| **images** | "I want to deploy a specific image" | `charly-distros`, `charly-languages`, `charly-infrastructure`, `charly-tools`, `charly-jupyter`, `charly-coder`, `charly-selkies`, `charly-openclaw`, `charly-punktfunk`, `charly-versa`, `charly-ollama`, `charly-openwebui`, `charly-comfyui`, `charly-immich`, `charly-hermes`, `charly-filebrowser` |

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
| **charly-build** | — | Build/authoring: build, generate, list, inspect, merge, new, pull, validate, secrets, settings, migrate, reconcile, charly-mcp-cmd, docs (the opencharly.ai site generator). |
| **charly-check** | — | Live-container evaluation: `check` orchestrator + cdp, wl, wl-overlay, dbus, vnc, spice, libvirt, record, adb, appium, punktfunk probes + `android` (the `kind: android` device + `apk:` package format + Android-device deploy) + the `check-sway-browser-vnc-pod` R10 bed. |
| **charly-automation** | — | tmux verb, agent control plane (agent skill + agent-control-operator agent), host-side wrappers (alias, udev), topic flags (enc, sidecar, openclaw-deploy). |

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
| **charly-internals** | — | The contributor rulebook skills: git-workflow, root-cause-analyzer, strict-policy, cutover-policy, agents, skills, plugin, disposable, go, egress, generate-source, install-plan, local-infra, vm-deploy-target, vm-spec, ovmf, libvirt-renderer, cloud-init-renderer, capabilities. |

### images — the deployable catalog

| Plugin | MCP server | Purpose |
|---|---|---|
| **charly-distros** | — | The distro image families (arch/cachyos/debian/fedora/ubuntu + their builders and bootstrap variants). |
| **charly-languages** | — | Language images. |
| **charly-infrastructure** | — | Infrastructure services. |
| **charly-tools** | — | The CLI tools catalog (ripgrep, yay, himalaya, dsh, gogcli, mcporter, nano-pdf, ordercli, sag, sherpa-onnx, songsee, summarize, whisper, xurl). |
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
