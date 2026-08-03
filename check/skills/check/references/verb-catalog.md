# Verb catalog — deterministic checks, matchers, runtime variables, overlays

Full detail for `/charly-check:check`: the deterministic (non-live-container) check-verb catalog, the shared matcher/modifier vocabulary, execution routing, runtime variables, and the `charly.yml` overlay + workflow surface.

## Authoring: the plan (the ordered `plan:` list)

Every step is an entry in the entity's ordered `plan:` list — ONE intent keyword
(`run:`/`check:`/`agent-run:`/`agent-check:`/`include:`) carrying prose, plus —
for `run:`/`check:` — at most one verb-position key (a builtin install verb, or
the plugin-verb sugar `<word>: <input>`: a map is the verb's input verbatim,
holding the verb-specific attributes; a scalar is the verb's primary-field
shorthand) and the shared step modifiers as siblings. An optional `id:` names a
step (reports + overlay merging), mirroring `candy/redis/charly.yml`. `run:`
steps ARE the install timeline; `check:` steps are the deterministic idempotent
probes `charly check`/`charly check live` run.

### Gold-standard pattern (redis candy)

```yaml
# candy/redis/charly.yml — the ordered plan: list inline in the candy body.
redis:
    candy:
        version: 2026.144.1531
        description: A Redis-compatible key-value server supervised on 127.0.0.1:6379
        plan:
            # Build-context check: — run inside the built image via `podman run --rm`.
            - check: the redis-server binary is installed
              file:
                  file: /usr/bin/redis-server
                  exists: true
            - check: the redis-cli binary is installed
              file:
                  file: /usr/bin/redis-cli
                  exists: true
            - check: the providing package is installed
              package:
                  package: valkey-compat-redis   # see references/authoring-gotchas.md #8 on renames
                  package_map:
                      arch: valkey
                  installed: true
            # Runtime check: — HOST_PORT:N resolves to the effective port mapping, so
            # the same step works whether the deploy publishes 6379:6379 or 16379:6379.
            - check: redis answers ping over the published port
              id: redis-responds
              context: [runtime]
              stdout: PONG                       # shared matcher — a step-level sibling
              command:
                  command: redis-cli -h 127.0.0.1 -p 6379 ping
                  in_container: true
            - check: the redis port is reachable from the host
              id: redis-port-open
              context: [runtime]
              addr: 127.0.0.1:${HOST_PORT:6379}  # scalar sugar: addr's primary field
```

The five `check:` steps cover: binary existence, package identity, a functional
live probe, and raw TCP reachability. Adopt this shape for any primary
service layer.

### Cross-distro package names (`package_map:`)

The `package:` verb chains `rpm -q || dpkg -s || pacman -Q` with a single
literal name, so a test that works on Fedora (`openssh-server`) fails on
Arch (where the package is just `openssh`). `package_map:` is the
authoring hook: the first key that matches any of the image's
`distro:` tags wins; otherwise the `package:` scalar is used as the
fallback. Source: `charly/checkrun_charly_verbs.go:resolvePackageName` + the
`Runner.Distros` field wired from `meta.Distro` at both test entry
points.

```yaml
# candy/sshd/charly.yml — cross-distro authoring (a plan: step; the package-verb
# fields, package_map included, live INSIDE the package input map)
plan:
    - check: the openssh-server package is installed
      id: openssh-server-package
      package:
          package: openssh-server          # Fedora / Debian default
          package_map:
              arch: openssh                # Arch ships the metapackage as 'openssh'
              fedora: openssh-server
              fedora:43: openssh-server    # explicit version tag — matches before 'fedora'
          installed: true
```

Tag priority: entries in `distro:` are in priority order (e.g.
`["fedora:43", fedora]`), so `package_map:` can be keyed on either the
version-specific or the family tag, and the more-specific tag wins
naturally. An empty-string map value falls through to the next tag
(see `TestResolvePackageName` in `charly/checkrun_verbs_test.go`).

### Verb catalog (goss-parity feature set)

Every verb-exclusive attribute below lives inside the verb's input map
(`file: {file: /x, exists: true}`), validated by the plugin's own served CUE
schema; a scalar value is the verb's primary-field shorthand (`file: /x`,
`command: id`, `cdp: status`, …). The shared step modifiers and the
`stdout`/`stderr`/`exit_status` matchers stay step-level siblings.

