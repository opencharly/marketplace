# Live-container probe verbs — cdp, wl, dbus, vnc, mcp

Full detail for `/charly-check:check`. Covers the deploy-context-only probe verbs that dispatch out-of-process to their serving plugin candy. The `kube`/`adb`/`appium`/`spice`/`libvirt` verbs are each served by their own plugin and documented in their own skill — see this skill's "Related skills".

## Live-container verbs — ALL served out-of-process

There are no in-core `charly check <verb>` host subcommands: every
live-container probe verb is served out-of-process by its plugin candy and
reached ONLY as a declarative step. `wl` was the last live-container verb
compiled into charly — after its move to `candy/plugin-wl`, zero check verbs are
in-core. The `charly check` command tree is now the three primary modes +
`feature` + the check-run management subcommands (`box`/`live`/`run`/`feature`,
`list`/`report`/`note`/…) — nothing else.

Each live-container verb (`cdp:`/`wl:`/`vnc:`/`dbus:`/`mcp:`/`record:`/`kube:`/
`adb:`/`appium:`/`spice:`/`libvirt:`) is authored as a declarative step and
dispatched through the provider registry exactly like a built-in verb
(`ResolveVerb` → the out-of-process gRPC provider → `Provider.Invoke`); run a
candy's baked steps with `charly check live <image> --filter <verb>`. `libvirt`
(served by `candy/plugin-vm`) and `kube`/`adb`/`appium` (each served by its own
plugin candy) are all dispatched through that same provider registry — there is no
separate in-`charly check` attach path. Authoring never
says `plugin: <verb>` — you write `wl: screenshot`, `libvirt: info`, etc. The
per-verb skill + serving plugin are listed in this skill's "Related skills" index.

Because no live-container verb is a host subcommand any more, an image's name can
never collide with one — `charly check live <name>` resolves the image
unambiguously.

## Live-container verb catalog: `cdp`, `wl`, `dbus`, `vnc`, `mcp`

