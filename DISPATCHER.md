<!-- BEGIN GENERATED SKILL DISPATCHER -->
| Trigger (what the user said or you're about to do) | Skill to load |
|---|---|
| `charly tui` / agent TUI / interactively browse agent sessions | `/charly-agent:tui` |
| the agentteams box / the AgentTeams multi-agent stack (Manager–Workers, Rooms, the controller + matrix + element + higress + minio candies) on the pod or vm substrate / the `check-agentteams-pod` and `check-agentteams-vm` beds | `/charly-agentteams:agentteams` |
| `charly agentteams` controller management (workers / teams / humans) / the `verb:agentteams` check verb (`status`, `manager-running`, `worker-running`, `worker-list`) / hydrating a deployment with `charly agentteams apply -f` | `/charly-agentteams:agentteams-cli` |
| `charly box set` / `charly box add-candy` / `charly box rm-candy` / `charly box write` / `charly box cat` / `charly box fetch` / `charly box refresh` | `/charly-authoring:authoring` |
| `charly agent` / agent control plane / sessions / runs / terminal channels / `charly tui` / MCP routing / agent target routing | `/charly-automation:agent` |
| host command alias / `charly alias` / wrapper script in a container | `/charly-automation:alias` |
| crabbox CLI / local coordinator / remote-execution broker / composing the crabbox candies | `/charly-automation:crabbox-deploy` |
| `charly config` encrypted volumes / gocryptfs / the `--encrypt` flag / config mount-unmount-status-passwd | `/charly-automation:enc` |
| ‘charly herdr’ session control (status / workspace / tab / pane / agent helpers) / the `verb:herdr` check verb (`ping`, `workspace-list`, `pane-wait-output`, `agent-wait`, …) / the check-herdr-pod bed / the pod-herdr box | `/charly-automation:herdr` |
| the herdr box (box/herdr) / the check-herdr-pod bed / composing the herdr + socat candies / the herdr: check verb + charly herdr CLI against a deployed herdr venue | `/charly-automation:herdr-box` |
| OpenClaw gateway / `openclaw-*` candies / model auth / browser integration / channel setup | `/charly-automation:openclaw-deploy` |
| sidecars via `charly config` / Tailscale exit nodes / `env_accept` / `env_require` / pod networking | `/charly-automation:sidecar` |
| `charly tmux` sessions / terminal channels / snapshot / transcript / detached-reattach / gRPC terminal | `/charly-automation:tmux` |
| `charly udev` / GPU device access rules / container GPU troubleshooting | `/charly-automation:udev` |
| `charly bpf` / eBPF readiness / BPF-LSM / kernel BPF config | `/charly-bpf:bpf` |
| `charly box build` / `charly box generate` / Containerfile | `/charly-build:build` |
| `charly docs` / the opencharly.ai site / the opencharly/docs repo / Starlight/Astro / `candy/plugin-docs` (runtime plugin) or `candy/docs-site` | `/charly-build:docs` |
| `charly box build` / `charly box generate` / Containerfile | `/charly-build:generate` |
| `charly box load` / delivering an image into a pod's NESTED podman store / nested-podman-socket / the container twin of `charly vm cp-box` | `/charly-build:load` |
| `charly migrate` / schema migration / legacy → latest CalVer / CalVer schema version | `/charly-build:migrate` |
| `charly box reconcile` / cross-repo `@github` pin alignment / candy-version-mismatch cleanup | `/charly-build:reconcile` |
| Secret management / `charly secrets` / Secret Service / GPG `.secrets` | `/charly-build:secrets` |
| `charly box validate` / schema error | `/charly-build:validate` |
| `charly cache` / git-ref cache / stale @github ref resolution / pinned ref won't advance | `/charly-cache:cache` |
| `charly candy` / candy set / candy add-pac/add-deb/add-rpm / edit a candy manifest | `/charly-candy-cli:candy` |
| `charly cardwire` / cardwire GPU manager / GPU block/unblock / cardwired | `/charly-cardwire:cardwire` |
| the `adb:` check verb / Android Debug Bridge probing from a candy/box plan (out-of-process plugin; devices, shell, install, getprop, screencap, logcat, wait-for-device) | `/charly-check:adb` |
| `kind: android` device / `target: android` deploy / `apk:` package format in candies / installing Android apps declaratively / remote-or-emulator adb endpoint / nested `pod → android` | `/charly-check:android` |
| the `appium:` check verb / Android UI automation (out-of-process plugin) / W3C WebDriver sessions, element introspection, the gesture/app/key/device sugar groups, the generic `execute`/`raw` escape hatch | `/charly-check:appium` |
| `charly check *` (ANY check verb, incl. `charly check box`) / `charly check run <bed>` (the disposable-deploy R10 bed) / authoring `disposable: true` check beds / `charly check live` / the probe verbs (cdp/wl/dbus/vnc/mcp/record/spice/libvirt) / `iterate:` AI-agent scoring / `plan:` step authoring / `charlycheck/*` branches / Agent Driven Evaluation (ADE) / `charly box feature run` / `charly check feature run` / `charly feature list/pending/validate` / authoring a candy's `plan:` + `description:` string / the agent grader for `agent-check:` steps / the `adb:` check verb / Android Debug Bridge probing from a candy/box plan (out-of-process plugin; devices, shell, install, getprop, screencap, logcat, wait-for-device) / the `jetkvm:` check verb / IP-KVM control from a candy/box plan (out-of-process plugin; status, screenshot, keyboard/mouse, power/ATX, virtual media, USB, device config) / the `appium:` check verb / Android UI automation (out-of-process plugin) / W3C WebDriver sessions, element introspection, the gesture/app/key/device sugar groups, the generic `execute`/`raw` escape hatch / Verify a cutover by running the R10 beds (drive `charly check run <bed>`) / Evaluate/audit a deployment config (image or deploy, yours) | `/charly-check:check` |
| the `jetkvm:` check verb / driving a JetKVM IP-KVM from a candy/box plan (out-of-process plugin; status, screenshot, keyboard/mouse, power, virtual media, USB, device config) / installing charly on a JetKVM / `charly-jetkvm` / running charly on the armv7 appliance / why there is no MCP server on the JetKVM | `/charly-check:jetkvm` |
| the `punktfunk:` check verb / probing or managing a punktfunk streaming host from a candy or box plan | `/charly-check:punktfunk` |
| Debian images / `debian*` / `box/debian` submodule | `/charly-coder:debian-coder` |
| Fedora images / `fedora*` / `box/fedora` submodule (incl. the GPU base `nvidia` / `python-ml` + `sway-browser-vnc`) | `/charly-coder:fedora-coder` |
| Ubuntu images / `ubuntu*` / `box/ubuntu` submodule | `/charly-coder:ubuntu-coder` |
| `charly clean` / build-artifact retention / `keep_images` / `keep_check_runs` / image-tag pruning / `.check` run cleanup | `/charly-core:clean` |
| `charly fleet add/del` / pod or container deploys / `kind: android` device / `target: android` deploy / `apk:` package format in candies / installing Android apps declaratively / remote-or-emulator adb endpoint / nested `pod → android` / Disposable-flag semantics / `disposable: true` authorization / preemptible-flag / `requires_exclusive:` / `charly preempt` / exclusive host-resource arbitration (GPU passthrough contention) | `/charly-core:deploy` |
| CachyOS images / `cachyos*` / `charly-cachyos` workstation profile / `box/cachyos` submodule | `/charly-distros:cachyos` |
| Fedora images / `fedora*` / `box/fedora` submodule (incl. the GPU base `nvidia` / `python-ml` + `sway-browser-vnc`) | `/charly-distros:charly-fedora` |
| Debian images / `debian*` / `box/debian` submodule | `/charly-distros:debian` |
| Debian images / `debian*` / `box/debian` submodule | `/charly-distros:debian-builder` |
| Debian images / `debian*` / `box/debian` submodule | `/charly-distros:debian-debootstrap` |
| Fedora images / `fedora*` / `box/fedora` submodule (incl. the GPU base `nvidia` / `python-ml` + `sway-browser-vnc`) | `/charly-distros:fedora` |
| Fedora images / `fedora*` / `box/fedora` submodule (incl. the GPU base `nvidia` / `python-ml` + `sway-browser-vnc`) | `/charly-distros:fedora-builder` |
| Fedora images / `fedora*` / `box/fedora` submodule (incl. the GPU base `nvidia` / `python-ml` + `sway-browser-vnc`) | `/charly-distros:fedora-nonfree` |
| Fedora images / `fedora*` / `box/fedora` submodule (incl. the GPU base `nvidia` / `python-ml` + `sway-browser-vnc`) | `/charly-distros:fedora-test` |
| nested-podman-socket / serving a rootless podman API socket at uid 1000 inside a pod / the `/run/user/1000` runtime-dir named volume | `/charly-distros:nested-podman-socket` |
| Fedora images / `fedora*` / `box/fedora` submodule (incl. the GPU base `nvidia` / `python-ml` + `sway-browser-vnc`) | `/charly-distros:nvidia` |
| Omarchy images / `omarchy*` boxes / the `box/omarchy` submodule / `distro: [omarchy, arch]` | `/charly-distros:omarchy` |
| omarchy-cstream / the streamed Omarchy desktop / pod-cstream / layer-cstream-desktop / Hyprland-over-HTTPS | `/charly-distros:omarchy-cstream` |
| Ubuntu images / `ubuntu*` / `box/ubuntu` submodule | `/charly-distros:ubuntu` |
| Ubuntu images / `ubuntu*` / `box/ubuntu` submodule | `/charly-distros:ubuntu-builder` |
| Ubuntu images / `ubuntu*` / `box/ubuntu` submodule | `/charly-distros:ubuntu-debootstrap` |
| `charly feature` / feature list / feature pending / feature validate / ADE entity descriptions | `/charly-feature:feature` |
| Editing a box (`box/<name>/charly.yml` — boxes live in the `box/<distro>` submodules; main owns none), box composition | `/charly-image:image` |
| Editing a candy (`candy/<name>/charly.yml`), candy authoring, candy tasks/services | `/charly-image:layer` |
| Verify a cutover by running the R10 beds (drive `charly check run <bed>`) / Evaluate/audit a deployment config (image or deploy, yours) / Sub-agents / dynamic workflows / agent teams / agent-lifecycle or commit-push gate hooks | `/charly-internals:agents` |
| OCI labels / capabilities contract | `/charly-internals:capabilities` |
| Hard-cutover concerns / rename sweeps | `/charly-internals:cutover-policy` |
| Disposable-flag semantics / `disposable: true` authorization / preemptible-flag / `requires_exclusive:` / `charly preempt` / exclusive host-resource arbitration (GPU passthrough contention) | `/charly-internals:disposable` |
| Egress config validation — validating/generating the config files charly WRITES to a system (`candy/plugin-fleet/egress.go`, `ValidateEgress`, the vendored CUE egress schemas in `candy/plugin-egress/egress-schemas/vendor/`, cloud-init/k8s_object/units/ssh_config/libvirt-XML egress) | `/charly-internals:egress` |
| `charly box build` / `charly box generate` / Containerfile | `/charly-internals:generate-source` |
| Git/`gh` workflow — `feat/` branch, commit, PR-only landing (NO direct push to main), branch protection, the `pr-validator` fresh-evaluator gate, native auto-merge + tag-on-merge CalVer-at-merge, worktree, sync-to-upstream, branch/worktree prune, cross-repo R10 landing | `/charly-internals:git-workflow` |
| Go source work (adding/modifying `charly` commands) / Editing `sdk/schema/*.cue` / `task cue:gen` / `cue exp gengotypes` / generated `cue_types_gen.go` / Schema Driven Design (SDD) / a schema spike | `/charly-internals:go` |
| Go code-quality / CLAUDE.md-compliance audit / `golangci-lint` / `dupl` / duplication or dead-code check / `.golangci.yml` | `/charly-internals:go-quality` |
| IR / InstallPlan / EmitTarget / OCITarget | `/charly-internals:install-plan` |
| local-target deploy / `target: local` / `host: local` (default) / SSH-host deploys / `user:` / `ssh_arg:` | `/charly-internals:local-infra` |
| Marketplace / skill-corpus generation — `charly marketplace generate`, the refs list (candy/charly-marketplace/charly.yml), the drift gate, the daily refresh PRs, per-harness vendoring, or 'my skill is stale' | `/charly-internals:marketplace` |
| Authoring a plugin (a candy with a `plugin:` block) / builtin vs out-of-tree plugin / per-plugin `.cue` schema (single source → `gengotypes` for dev + schema-over-`Describe` RPC at runtime) / the plugin SDK (`github.com/opencharly/sdk`, the proxy-resolved contract module — no submodule) / `sdk/**` / a compiled-in plugin candy (`compiled_plugins:`) or host-coupled kit candy / an external plugin module / Editing `sdk/schema/*.cue` / `task cue:gen` / `cue exp gengotypes` / generated `cue_types_gen.go` / Schema Driven Design (SDD) / a schema spike | `/charly-internals:plugin` |
| Skill authoring / skill maintenance / where does this doc content belong | `/charly-internals:skills` |
| Agent Driven Evaluation (ADE) / `charly box feature run` / `charly check feature run` / `charly feature list/pending/validate` / authoring a candy's `plan:` + `description:` string / the agent grader for `agent-check:` steps / Engineering-discipline triggers (failure surfaced / dup pattern / ad-hoc fix tempting / "out of scope" framing) / Go code-quality / CLAUDE.md-compliance audit / `golangci-lint` / `dupl` / duplication or dead-code check / `.golangci.yml` | `/charly-internals:strict-policy` |
| `charly update` / `charly vm *` / VM entities in `vm.yml` or `vm:` | `/charly-internals:vm-deploy-target` |
| VmSpec / libvirt / cloud-init / OVMF internals | `/charly-internals:vm-spec` |
| the `kube:` check verb / Kubernetes cluster probing from a candy/box plan (out-of-process plugin; nodes, pods, ingress, wait-ready, storageclass, addons, apply/delete, raw resource GETs) | `/charly-kubernetes:check-k8s` |
| `step:helm-release` / `verb:helm` / installing a Helm chart from a candy plan / the `helm_charts:` deploy field and its kustomize `helmCharts:` emission / the `--enable-helm` apply path | `/charly-kubernetes:helm` |
| CachyOS images / `cachyos*` / `charly-cachyos` workstation profile / `box/cachyos` submodule | `/charly-local:charly-cachyos` |
| local-target deploy / `target: local` / `host: local` (default) / SSH-host deploys / `user:` / `ssh_arg:` / Managed `~/.config/charly/ssh_config` fragment / `charly vm create` writes Host stanza | `/charly-local:local-deploy` |
| Editing `local.yml` / authoring `kind: local` templates | `/charly-local:local-spec` |
| `charly pipeline` / agent workflow engine / kind:pipeline / pipeline run | `/charly-pipeline:pipeline` |
| `charly cp` / copy a file into a container / copy out of a container / podman cp | `/charly-pod-verbs:cp` |
| `charly restart` / restart a deployment / cycle a container | `/charly-pod-verbs:restart` |
| `charly volume` / list a deployment's volumes / reset a volume / wipe sidecar state / podman volume | `/charly-pod-verbs:volume` |
| punktfunk / game streaming host / Moonlight-compatible host / `punktfunk-host` units | `/charly-punktfunk:punktfunk-host` |
| `charly review` / review a PR / PR verdict / review plan | `/charly-review:review` |
| `charly docs` / the opencharly.ai site / the opencharly/docs repo / `candy/docs-site` / the check-docs bed / Starlight/Astro | `/charly-tools:docs-site` |
| CachyOS images / `cachyos*` / `charly-cachyos` workstation profile / `box/cachyos` submodule | `/charly-vm:cachyos-bootstrap-vm` |
| Debian images / `debian*` / `box/debian` submodule | `/charly-vm:debian-debootstrap-vm` |
| omarchy VMs / `omarchy-vm` / `charly-omarchy` / `source.kind: iso` / unattended archinstall | `/charly-vm:omarchy-vm` |
| Ubuntu images / `ubuntu*` / `box/ubuntu` submodule | `/charly-vm:ubuntu-debootstrap-vm` |
| `charly update` / `charly vm *` / VM entities in `vm.yml` or `vm:` / Managed `~/.config/charly/ssh_config` fragment / `charly vm create` writes Host stanza | `/charly-vm:vm` |
<!-- END GENERATED SKILL DISPATCHER -->