| Verb | Input attributes (inside the verb map) | Notes |
|------|---------------------|-------|
| `file` | `file` (primary), `exists`, `mode`, `owner`, `group_of`, `filetype`, `contains`, `sha256` | `group_of` (not `group`) — `group` is a reserved kind word, so the owning-group attribute is spelled `group_of` (the getent-group probe verb is `unix_group`) |
| `package` | `package` (primary), `installed`, `version`, `package_map` | Tries rpm / dpkg / pacman — exact match on installed name (see `references/authoring-gotchas.md` #8) |
| `service` | `service` (primary), `running`, `enabled` | Supervisord first, then systemd |
| `port` | `port` (primary), `listening`, `ip`, `reachable` | `listening` needs `ss`/`netstat` inside the container — absent from minimal images |
| `process` | `process` (primary), `running` | Needs `pgrep` — absent from minimal images |
| `command` | `command` (primary), `in_container` | Default runs via `podman exec`; set `in_container: false` to run from host. Assert via the shared `exit_status`/`stdout`/`stderr` step matchers |
| `http` | `http` (primary URL), `status` (int, single value), `body`, `headers`, `method`, `request_body`, `allow_insecure`, `no_follow_redirects`, `ca_file`, `timeout` | Host-side under `charly check live`; curl-in-container under `charly check box` |
| `dns` | `dns` (primary), `resolvable`, `addrs`, `server` | Host resolver for `charly check live`; `getent hosts` for `charly check box` |
| `user` | `user` (primary), `uid`, `gid`, `home`, `shell` | `getent passwd` |
| `unix_group` | `unix_group` (primary), `gid`, `groups` | `getent group` |
| `interface` | `interface` (primary), `mtu`, `addrs` | `ip -o addr show` |
| `kernel-param` | `kernel-param` (primary), `value` (scalar or matcher) | `sysctl -n` |
| `mount` | `mount` (primary), `mount_source`, `filesystem`, `opts` | `findmnt` |
| `addr` | `addr` (primary), `reachable`, `timeout` | Pure Go-native `net.DialTimeout` for `charly check live`; `nc` for `charly check box` |
| `matching` | `matching` (primary), `contains` | Pure in-process value matching — no target probe |
| `cdp` | `method` (primary: status/list/eval/text/html/url/axtree/screenshot/open/click/type/raw/wait/coords + spa-*) + method-specific fields (`tab`, `expression`, `url`, `selector`, `text`, `artifact`, `x`, `y`, `http_method` for `raw`) + `artifact_min_bytes` | Deploy-context only. Dispatches out-of-process via `candy/plugin-cdp` (no host subcommand). See `references/live-probe-verbs.md`. |
| `wl` | `method` (primary: screenshot/status/click/type/key/key-combo/mouse/scroll/drag/clipboard/toplevel/windows/focus/close/geometry/xprop/atspi/exec/resolution + overlay-*/sway-*) + method-specific fields (`x`, `y`, `text`, `key`, `combo`, `target`, `action`, `command`, `artifact`) | Deploy-context only. Dispatches out-of-process via `candy/plugin-wl` (no host subcommand; includes the `sway-*` and `overlay-*` nested methods). See `references/live-probe-verbs.md`. |
| `dbus` | `method` (primary: list/call/introspect/notify) + method-specific fields (`dest`, `path`, `member` — the fully-qualified interface.Method a `call` invokes, `arg`, `text`) | Deploy-context only. Dispatches out-of-process via `candy/plugin-dbus` (no host subcommand); EXEC-based, driving the venue's session bus with `gdbus`. |
| `vnc` | `method` (primary: status/screenshot/click/mouse/type/key/rfb/passwd) + method-specific fields (`x`, `y`, `text`, `key`, `artifact`) | Deploy-context only. Dispatches out-of-process via `candy/plugin-vnc` (no host subcommand); the host pre-resolves the RFB endpoint for pod AND vm targets. See `references/live-probe-verbs.md`. |
| `mcp` | `method` (primary: ping/servers/list-tools/list-resources/list-prompts/call/read) + method-specific fields (`tool`, `uri`, `input`, `mcp_name`) | Deploy-context only. Speaks `github.com/modelcontextprotocol/go-sdk` to any `mcp_provide` endpoint. See `references/live-probe-verbs.md` "Method allowlist — mcp". |

> **A step verb (or Op modifier) must never be spelled like a reserved kind word.** Kinds (`candy`, `pod`, `vm`, `k8s`, `local`, `android`, `group`, …) live only at a config edge — the opening discriminator of a top-level node or a tree-child node — never as a key in the middle of a step. A new probe verb that would collide with a kind word must pick a non-colliding spelling (the `k8s`/`group` probe verbs were renamed to `kube`/`unix_group` for exactly this reason). This is machine-enforced by `sdk/spec` `TestNoKindWordAsStepVerb` + `TestNoKindWordAsOpModifier` — adding a colliding verb fails the build.

### Shared modifiers

| Field | Purpose |
|-------|---------|
| `id` | Optional stable identifier. Enables `charly.yml` to override by `id`. Unique per section per image. |
| `description` | Human-readable label for reports. |
| `skip: true` | Always skip this check (reported but doesn't fail the run). |
| `exclude_distro: [<tag>, ...]` | Skip the check when any of the image's `distro:` tags matches an entry. Use for probes that only apply on some distros (e.g. `file: /usr/bin/fastfetch` is valid on Fedora/Arch/Debian but fastfetch is dropped from Ubuntu 24.04's noble main). Matched against the image's full distro list (`["ubuntu:24.04", "ubuntu", "debian"]`), so either `ubuntu:24.04` or `ubuntu` matches. See `charly/checkspec.go:Op.ExcludeDistros` and `charly/checkrun.go:runOne`. |
| `timeout: "5s"` | Per-check timeout (http, addr). |
| `context: [build\|deploy\|runtime]` | Which contexts the step runs in (a list). Build steps run in `charly check box`; deploy/runtime steps need a live deployment. |

#### `exclude_distro:` worked example

```yaml
plan:
    - check: the fastfetch binary is installed (skipped on Ubuntu)
      id: fastfetch-binary
      exclude_distro:
          - ubuntu
      file:
          file: /usr/bin/fastfetch
          exists: true
```

On `ghcr.io/opencharly/ubuntu-coder:latest` this reports `skipped (excluded on distro "ubuntu")` instead of `failed`. On any other image it runs normally. Prefer this over dropping the test entirely — it keeps the guard in place for Fedora/Arch/Debian and documents why Ubuntu is special.

**Compared to `package_map:`** — `package_map:` changes what the test *probes for* per distro (same semantic, different package name). `exclude_distro:` skips the check entirely — use it when the functionality genuinely doesn't exist on a given distro.

### Matcher forms

Any `MatcherList` attribute (`stdout`, `stderr`, `body`, `headers`,
`contains`, `opts`, `value`) accepts three shapes — picked by yaml.v3
at parse time:

```yaml
stdout: PONG                         # scalar  → [{equals: PONG}]
stdout: [PONG, READY]                # list    → [{equals: PONG}, {equals: READY}]
stdout:
  - equals: PONG                     # operator map
  - contains: ["ready", "ok"]
  - matches: "^[A-Z]+$"
  - not_contains: "error"
```

Supported operators: `equals`, `not_equals`, `contains`, `not_contains`,
`matches`, `not_matches`, plus `lt`/`le`/`gt`/`ge` (numeric, added as
verbs need them).

**`status:` is not a MatcherList** — it's a plain `int` on the `http`
verb. One code per test. See `references/authoring-gotchas.md` #2.

## Three levels, three sections

| Section | Authored in | When it runs |
|---------|-------------|--------------|
| `candy` | `plan:` steps in the candy body, `candy/<name>/charly.yml` (build context) | `charly check box` + `charly check live` |
| `box` | `plan:` steps in the box body, `charly.yml` (build context) | `charly check box` + `charly check live` |
| `deploy` | a `plan:` step with `context: [deploy]`, or a local `charly.yml` overlay step | `charly check live <name>` only (deploy-context steps need a running deployment with port mappings, volumes, and resolved runtime variables) |

The `ai.opencharly.description` label carries the collected plan steps from all three
sections with `origin:` annotations (`candy:<name>`, `box:<name>`, `deploy-default`,
`deploy-local`). `CollectDescriptions` walks the base-image chain with a
visited-image guard: cycles are reported by `validateBoxDAG` at validate
time, but the collector itself terminates cleanly even if called on a
pathological config.

## Verb routing (which executor runs each check)

Every verb dispatches through one of two executors depending on the run
mode — this is what makes the same plan work both against a
disposable container (`charly check box`) and a running service (`charly check live`):

| Verb + attributes | Under `charly check live` (running service) | Under `charly check box` (disposable) |
|-------------------|-----------------------------------|------------------------------------|
| file, package, service, process, user, unix_group, interface, kernel-param, mount | `ContainerExecutor` (`podman exec`) | `ImageExecutor` (`podman run --rm`) |
| port with `listening` | `ContainerExecutor` (`ss`/`netstat` inside) | `ImageExecutor` |
| port with `reachable` | Host-side `net.DialTimeout` | Skipped (no host port binding on a disposable run) |
| command (`in_container: true`, default) | `ContainerExecutor` | `ImageExecutor` |
| command (`in_container: false`) | Host-side `exec.Command` | Skipped |
| http, dns, addr | Host-side (from the `charly` process) | In-container `curl` / `getent hosts` / `nc` |
| matching | In-process matcher check | Same |

The routing table lives in `charly/checkrun.go` (`runOne` switch) and
`charly/checkrun_charly_verbs.go`. When a check is unroutable (e.g. `port:
reachable` under `charly check box`), the runner reports it as **skipped**
with a reason rather than failing the run.

### in-container `command:` stdin is guarded

An in-container `command:` script (`in_container: true`, the default) is
delivered to the pod shell over a stdin heredoc (`NestedExecutor.wrapWithJump`,
"stdin-attached exec"). The runner wraps every such script in
`{ <script>; } </dev/null` (`wrapContainerCommand`, `charly/checkrun.go`) so a
subcommand that reads stdin — `adb shell`, `ssh`, `read`, `cat` — cannot consume
the rest of the heredoc (the not-yet-run script lines, which would otherwise
truncate the check to its first command). Authors write plain multi-line
scripts; no per-call-site `</dev/null` is needed. Host-side `command:`
(`in_container: false`) runs via `sh -c` argv and is unaffected. For Android UI
readiness, prefer the typed `adb: wait-ui-settled` / `current-focus` / `keyevent`
verbs (`/charly-check:adb`) over shell entirely.

## Runtime variables

`charly check live` resolves these via `podman inspect` on the running container
before any check executes. `${NAME:arg}` is parameterized form.

| Variable | Source | Context |
|----------|--------|-------|
| `${USER}`, `${HOME}`, `${UID}`, `${GID}` | Image metadata (OCI labels) | build + deploy |
| `${IMAGE}` | Image metadata | build + deploy |
| `${DNS}`, `${ACME_EMAIL}` | Image metadata + charly.yml overlay | build + deploy |
| `${INSTANCE}` | `--instance` flag / charly.yml key | deploy |
| `${CONTAINER_NAME}`, `${CONTAINER_IP}` | `podman inspect` | deploy |
| `${HOST_PORT:N}` | Port mapping for container port N | deploy |
| `${VOLUME_PATH:name}` | Host path backing the named volume (bind source, encrypted mount, or `_data` dir) | deploy |
| `${VOLUME_CONTAINER_PATH:name}` | In-container mount path for a volume | deploy |
| `${ENV_NAME}` | Effective env var value on the running container | deploy |
| `${HOST:member}` | A separate member's container DNS name on the shared `charly` net (`charly-<member>`); no `:<port>` segment → container DNS; cross-member addressing (see `references/cross-deployment-probing.md`) | deploy |
| `${HOST:member:port}` | A host-reachable `127.0.0.1:NNNN` for a separate member's `port` (published port / VM ssh-forward); the `:<port>` segment selects host-vantage cross-member addressing | deploy |

Build-context steps may not reference deploy-context variables — the
validator flags this at `charly box validate` time.

**No bash-style defaults**: `${VAR:-fallback}` is unsupported (see
`references/authoring-gotchas.md` #7). Plain `${VAR}` only.

## charly.yml overlay rules

A local `charly.yml` can contribute its own `plan:` steps per deploy.
Merge rules applied by `charly check live`:

1. Local entries with an `id:` matching a baked entry replace that entry.
2. Entries without a matching `id:` are appended.
3. To disable a baked check, reference it with `id:` and `skip: true`.

```yaml
# ~/.config/charly/charly.yml — name-first: the redis-ml deploy with overlay plan: steps
redis-ml:
    pod:
        image: redis-ml
        plan:
            - check: redis answers ping             # overrides image's baked step (by id)
              id: redis-responds
              stdout: PONG
              command:
                  command: redis-cli -h 127.0.0.1 -p 16379 ping
                  in_container: false
            - check: the external tunnel is healthy # appended (no baked match)
              id: external-tunnel
              http:
                  http: https://redis.tailnet.ts.net/health
                  status: 200
            - check: a legacy baked step            # disable a legacy baked step
              id: old-probe
              skip: true
```

## Typical workflow

```bash
# 1. Author tests in candy/<name>/charly.yml.
# 2. Validate schema + references.
charly box validate

# 3. Build the image (the plan is auto-embedded as `LabelDescriptionSet`).
#    LABELs are emitted LAST in the final stage — a test edit rebuilds
#    in ~2 sec (cache hits every upstream RUN/COPY).
charly box build redis-ml

# 4. Run against a disposable container (build-context steps only).
charly check box redis-ml

# 5. Start the service and test end-to-end.
charly start redis-ml
charly check live redis-ml

# 6. Override a baked deploy check via local charly.yml, re-test.
$EDITOR ~/.config/charly/charly.yml    # add an overlay plan: step with matching id
charly check live redis-ml
```