None of these verbs has a host `charly check` subcommand — each dispatches
out-of-process via its plugin (`candy/plugin-cdp`, `candy/plugin-wl`,
`candy/plugin-dbus`, `candy/plugin-vnc`, `candy/plugin-mcp`; parallel to the
`kube:`/`spice:`/`adb:`/`appium:` plugin verbs).
The `vnc` plugin covers pod AND vm targets — the host pre-resolves the RFB endpoint
(pod port-5900 or a VM's libvirt VNC via bridge/tunnel) and the plugin dials it.
Every live-container
operation (browser automation, Wayland input/screenshot, D-Bus calls, VNC
framebuffer capture, MCP protocol probes) is authorable as a declarative step.
All five are deploy-context only — they need a running container with port
mappings; `charly box validate` rejects them in build context, and `charly check
box` skips them at runtime with a clear message.

**Assertion semantics:** the runner dispatches the method to the out-of-process
plugin (`candy/plugin-cdp`, `candy/plugin-wl`, `candy/plugin-vnc`,
`candy/plugin-dbus`, `candy/plugin-mcp`), which captures stdout/stderr/exit and
feeds the output through the existing matcher pipeline. Queries
(status/list/eval/text/html/url/axtree/screenshot/…) produce assertable output.
Side-effect actions (click/type/open/close/…) pass when they exit 0 — follow them
with a query check to verify the effect.

**No state chaining:** there's no framework-managed variable to
carry a tab ID or window handle from one check to the next. Authors rely
on conventions (new tabs are usually ID 1) and inspect state via
follow-up `cdp: list` checks if needed.

### Method allowlist — `cdp` (15 methods + 6 SPA-nested)

Queries: `status`, `list`, `url`, `text`, `html`, `eval`, `axtree`,
`coords`, `raw`, `wait`, `screenshot`.
Actions: `open`, `close`, `click`, `type`.
SPA-nested (selkies coordinate-scaling / passthrough input):
`spa-status`, `spa-click`, `spa-type`, `spa-key`, `spa-key-combo`,
`spa-mouse`.

```yaml
plan:
    - check: the CDP endpoint is reachable
      id: cdp-up
      cdp: status                   # scalar sugar == {method: status}
      stdout:
          equals: ok

    - check: the page title is Dashboard
      id: cdp-page-title
      cdp:
          method: eval
          tab: "1"
          expression: "document.title"
      stdout: "Dashboard"

    - check: a non-empty CDP screenshot is captured
      id: cdp-screenshot-valid
      cdp:
          method: screenshot
          tab: "1"
          artifact: /tmp/cdp.png
          artifact_min_bytes: 10000   # PNG must be non-empty
```

### Method allowlist — `wl` (22 top-level + 4 overlay + 12 sway)

Queries: `screenshot`, `status`, `toplevel`, `windows`, `geometry`,
`xprop`, `atspi`, `clipboard`.
Actions: `click`, `double-click`, `mouse`, `scroll`, `drag`, `type`,
`key`, `key-combo`, `focus`, `close`, `fullscreen`, `minimize`, `exec`,
`resolution`.
Overlay-nested: `overlay-list`, `overlay-status`, `overlay-show`,
`overlay-hide`.
Sway-nested: `sway-tree`, `sway-workspaces`, `sway-outputs`, `sway-msg`,
`sway-focus`, `sway-move`, `sway-resize`, `sway-kill`, `sway-floating`,
`sway-layout`, `sway-workspace`, `sway-reload`.

```yaml
plan:
    - check: a non-empty desktop screenshot is captured
      id: wl-desktop-captured
      wl:
          method: screenshot
          artifact: /tmp/wl.png
          artifact_min_bytes: 10000

    - check: at least one toplevel window is present
      id: wl-has-windows
      wl: toplevel
      stdout:
          matches: "."      # at least one line of output

    - check: sway reports workspace "1"
      id: wl-sway-has-workspace-1
      wl: sway-workspaces
      stdout:
          contains: '"name":"1"'
```

### Method allowlist — `dbus` (4 methods)

Queries: `list`, `call`, `introspect`.
Actions: `notify`.

```yaml
plan:
    - check: the Notifications service is registered on the bus
      id: dbus-notifications-registered
      dbus: list
      stdout:
          contains: "org.freedesktop.Notifications"

    - check: the Notifications service answers GetCapabilities
      id: dbus-get-capabilities
      dbus:
          method: call
          dest: org.freedesktop.Notifications
          path: /org/freedesktop/Notifications
          member: org.freedesktop.Notifications.GetCapabilities
      stdout:
          contains: body
```

### Method allowlist — `vnc` (8 methods)

Queries: `status`, `screenshot`, `rfb`.
Actions: `click`, `mouse`, `type`, `key`, `passwd`.

```yaml
plan:
    - check: the VNC endpoint is reachable
      id: vnc-up
      vnc: status
      stdout:
          equals: ok

    - check: a non-empty VNC framebuffer is captured
      id: vnc-framebuffer-captured
      vnc:
          method: screenshot
          artifact: /tmp/vnc.png
          artifact_min_bytes: 5000
```

### Method allowlist — `mcp` (7 methods)

Queries: `ping`, `servers`, `list-tools`, `list-resources`, `list-prompts`,
`read`.
Actions: `call`.

The `mcp` verb speaks the Model Context Protocol to any server advertised
via `mcp_provide`. URL resolution is automatic — the runner reads the
image's `ai.opencharly.mcp_provide` OCI label, substitutes
`{{.ContainerName}}`, runs the entries through `podAwareMCPProvides`, and
then rewrites the host portion to `127.0.0.1:<published-host-port>` using
the same port-mapping data that powers `${HOST_PORT:N}`. No URL argument
is needed in YAML.

Transport dispatch: `transport: http` (or empty) → Streamable HTTP;
`transport: sse` → SSE. Anything else is rejected at dial time.

Disambiguation: if an image declares multiple `mcp_provide` entries,
add `mcp_name: <server>` on the check; otherwise the single entry
auto-picks.

```yaml
plan:
    - check: the MCP server answers a ping
      id: mcp-ping
      context: [deploy]
      mcp: ping
      timeout: 10s              # optional; default 30s

    - check: the MCP server lists its notebook tools
      id: mcp-list-tools
      context: [deploy]
      mcp: list-tools
      stdout:
          - contains: insert_cell   # plaintext "name\tdescription" per line
          - contains: execute_cell

    - check: calling list_notebooks succeeds (no IsError)
      id: mcp-call-tool
      context: [deploy]
      mcp:
          method: call
          tool: list_notebooks  # required
          input: "{}"           # optional JSON arg blob
      exit_status: 0            # assert no IsError

    - check: reading a resource returns a non-empty body
      id: mcp-read-resource
      context: [deploy]
      mcp:
          method: read
          uri: file:///tmp/example.txt
      stdout:
          - matches: "."        # non-empty body
```

There is no host `charly check` subcommand for `mcp`: it is a
declarative-only check verb served out-of-process by `candy/plugin-mcp` (parallel
to `kube:`/`spice:`/`adb:`/`appium:`). Exercise it by running the candy's baked
`mcp:` steps against a live deployment — `charly check live <image> --filter mcp` —
or author the steps above. For multi-server images the `--name` flag is the
declarative `mcp_name:` modifier; the full verb reference (methods, URL rewriting,
port-publishing gotcha, validator rules) lives in `/charly-build:charly-mcp-cmd`.

Output format: tab-separated plaintext (one record per line) so matchers
can `contains:` without JSON decoding. `list-tools` emits
`<name>\t<description>`; `list-resources` emits `<uri>\t<name>\t<mime>`;
`call` emits the concatenated `TextContent` payloads; `ping` emits `ok`.

### Artifact-validation modifiers

For artifact-producing methods (`cdp: screenshot`, `wl: screenshot`,
`vnc: screenshot`, `libvirt: screenshot`, `spice: screenshot`,
`record: stop`), set `artifact: <path>` to tell `charly` where to write the
output AND any combination of the modifiers below to assert the
artifact's correctness post-run.

- **`artifact_min_bytes: <N>`** — assert the file is at least N bytes
  after the run. Guards against zero-byte files. Cheap (`os.Stat`
  only).
- **`artifact_min_dimensions: WxH`** — assert decoded image width and
  height are each at least the given values. Reads only the PNG/JPEG
  header via `image.DecodeConfig`, so essentially free. Catches "the
  screenshot ran but the compositor produced 320×240 instead of the
  expected 1920×1080".
- **`artifact_not_uniform: true`** — assert the image is not uniformly
  one color. Decodes the full image and samples 100 pixels at
  deterministic stride positions; fails if every sampled pixel has
  the same RGBA. Catches the failure mode `artifact_min_bytes` is
  blind to: a 100KB all-black PNG passes the byte check but fails
  this one. Use on every screenshot probe where "the image has real
  content" matters.
- **`artifact_min_cast_events: <N>`** — for asciinema `.cast`
  artifacts (e.g. `record: stop` in terminal mode): validates the
  first line is the asciinema v2 header and counts at least N event
  lines after it. Catches "the recording started and stopped but
  captured nothing because nothing was typed".

```yaml
plan:
    # Combined screenshot validity assertion — bytes + dimensions + content.
    - check: the CDP screenshot is a real, non-uniform image
      id: cdp-screenshot-real
      cdp:
          method: screenshot
          tab: "1"
          artifact: /tmp/cdp.png
          artifact_min_bytes: 5000
          artifact_min_dimensions: 800x600
          artifact_not_uniform: true

    # Recording validity — bytes + event count.
    - check: the terminal recording captured real events
      id: record-cast-has-events
      record:
          method: stop
          artifact: /tmp/session.cast
          artifact_min_bytes: 200
          artifact_min_cast_events: 5
```

The four modifiers are independent — set just the one you need or
combine all four for the strongest "the artifact is real" assertion.
Failure messages identify the specific artifact and the specific
threshold that wasn't met.
