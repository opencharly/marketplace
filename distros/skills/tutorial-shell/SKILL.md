---
name: tutorial-shell
description: |
  The teaching box quoted end to end by opencharly.ai — a minimal, real dev shell
  composing one tool candy, one service candy, and the container init.
  MUST be invoked before editing the tutorial-shell box, the tutorial-shell-dev bed,
  or any documentation page that excerpts them.
---

# tutorial-shell

The **documented example**. `tutorial-shell` exists so the quickstart and the concepts
curriculum on [opencharly.ai](https://opencharly.ai) can quote a box that is real, builds, and is
re-proven on every R10 roster run — instead of illustrating with YAML that nobody executes.

Lives in the **`opencharly/distro-fedora`** repo (git submodule at **`box/fedora`**). Its
`fedora` base is bare-local in the same self-contained submodule (`import: []`), and the three
candies are pulled by `@github` reference.

```bash
charly -C box/fedora box build tutorial-shell
charly -C box/fedora check run tutorial-shell-dev
```

## Box Properties

| Property | Value |
|----------|-------|
| Base | fedora |
| Candies | supervisord, ripgrep, sshd |
| Ports | 2222 (tcp, from the sshd candy) |
| Init | supervisord |
| Bed | `tutorial-shell-dev` (`disposable: true`, pod) |

## Why these three candies

Each one is there to teach exactly one thing, and the box is kept at three so it stays readable
when quoted in full on a documentation page:

| Candy | Teaches |
|---|---|
| `/charly-tools:ripgrep` | a **tool** candy — packages plus deterministic probes, no service |
| `/charly-coder:sshd` | a **service** candy, and the canonical init-polymorphism example: ONE `service:` list carrying both a `use_packaged:` systemd form and a custom `exec:` supervisord form |
| `/charly-infrastructure:supervisord` | the container **init** that actually runs the service |

Together they cover the whole shape of a box without any of them being a fixture: a reader can
build this, shell into it, and use it.

## What the box's own plan asserts

The box carries two `check:` steps, and both assert **cross-candy invariants the composed candies
cannot assert individually**:

- `tutorial-shell-composition` — `rg` and `sshd` are on PATH *together*. Neither candy's own plan
  can prove this: ripgrep's checks pass in any image containing ripgrep, sshd's in any image
  containing sshd. Only the composing box can prove they arrived in one image.
- `tutorial-shell-search-works` — the composed tool really searches on this base, rather than
  merely being present.

The `tutorial-shell-dev` bed adds the two claims only a live deployment can settle: the sshd
service came up under supervisord, and the tool is usable inside the running pod.

## Editing rule — the site quotes this file verbatim

Documentation pages **excerpt** `box/tutorial-shell/charly.yml`, they do not paraphrase it. Two
consequences:

1. **Keep it readable.** Comments in the box are written for a first-time reader, not for a
   maintainer. Resist adding candies: every addition costs a line on several published pages.
2. **A change here is a documentation change.** After editing the box, re-read the pages that
   quote it (the quickstart and the concepts curriculum) and update the surrounding prose in the
   same cutover — a quoted block that no longer matches its source is a doc-vs-reality divergence
   (R1), not a cosmetic drift.

## Related Boxes

- `/charly-distros:fedora` — the parent base image
- `/charly-distros:charly-fedora` — the next box up in size: the same shape plus the charly toolchain
- `/charly-coder:fedora-coder` — the kitchen-sink end of the same spectrum (~32 candies)

## Related Commands

- `/charly-build:build` — build the box
- `/charly-check:check` — the bed model and `charly check run`

## When to Use This Skill

**MUST be invoked** when editing the `tutorial-shell` box, the `tutorial-shell-dev` bed, or any
opencharly.ai page that quotes them.

## Related

- `/charly-image:image` — image family umbrella (`candy:` entries carrying `base:`/`from:`)
- `/charly-build:docs` — the generator that publishes this card and the box's reference page
