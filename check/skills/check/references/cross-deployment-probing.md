# Image preflight and cross-deployment probing

Full detail for `/charly-check:check`: the host-target image-preflight fetch surface, and cross-deployment probing (one deployment testing another via venue-from-position members and `${HOST:...}` addressing).

## Image preflight (host-target runs only)

When `charly check run --on-host <name>` (or any `iterate:` entity whose
sandbox resolves to `TargetKindHost`) dispatches the runner, an image
preflight runs first: walk the bed's plan, collect every
distinct step venue's image (per-step `Op.venue`, loader-derived from tree
position) plus the bed's target image, deduplicate, and
ensure each image is present in local podman storage before handing
off to the host runner.

For each discovered image, the algorithm is:

1. `LocalImageExists(podman, ref)` — short-circuit if already
   present. Idempotent on re-runs.
2. `charly box pull <ref>` — preferred path. Resolves short names via
   `cfg.Images[<name>]`, full registry refs pass-through, remote
   `@github.com/...` refs walk through `ResolveRemoteImage`.
3. `charly box build <name>` — fallback when pull fails AND the
   identifier is a short name resolvable via the project's
   `charly.yml`. Build fallback is local-only; for any non-short
   identifier that fails to pull, the preflight aborts with an
   actionable error.

Failures abort the check before any plan step runs, so operators see
problems early rather than mid-run.

This is the **only** image-fetch surface in the system: deploys (any
target — `local`, `pod`, `vm`, `k8s`) emit zero image-pull steps. A
`kind: local` template has no `image:` field; image preflight lives on this
verb. Operators with legacy YAML run `charly migrate`. See
`/charly-local:local-spec` "What the deploy does NOT do" and the project rulebook
"Deploy fetches NOTHING speculative".

Lives in `charly/check_image_preflight.go`
(`EnsureImagePresent`, `ensureScoreImages` — the "preflight" mode body); reached
via the `host_build_check_run.go` "preflight" seam, which the `command:check`
plugin (`candy/plugin-check`) drives for the host-target run (the former
`case TargetKindHost:` arm). Pod / VM / k8s
targets carry their own image inside their respective deploy schema
and never trigger the preflight.

## Cross-deployment probing — venue-from-position members + `${HOST:...}`

A check normally probes the deployment under test. Cross-deployment probing
lets ONE deployment act as a test DRIVER against a SEPARATE deployment as the
SUBJECT — the canonical case being a Chrome DRIVER pod that CDP-probes a
separate web-server SUBJECT pod, so a real browser tests the subject without
baking Chrome into the subject image. "A different kind of deployment tests
another kind" — pod→pod, local→pod, and local→VM, all through one mechanism.

Two pieces compose it:

- **venue-from-position members** — bring the driver up alongside the subject on
  the shared `charly` network (see `/charly-core:deploy` "Sibling members"). A deploy
  declares each as a MEMBER NODE — a resource node on a substrate kind (`pod: {image: …}` / `vm: {from: …}` / `local: {from: …}`)
  placed directly under the deploy — and a plan step's execution venue is its tree
  position: a step in the `plan:` of member `M` runs on `M` (bare name), a step in the
  `plan:` of a nested child `C` of parent path `P` runs on `P.C` (dotted). There is no authored
  `on:`/`pod:` step field — both are retired; tree position is the sole source of
  venue (`flattenBundleVenues` stamps it at load time). A `cdp:`/`vnc:`/`mcp:` step
  placed under a driver member connects to that member's CDP/VNC/MCP endpoint; a
  `command:` step runs in that member's venue. Members are brought up by the same
  deploy verbs and are never check-live'd (instruments, not subjects). A GROUP
  deploy (the `group:` kind) carries no workload of its own — it has no venue of its
  own, so every plan step must live under a member (a direct step on a group root is a
  hard load error). **Agent-provisioned members:** in an `iterate:` bed a member
  marked `agent_provisioned: true` is the artifact the AI builds during the benchmark
  (e.g. the `os` venue), not something the bed brings up — `foldMembers` skips it, so it
  is never a top-level addressable entry (no auto bring-up) and never collides cross-bed
  when the same venue name recurs across iterate beds; the scorer reaches its
  `charly-<name>` container via the bare-name fallback (`resolveScoringChain`).
