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
| `charly migrate` / schema migration / legacy config shape / migration table / adding a migration step | `/charly-build:migrate` |
| `charly box reconcile` / cross-repo `@github` pin alignment / candy-version-mismatch cleanup | `/charly-build:reconcile` |
| Secret management / `charly secrets` / Secret Service / GPG `.secrets` | `/charly-build:secrets` |
| `charly box validate` / schema error | `/charly-build:validate` |
| `charly cache` / git-ref cache / stale @github ref resolution / pinned ref won't advance | `/charly-cache:cache` |
| `charly candy` / candy set / candy add-pac/add-deb/add-rpm / edit a candy manifest / candy params / regenerate a plugin's params / cue_types_gen.go / regenerating a candy params package, or a CI drift gate for a generated cue_types_gen.go | `/charly-candy-cli:candy` |
| `charly cardwire` / cardwire GPU manager / GPU block/unblock / cardwired | `/charly-cardwire:cardwire` |
| the `adb:` check verb / Android Debug Bridge probing from a candy/box plan (out-of-process plugin; devices, shell, install, getprop, screencap, logcat, wait-for-device) | `/charly-check:adb` |
| `kind: android` device / `target: android` deploy / `apk:` package format in candies / installing Android apps declaratively / remote-or-emulator adb endpoint / nested `pod → android` | `/charly-check:android` |
| the `appium:` check verb / Android UI automation (out-of-process plugin) / W3C WebDriver sessions, element introspection, the gesture/app/key/device sugar groups, the generic `execute`/`raw` escape hatch | `/charly-check:appium` |
| the `cdp:` check verb / Chrome DevTools Protocol browser automation from a candy/box plan (out-of-process plugin plugin-cdp; connect to port 9222, navigate, click, screenshot, evaluate, OAuth flows inside containers) | `/charly-check:cdp` |
| `charly check *` (ANY check verb, incl. `charly check box`) / `charly check run <bed>` (the disposable-deploy R10 bed) / authoring `disposable: true` check beds / `charly check live` / the probe verbs (cdp/wl/dbus/vnc/mcp/record/spice/libvirt) / `iterate:` AI-agent scoring / `plan:` step authoring / `charlycheck/*` branches / Agent Driven Evaluation (ADE) / `charly box feature run` / `charly check feature run` / `charly feature list/pending/validate` / authoring a candy's `plan:` + `description:` string / the agent grader for `agent-check:` steps / the `adb:` check verb / Android Debug Bridge probing from a candy/box plan (out-of-process plugin; devices, shell, install, getprop, screencap, logcat, wait-for-device) / the `jetkvm:` check verb / IP-KVM control from a candy/box plan (out-of-process plugin; status, screenshot, keyboard/mouse, power/ATX, virtual media, USB, device config) / the `appium:` check verb / Android UI automation (out-of-process plugin) / W3C WebDriver sessions, element introspection, the gesture/app/key/device sugar groups, the generic `execute`/`raw` escape hatch / Verify a cutover by running the R10 beds (drive `charly check run <bed>`) / Evaluate/audit a deployment config (image or deploy, yours) | `/charly-check:check` |
| the DISPOSABLE `check-sway-browser-vnc-pod` bed / the live-container R10 gate for the Sway desktop verb surface (cdp / wl / vnc / dbus / mcp / record) on the shipping sway-browser-vnc image — reach for it when running or maintaining that bed, or when a change touches the Sway verb surface | `/charly-check:check-sway-browser-vnc` |
| driving a text console by screenshot + OCR + keyboard / console installer / first-boot provisioning / a shell command over a KVM or VM console / open a terminal on a remote machine / run a command and read its output via OCR / sudo over a console / enter a LUKS passphrase at the initramfs prompt / continuous OCR-until-condition / named outcomes / if-then-else / case-switch / bounded while over a console / the `flow` method / set the UEFI boot order from inside the OS / efibootmgr / boot-order / boot the installer medium once via --bootnext / generic console actions shared between JetKVM and VM (SPICE) / `sdk/kit` ConsoleSession, ConsoleFlow, ConsoleTransport | `/charly-check:console-automation` |
| the `crabbox:` check verb / probing the Crabbox CLI or coordinator from a candy or box plan | `/charly-check:crabbox` |
| the `cua:` check verb / driving a live desktop through Cua Driver from a candy/box plan (out-of-process plugin; status, list-apps, list-windows, get-window-state, screenshot, click, type, key, hotkey, launch-app, recording) / a `kind: cua` entity / Cua Driver connection + permission defaults (permission_mode standard bounded unrestricted, driver path, session env) / the allow_control desktop-safety gate / foreground vs background delivery / a Cua Fleet image / a KubeVirt containerDisk / the `container_disk` VM source (pull a bootable guest disk from OCI and boot it locally) / the layer-cua candies (cua-driver, cua-session, cua-computer-server, cua-guest, cua-hyprland-plugin) | `/charly-check:cua` |
| the `dbus:` check verb / D-Bus interaction inside a container from a candy/box plan (out-of-process plugin plugin-dbus; EXEC-based gdbus over the executor reverse channel — session and system bus, method calls, property get/set, introspection, desktop notifications) | `/charly-check:dbus` |
| the `jetkvm:` check verb / driving a JetKVM IP-KVM from a candy/box plan (out-of-process plugin; status, screenshot, ocr, keyboard/mouse, power, virtual media, USB, device config) / a `kind: jetkvm` device entity / the `install` method / console-installer recipe / driving an OS installer (e.g. Omarchy) remotely over a KVM / wait-for-screen OCR / opening a terminal on a remote machine over a KVM/VM console / running a shell command and reading its output via OCR / `run-command` / `open-terminal` / `close-terminal` / sudo with a password / entering a LUKS disk-encryption passphrase / `luks-unlock` / continuous OCR-until-condition / named outcomes / if-then-else / case-switch / bounded while loop over a console / the `flow` method / setting the UEFI boot order from inside the OS / `efibootmgr` / `boot-order` / generic console actions shared between JetKVM and VM (SPICE) / `sdk/kit` ConsoleSession + ConsoleFlow / `kit.ConsoleTransport` / installing charly on a JetKVM / `charly-jetkvm` / running charly on the armv7 appliance / why there is no MCP server on the JetKVM | `/charly-check:jetkvm` |
| the `libvirt:` check verb / libvirt-RPC probing of a VM from a candy/box plan (out-of-process plugin plugin-vm; domain info, framebuffer screenshots, send-key, passwd, QMP, qemu-guest-agent client, snapshots, lifecycle events) | `/charly-check:libvirt` |
| the `punktfunk:` check verb / probing or managing a punktfunk streaming host from a candy or box plan | `/charly-check:punktfunk` |
| the `record:` check verb / capturing terminal or desktop evidence from a candy/box plan (out-of-process plugin plugin-record; asciinema terminal casts, pixelflux/wf-recorder desktop video, session capture) | `/charly-check:record` |
| the `spice:` check verb / SPICE-wire interaction with a VM from a candy/box plan (out-of-process plugin plugin-spice; handshake, native-SPICE display screenshots, keyboard/mouse input injection) | `/charly-check:spice` |
| the `transcode:` pipeline verb / MJPEG to MP4 capture-evidence transcode / instrument `pipeline:` word | `/charly-check:transcode` |
| the `vnc:` check verb / VNC-RFB desktop automation from a candy/box plan (out-of-process plugin plugin-vnc, pod AND vm targets; connect, authenticate, screenshot, click coordinates, type, RFB protocol interaction) | `/charly-check:vnc` |
| Debian images / `debian*` / `box/debian` submodule | `/charly-coder:debian-coder` |
| Fedora images / `fedora*` / `box/fedora` submodule (incl. the GPU base `nvidia` / `python-ml` + `sway-browser-vnc`) | `/charly-coder:fedora-coder` |
| Ubuntu images / `ubuntu*` / `box/ubuntu` submodule | `/charly-coder:ubuntu-coder` |
| `charly clean` / build-artifact retention / `keep_images` / `keep_check_runs` / image-tag pruning / `.check` run cleanup | `/charly-core:clean` |
| `charly deploy add/del` / pod or container deploys / `kind: android` device / `target: android` deploy / `apk:` package format in candies / installing Android apps declaratively / remote-or-emulator adb endpoint / nested `pod → android` / Disposable-flag semantics / `disposable: true` authorization / preemptible-flag / `requires_exclusive:` / `charly preempt` / exclusive host-resource arbitration (GPU passthrough contention) | `/charly-core:deploy` |
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
| `external_builder: mise` / the `mise:` plan-step verb / provisioning the mise dev-tool manager into an image | `/charly-image:mise` |
| Verify a cutover by running the R10 beds (drive `charly check run <bed>`) / Evaluate/audit a deployment config (image or deploy, yours) / Sub-agents / dynamic workflows / agent teams / agent-lifecycle or commit-push gate hooks / Monitor a subagent's progress / stop a stalled, idle, or looping worker / Todo ledger / interruption safety / never drop in-flight work across a new instruction | `/charly-internals:agents` |
| OCI labels / capabilities contract | `/charly-internals:capabilities` |
| Hard-cutover concerns / rename sweeps | `/charly-internals:cutover-policy` |
| Disposable-flag semantics / `disposable: true` authorization / preemptible-flag / `requires_exclusive:` / `charly preempt` / exclusive host-resource arbitration (GPU passthrough contention) | `/charly-internals:disposable` |
| Egress config validation — validating/generating the config files charly WRITES to a system (`candy/plugin-fleet/egress.go`, `ValidateEgress`, the vendored CUE egress schemas in `candy/plugin-egress/egress-schemas/vendor/`, cloud-init/k8s_object/units/ssh_config/libvirt-XML egress) | `/charly-internals:egress` |
| `charly box build` / `charly box generate` / Containerfile | `/charly-internals:generate-source` |
| Git/`gh` workflow — `feat/` branch, commit, PR-only landing (NO direct push to main), branch protection, the `pr-validator` fresh-evaluator gate, native auto-merge + tag-on-merge CalVer-at-merge, worktree, sync-to-upstream, branch/worktree prune, cross-repo R10 landing | `/charly-internals:git-workflow` |
| Go source work (adding/modifying `charly` commands) / Editing `sdk/schema/*.cue` / `charly task cue-gen` / `cue exp gengotypes` / generated `cue_types_gen.go` / Schema Driven Design (SDD) / a schema spike | `/charly-internals:go` |
| Go code-quality / AGENTS.md-compliance audit / `golangci-lint` / `dupl` / duplication or dead-code check / `.golangci.yml` | `/charly-internals:go-quality` |
| IR / InstallPlan / EmitTarget / OCITarget | `/charly-internals:install-plan` |
| local-target deploy / `target: local` / `host: local` (default) / SSH-host deploys / `user:` / `ssh_arg:` | `/charly-internals:local-infra` |
| Marketplace / skill-corpus generation — `charly marketplace generate`, the refs list (candy/charly-marketplace/charly.yml), the drift gate, the daily refresh PRs, per-harness vendoring, or 'my skill is stale' | `/charly-internals:marketplace` |
| Authoring a plugin (a candy with a `plugin:` block) / builtin vs out-of-tree plugin / per-plugin `.cue` schema (single source → `gengotypes` for dev + schema-over-`Describe` RPC at runtime) / the plugin SDK (`github.com/opencharly/sdk`, the proxy-resolved contract module — no submodule) / `sdk/**` / a compiled-in plugin candy (`compiled_plugins:`) or host-coupled kit candy / an external plugin module / Editing `sdk/schema/*.cue` / `charly task cue-gen` / `cue exp gengotypes` / generated `cue_types_gen.go` / Schema Driven Design (SDD) / a schema spike | `/charly-internals:plugin` |
| Set up a new repository in the opencharly org (required workflows, ruleset, auto-merge, CalVer tags) / How the org ruleset / dotgithub workflows / native auto-merge / tag-on-merge CalVer work | `/charly-internals:repo-setup` |
| Skill authoring / skill maintenance / where does this doc content belong | `/charly-internals:skills` |
| Agent Driven Evaluation (ADE) / `charly box feature run` / `charly check feature run` / `charly feature list/pending/validate` / authoring a candy's `plan:` + `description:` string / the agent grader for `agent-check:` steps / Engineering-discipline triggers (failure surfaced / dup pattern / ad-hoc fix tempting / "out of scope" framing) / Go code-quality / AGENTS.md-compliance audit / `golangci-lint` / `dupl` / duplication or dead-code check / `.golangci.yml` | `/charly-internals:strict-policy` |
| `charly update` / `charly vm *` / VM entities in `vm.yml` or `vm:` | `/charly-internals:vm-deploy-target` |
| VmSpec / libvirt / cloud-init / OVMF internals | `/charly-internals:vm-spec` |
| the `kube:` check verb / Kubernetes cluster probing from a candy/box plan (out-of-process plugin; nodes, pods, ingress, wait-ready, storageclass, addons, apply/delete, raw resource GETs) | `/charly-kubernetes:check-k8s` |
| `step:helm-release` / `verb:helm` / installing a Helm chart from a candy plan / the `helm_charts:` deploy field and its kustomize `helmCharts:` emission / the `--enable-helm` apply path | `/charly-kubernetes:helm` |
| kind (Kubernetes-in-Docker) / kindcluster deploy / local Kubernetes-in-Docker / a kind cluster on docker-podman-nerdctl / KIND_EXPERIMENTAL_PROVIDER / composing the kind candy | `/charly-kubernetes:kind` |
| the `kubevirt:` check verb / probing a running KubeVirt cluster from a candy/box plan (vm / vmi / wait-ready / guest-info / migration / snapshot / datavolume) | `/charly-kubevirt:check-kubevirt` |
| KubeVirt / `kind: kubevirt` / a `kubevirt:` or `target: kubevirt` deploy / `deploy:kubevirt` / running a charly VM on a Kubernetes cluster / `charly kubevirt` CLI (build/create/start/stop/restart/destroy/console/ssh/snapshot/migrate/gpu/status) / the VirtualMachine CR lifecycle | `/charly-kubevirt:kubevirt` |
| installing KubeVirt + CDI on a cluster / `candy/kubevirt-operator` / the kubevirt platform leg of a check bed | `/charly-kubevirt:kubevirt-operator` |
| CachyOS images / `cachyos*` / `charly-cachyos` workstation profile / `box/cachyos` submodule | `/charly-local:charly-cachyos` |
| local-target deploy / `target: local` / `host: local` (default) / SSH-host deploys / `user:` / `ssh_arg:` / Managed `~/.config/charly/ssh_config` fragment / `charly vm create` writes Host stanza | `/charly-local:local-deploy` |
| Editing `local.yml` / authoring `kind: local` templates | `/charly-local:local-spec` |
| `charly pipeline` / agent workflow engine / kind:pipeline / pipeline run | `/charly-pipeline:pipeline` |
| `charly cp` / copy a file into a container / copy out of a container / podman cp | `/charly-pod-verbs:cp` |
| `charly restart` / restart a deployment / cycle a container | `/charly-pod-verbs:restart` |
| `charly volume` / list a deployment's volumes / reset a volume / wipe sidecar state / podman volume | `/charly-pod-verbs:volume` |
| punktfunk / game streaming host / Moonlight-compatible host / `punktfunk-host` units | `/charly-punktfunk:punktfunk-host` |
| qdrant server / vector search / the qdrant candy (`candy/qdrant`) / the qdrant pod / the `qdrant:` check verb / `charly qdrant` CLI / REST 6333 / gRPC 6334 / QDRANT__SERVICE__API_KEY | `/charly-qdrant:qdrant` |
| `charly qdrant` CLI (collections / points / snapshots / health / version) / the `qdrant:` check verb / the check-qdrant-pod bed / the qdrant box | `/charly-qdrant:qdrant-cli` |
| `charly review` / review a PR / PR verdict | `/charly-review:review` |
| `charly docs` / the opencharly.ai site / the opencharly/docs repo / `candy/docs-site` / the check-docs bed / Starlight/Astro | `/charly-tools:docs-site` |
| The dsh / DeepSeek Harness CLI or web UI, the `dsh` / `dsh-web` candies, `~/.dsh`, the dsh web UI's launch-token + Host/Origin trust fence, `--trusted-host`, exposing dsh web over Tailscale (`tailscale serve`), or `charly dsh status` web health | `/charly-tools:dsh` |
| `charly dsh` (status / profile list / plugin list) against a running deepseek-harness deployment, the compiled-in command:dsh plugin, or the `dsh:` check verb | `/charly-tools:dsh-cli` |
| The dsh-TUI / dsh-tui terminal UI plugin (`@deepseek-harness-tui/dsh-tui`), the `dsh-tui` / `dst` launcher, the `dsh-tui` dsh profile, `DSH_TUI_NO_LAUNCHPAD`, the terminal:tmux channel, or the check-dsh-tui-pod bed | `/charly-tools:dsh-tui` |
| the airflow layer / Apache Airflow 3.x (LocalExecutor + SQLite; supervisord init/scheduler/dag-processor/webserver services) — Airflow DAG authoring, the Airflow REST API, the SimpleAuthManager pattern, or the dag-processor split-from-scheduler architecture | `/charly-versa:airflow-layer` |
| the debug-tools layer / in-container service debugging — network probes (ip/ss/lsof/ping/dig/nc/socat/tcpdump/traceroute/mtr/wget), process inspection (ps/top/htop/pgrep/strace/free/vmstat), file inspection, or the per-distro package-name divergence (nmap-ncat vs ncat vs gnu-netcat) | `/charly-versa:debug-tools-layer` |
| the maputnik layer / the Maputnik visual editor for MapLibre GL vector-tile styles (npm-built SPA served as a static dist by python -m http.server; the Vite --base=/ build override; the asset-base lock-in check) | `/charly-versa:maputnik-layer` |
| the marimo layer / the reactive notebook server + MCP runtime, its pixi environment (cudf-polars-cu13, polars, geopandas, quackosm, gtfs-parquet), the supervisord service spec, or the cell-display + mo.iframe rendering patterns | `/charly-versa:marimo-layer` |
| the marimo MCP server on port 2718 path /mcp/server (get_active_notebooks, get_cell_outputs, get_notebook_errors) — the marimo MCP tool catalog, or the cells-don't-execute-via-MCP gap (marimo MCP is read-only) | `/charly-versa:marimo-mcp` |
| the OSM data pipeline tooling (tippecanoe, gdal/ogr2ogr, martin on port 3000, the pmtiles CLI), martin reading tiles from /workspace/tiles/pmtiles/, the martin data-source cache restart pattern, or vector-tiles-only MapLibre output | `/charly-versa:osm-tools-layer` |
| the versa/ecovoyage tailnet sway-browser-vnc instance — chrome-devtools-mcp + CDP debugging of the generated MapLibre and folium maps | `/charly-versa:sway-browser-ecovoyage` |
| CachyOS images / `cachyos*` / `charly-cachyos` workstation profile / `box/cachyos` submodule | `/charly-vm:cachyos-bootstrap-vm` |
| Debian images / `debian*` / `box/debian` submodule | `/charly-vm:debian-debootstrap-vm` |
| omarchy VMs / `omarchy-vm` / `charly-omarchy` / `source.kind: iso` / unattended archinstall | `/charly-vm:omarchy-vm` |
| Ubuntu images / `ubuntu*` / `box/ubuntu` submodule | `/charly-vm:ubuntu-debootstrap-vm` |
| `charly update` / `charly vm *` / VM entities in `vm.yml` or `vm:` / Managed `~/.config/charly/ssh_config` fragment / `charly vm create` writes Host stanza | `/charly-vm:vm` |
<!-- END GENERATED SKILL DISPATCHER -->
