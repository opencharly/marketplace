---
name: go
description: |
  Go CLI development: building the charly binary, running tests, understanding
  the source code structure. Owns the Schema Driven Design (SDD)
  operationalization — the sdk/schema/*.cue → `task cue:gen` generation pipeline
  and the generation-coverage current state.
  MUST be invoked before reading or modifying any Go source file in charly/
  or any sdk/schema/*.cue schema file.
---

# Go - CLI Development

## Overview

The `charly` CLI is a Go program in the `charly/` directory. It uses the Kong CLI framework, go-containerregistry for OCI operations, and YAML parsing for configuration. All computation, validation, and building logic lives in Go. Taskfiles are used only for bootstrapping (building charly itself).

## Reference Index

| Topic | File |
|---|---|
| Architecture deep dives (unified YAML loader, Schema Driven Design pipeline + generation-coverage catalog, the `sdk/spec` package, namespace/remote-layer resolvers, Capabilities, the k8s/VM external substrates, YAML↔Go conventions, Kong parent+leaf commands, mode purity, the InstallPlan IR, the VM-path module topology, self-exec coordination) and the full file-by-file Source Code Map | `references/source-map.md` |
| The step-by-step recipe for changing the `charly.yml` schema (CUE is the single source of truth) | `references/schema-change-recipe.md` |
| Design notes for the Go-side architecture not obvious from reading the source cold (Kong flag-namespace collision, env-var proxy for parent-flag detection, the `yaml.v3` Node API, scalar-to-sequence upgrades, the path-traversal guard, the two-step project-dir resolver) | `references/implementation-insights.md` |

## Quick Reference

| Action | Command | Description |
|--------|---------|-------------|
| Build | `task build:binary` | Compile to `bin/charly` (CalVer-stamped), NO install. Also copies to `candy/charly/bin/charly` — does NOT touch the tracked `pkg/arch/PKGBUILD` (that file is read only by the containerized `charly box pkg` native-package build) |
| Package | `task pkg:arch` / `pkg:fedora` / `pkg:debian` / `pkg:all` | Build a distro-native `.pkg.tar.zst`/`.rpm`/`.deb` release artifact into `dist/`, containerized via `charly box pkg`. Install it yourself with your OWN package manager (`pacman -U`/`dnf install`/`apt install`) |
| Install (portable) | `task install-portable` | Copy `bin/charly` to `$HOME/.local/bin/charly` (solo bootstrap; NOT a multi-teammate dev-loop step — see below) |
| Run tests | `cd charly && go test ./...` | Run all tests |
| Run specific test | `cd charly && go test -run TestName ./...` | Run single test |
| Vet | `cd charly && go vet ./...` | Static analysis |
| Format | `cd charly && gofmt -w .` | Format code |

In a multi-teammate / multi-worktree setup, NO Taskfile target installs to the
host during in-flight work — use `task build:binary` per worktree instead; see
`/charly-internals:agents` "The charly binary in a multi-teammate /
multi-worktree setup" for the full discipline.

## Project Directory Structure

```
project/
├── bin/charly                     # Built by `task build:binary` (gitignored)
├── charly/                        # Go module (kong CLI, go-containerregistry)
│   └── charly.yml             # The binary's embedded default config (//go:embed,
│                              # embed_defaults.go): distro/builder/init/resource
│                              # build vocabulary + the sidecar: template library.
│                              # Parsed by the SAME unified loader as any project
│                              # charly.yml; a project ships none of it.
├── sdk/                       # Git submodule (github.com/opencharly/sdk) — the plugin
│                              # contract module: root package sdk, sdk/kit, sdk/spec,
│                              # sdk/proto, sdk/schema/*.cue, sdk/schemaconcat, sdk/vmshared;
│                              # its own Taskfile owns `task cue:gen` + `task proto:gen`
├── .build/                    # Generated Containerfiles (gitignored)
├── charly.yml                  # Image definitions
├── Taskfile.yml               # Bootstrap tasks only
├── taskfiles/                 # Build.yml, Cue.yml, Setup.yml
├── candy/<name>/             # Layer directories (160 layers)
├── plugins/                   # Git submodule (opencharly/plugins)
└── templates/                 # supervisord.header.conf (referenced by init.supervisord.header_file)
```

Submodule convention: `plugins/` is a submodule rooted at the
`opencharly/plugins` repo, and `sdk/` is a submodule rooted at the
`github.com/opencharly/sdk` repo. Clone with `--recurse-submodules` or run
`git submodule update --init` after a plain clone. See
`/charly-internals:skills` for the skill-authoring and sync conventions.

## Go Module Info

- Go version: 1.26.0
- Key dependencies: `kong` (CLI), `go-containerregistry` (OCI), and `github.com/opencharly/sdk` (the plugin contract module — required with `replace github.com/opencharly/sdk => ../sdk` for in-tree resolution). The credential store's `go-keyring` (Secret Service API) is NOT a core dependency — it links only into the out-of-process `candy/plugin-secrets` plugin (the C2 dep-shed)
- Module path: `charly/go.mod`

## Common Workflows

### Add a New CLI Command

1. Define command struct in appropriate file (or new file)
2. Add to CLI struct in `main.go`
3. Implement `Run()` method
4. Add tests in `*_test.go`
5. Build and test: `cd charly && go test ./... && go build -o ../bin/charly .`

### Add a New Validation Rule

A host-natural check that needs the raw loader goes in `charly/validate.go`; the
per-kind/op/candy/graph rule engine lives in the compiled-in `command:box` plugin
(`candy/plugin-box`) over the resolved-project envelope — add per-entity/op rules
there.

See `references/schema-change-recipe.md` for the full recipe when the change touches the `charly.yml` schema itself (CUE is the single source of truth).

### Debug a Build Issue

```bash
# Generate Containerfiles without building
bin/charly box generate

# Inspect generated output
cat .build/<image>/Containerfile

# Validate configuration
bin/charly box validate

# Inspect resolved image config
bin/charly box inspect <image>
```

### Intermediate image cache invalidation

`charly box build` auto-generates intermediate images (e.g., `ghcr.io/opencharly/charly-fedora-2-dbus-nodejs`) that bundle the `charly` layer plus common layers for cache reuse across many downstream images. These intermediates are aggressively podman-cached. Updating `candy/charly/bin/charly` does invalidate the COPY step inside the intermediate, but if the intermediate tag already exists locally, `charly box build` may reuse it without re-running the build chain. To force a fresh binary propagation after a manual `bin/charly` update:

```bash
charly clean --invalidate 'charly-fedora-2*'
charly box build <image>
```

This also interacts with the dual-path gotcha documented in `/charly-tools:charly`: `bin/charly` (repo-root, used by host-side invocations) and `candy/charly/bin/charly` (what the `charly` candy actually copies into images) must stay in sync. The canonical `task build:binary` path does both; a manual `go build -o bin/charly ./charly` needs an explicit `cp bin/charly candy/charly/bin/charly` follow-up.

## R9 — deployed binary matches source; runtime deps live in the PKGBUILD

See the project rulebook's R9 mandate (`CLAUDE.md`/`AGENTS.md`). Applied to the `charly` toolchain:

- **Syncing source does not rebuild the binary.** Syncthing / git / rsync move
  *source* between hosts. After pushing code, rebuild on the target — `task
  build:binary` in that checkout — and verify `./bin/charly version` matches what
  you built — if the version is old, the fix under test isn't really under test.
  The freshness guard (`/charly-internals:agents` "The charly binary in a
  multi-teammate / multi-worktree setup") catches a stale invoked binary against
  newer `charly/*.go` in the same tree, but the version check is still the
  explicit proof — the per-worktree-vs-host-package split lives there too.
- **Every runtime OS dependency goes into `pkg/arch/PKGBUILD` `depends=`** —
  the single source of truth (`nc`, `socat`, `xorriso`, `qemu-guest-agent`, …);
  the `pkg/fedora` / `pkg/debian` packaging mirrors it. A manual install on one
  host is a bug report disguised as a fix — it won't survive a fresh install on
  a synced host.

The verification side (checking the deployed binary + deps on a live target)
is `/charly-check:check` Standards 7–9; the dual-path `bin/charly` ↔
`candy/charly/bin/charly` gotcha is above and in `/charly-tools:charly`.

## Style Guide

- All logic belongs in Go. Taskfiles are only for bootstrap (building charly).
- Taskfiles for bootstrap only, Go for all other logic.
- Test files alongside source files (`foo.go` -> `foo_test.go`).

## Cross-References

- `/charly-internals:generate-source` — Understanding generated Containerfiles + deep dive on the task emission pipeline (`charly/tasks.go`).
- `/charly-image:layer` — **Canonical author-facing reference** for the task verb catalog that `charly/tasks.go` implements.
- `/charly-build:validate` — Validation rules and error handling (`validateCandyTasks` in `candy/plugin-box/validate_rules.go`).
- `/charly-build:build` — Using the built CLI.
- `/charly-check:check` — Author-facing reference for the declarative-testing feature that `checkspec.go` / `checkrun.go` / `checkrun_verbs.go` / `checkrun_charly_verbs.go` / `description_collect.go` / `check_cmd.go` / `check_endpoint_resolve.go` (the host-endpoint reverse-legs) implement — plus `sdk/kit/checkvars.go` and `sdk/kit/local_image.go` (moved out of core in P12a). (Op-level check validation moved out of core to `candy/plugin-box/validate_check.go`.)
- `/charly-build:charly-mcp-cmd` — Author-facing reference for both (a) the declarative `mcp:` client check verb (method catalog, URL-rewrite behavior, port-publishing gotcha, transport dispatch — served out-of-process by `candy/plugin-mcp`, which resolves its endpoint via the `check_endpoint_resolve.go` reverse-legs) and (b) the `charly mcp serve` server (externalized to `candy/plugin-mcp` `command:mcp`: one tool per CLI leaf, auto-generated from the `charly __cli-model` reflection seam, destructive-hint + `--read-only` filter, Streamable-HTTP + stdio transports, auto-fallback to `opencharly/charly` — pair with `cli_model_cmd.go` + `main_repo.go` + `box_fetch_reentry.go` + `candy/plugin-authoring` + `sdk/kit/yaml.go` in `references/source-map.md`).
- `/charly-coder:charly-mcp` — The candy that deploys `charly mcp serve` inside a container: bind-mount volume NAME `project` at the container PATH `/workspace`, `CHARLY_PROJECT_DIR=/workspace` so build-mode MCP tools (`box.list.boxes`, `box.inspect`, etc.) reach `charly.yml` from outside the project checkout — or auto-fall back to `opencharly/charly` when `/workspace` is empty (the fallback fires on absence of charly.yml, not absence of CHARLY_PROJECT_DIR).
- `/charly-check:wl`, `/charly-check:cdp`, `/charly-check:vnc`, and `/charly-check:dbus` are out-of-process verbs served by `candy/plugin-wl` / `candy/plugin-cdp` / `candy/plugin-vnc` / `candy/plugin-dbus` (cdp/vnc resolve their endpoints via the `check_endpoint_resolve.go` reverse-legs; `wl`/`dbus` are EXEC-based and reach the venue over the executor).
- Source: `charly/` directory (~304 source + ~294 test .go files).

## When to Use This Skill

**MUST be invoked** before reading or modifying Go source files. Invoke this skill BEFORE launching Explore agents on charly/ code.

Live-deploy verification: see `/charly-check:check` (the 11 Testing Standards) and `/charly-internals:disposable`.