- **`${HOST:...}` address variable** — lets the driven probe target the subject;
  the presence of a `:<port>` segment selects which form resolves:
  - **`${HOST:<member>}`** (no `:<port>`) → the member's container DNS name on the shared
    `charly` net (`charly-<member>`; also verifies it is running). The pod→pod address:
    `http://${HOST:<subject>}:8080`. Reference the subject by its own deploy
    name (for a bed, that's the bed name — the container is `charly-<bedname>`).
  - **`${HOST:<member>:<port>}`** (with `:<port>`) → a host-reachable `127.0.0.1:NNNN` for
    that member's `<port>` (container published port, or an ssh `-L` forward
    for a VM/host subject). The host-vantage address a `local`/host driver uses to
    reach a pod/VM subject. (Both are runtime-only — a build-context step can't use
    them.)

  An unresolvable `${HOST:...}` — the member/subject is unreachable (not running, bad
  port, VM ssh-forward refused) — **fails** the referencing check, never skips it.
  A skip on an unreachable dependency is a fake pass: it would let a bed go green
  even though the cross-deployment probe never reached its target. (Legitimate
  skips — `skip: true`, `exclude_distro`, a deploy-only var under build context —
  are unaffected; only an unresolved mandatory `${HOST:...}` is treated as a failure.)

### Worked example — a Chrome pod CDP-probes a web-server pod (pod→pod)

```yaml
# charly.yml — a disposable GROUP deploy (no workload root): a web SUBJECT member +
# a chrome DRIVER member. Each is a resource node placed UNDER the deploy; each
# carries its own plan: list (venue = the member's name). Mirror
# box/fedora/charly.yml's check-cross-pod-cdp.
check-cross-pod-cdp:
    group:
        disposable: true             # group kind — no own workload (no image:/from:)
    web:                             # the SUBJECT member (nginx fixture on :8080)
        pod:
            image: web
            # No port: — every inherited container port auto-allocates a free
            # 127.0.0.1 host port (conflict-free across concurrent beds). Pin with
            # a port: entry (["H:C"]) only when a fixed host port is needed.
            plan:
                - check: the web subject serves its marker
                  id: web-fixture-up
                  context: [runtime]
                  http:
                      http: http://127.0.0.1:${HOST_PORT:8080}/
                      status: 200
                      body:
                          - contains: charly-fixture-web-content-marker
    chrome:                          # the DRIVER member (headless Chrome + cdp-proxy, publishes 9222)
        pod:
            image: chrome-headless
            plan:
                - check: chrome navigates to the subject over the charly net
                  id: cdp-open-web-subject        # venue=chrome (DRIVE; passes on exit 0)
                  context: [runtime]
                  cdp:
                      method: open
                      url: http://${HOST:web}:8080
                  eventually: 45s
                  retry_interval: 3s
                - check: the rendered page carries the marker
                  id: cdp-web-fixture-rendered    # also venue=chrome (ASSERT)
                  context: [runtime]
                  cdp:
                      method: text
                      tab: "1"       # the first page (cdp `open` lands on tab 1)
                  eventually: 30s
                  retry_interval: 3s
                  stdout:
                      - contains: charly-fixture-web-content-marker
```

`bringUpMembers` config+starts the chrome member alongside the web member; the
`cdp:` steps nested under `chrome` run with venue=chrome (dispatching the `cdp:`
verb out-of-process via `candy/plugin-cdp`, connecting to chrome's published 9222) while
`${HOST:web}` resolves to the web member's `charly-web` container, reached over the
shared net.

**Driver-box requirement (CDP):** a headless Chrome CDP driver must launch with
`--remote-allow-origins='*'` (Chrome 146+ rejects the CDP WebSocket upgrade
otherwise — `cdp open` via HTTP works, but `cdp text`/`check`/`screenshot` fail).
The `chrome-headless` box sets it; see `/charly-check:cdp` "Requirements".

### Cross-kind: a host driver reaching a pod OR a VM subject (`${HOST:<member>:<port>}`)

The `:<port>` (endpoint) form `${HOST:<member>:<port>}` is kind-agnostic — it routes through the ONE host-vantage
port resolver (`resolveCheckEndpoint`): a pod subject resolves to its auto-
published port (`podman port`); a VM subject resolves to an `ssh -L
127.0.0.1:<rand>:127.0.0.1:<guestport>` forward over the managed `charly-<vm>` alias
(the same forward `check-k3s-vm` uses to reach the cluster API host-side). So the
identical check — `command: curl …${HOST:<subject>:<port>}` placed under a
`kind: local` host-driver MEMBER (venue = that member) — proves a pod subject
(`check-cross-local-http`) and a VM subject (`check-cross-vm-http`) with zero
kind-specific check code; only the subject kind differs.

**The VM subject is driven from a host-side (`local:`) driver member, not a pod
driver.** `${HOST:<member>:<port>}` is a host-vantage `127.0.0.1:NNNN` address; a pod
driver can't reach it (that loopback is the pod's own netns), and a rootless
`qemu:///session` VM shares no L2 bridge with rootless pods. The generic, no-hack
VM cell therefore uses a local driver member — the host where both the published
port and the ssh-forward live. (`${HOST:<member>}` — no `:<port>`, pod-net container DNS — is the
pod→pod address and does not reach a VM.)
