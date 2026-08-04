---
name: tutorial-shell
description: |
  The teaching box quoted end to end by opencharly.ai — a minimal, real dev shell
  composing one tool candy and one service candy, with the container init injected.
  MUST be invoked before editing the tutorial-shell box, the check-tutorial-shell bed,
  or any documentation page that excerpts them.
---

# tutorial-shell

The **documented example**. `tutorial-shell` exists so the quickstart and the concepts
curriculum on [opencharly.ai](https://opencharly.ai) can quote a box that is real, builds, and is
re-proven on every R10 roster run — instead of illustrating with YAML that nobody executes.

Lives in the **`opencharly/distro-fedora`** repo (git submodule at **`box/fedora`**). Its
`fedora` base is bare-local in the same self-contained submodule (`import: []`), and both composed
candies are pulled by `@github` reference.

```bash
charly -C box/fedora box build tutorial-shell
charly -C box/fedora check run check-tutorial-shell
```

## Box Properties

| Property | Value |
|----------|-------|
| Base | fedora |
| Candies | ripgrep, sshd |
| Ports | 2222 (tcp, from the sshd candy) |
| Init | supervisord — **auto-injected**, not composed (see below) |
| Bed | `check-tutorial-shell` (`disposable: true`, pod) |

## Why these two candies

Each one is there to teach exactly one thing, and the composed list is kept to two so it stays
readable when quoted in full on a documentation page:

| Candy | Teaches |
|---|---|
| `/charly-tools:ripgrep` | a **tool** candy — packages plus deterministic probes, no service |
| `/charly-coder:sshd` | a **service** candy, and the canonical init-polymorphism example: ONE `service:` list carrying both a `use_packaged:` systemd form and a custom `exec:` supervisord form |

**The init is deliberately absent from that list.** Because `sshd` declares a service, charly
resolves the init the target needs and injects it — `supervisord` for a container image, nothing
extra for a systemd machine venue, which already has an init. Composing the init by hand is
neither required nor correct: it would be target-blind. That is why the box teaches with two
candies rather than three.

Together they cover the whole shape of a box without any of them being a fixture: a reader can
build this, shell into it, and use it.

## What the box's own plan asserts — and what it deliberately does not

The box carries **one** `check:` step, `tutorial-shell-service-wired-into-init`: the assembled
`/etc/supervisord.conf` contains a `[program:sshd]` block.

That is the only claim composition itself produces. `supervisord`'s plan proves the init is
installed; `sshd`'s proves the daemon is installed; **neither proves sshd became a supervisord
program**. Drop either candy and the check fails — regenerating without `sshd` emits no
`supervisor/` fragment directory at all.

**Co-residence is NOT checked here, on purpose.** Every composed candy's plan runs against *this*
image, so ripgrep's probes and sshd's probes both passing already proves both landed. A box-level
`command -v rg && command -v sshd` would duplicate them (R3), and it would pass for the wrong
reason — testing the candies rather than the composition. The same applies to the bed, which
carries no `plan:` of its own.

This distinction is the reason the box exists in its current shape, and it is worth preserving: a
teaching example that restates a candy's own probe in the composing box teaches the opposite of
the rule the site's own "the spec is the test" page states.

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

**MUST be invoked** when editing the `tutorial-shell` box, the `check-tutorial-shell` bed, or any
opencharly.ai page that quotes them.

## Related

- `/charly-image:image` — image family umbrella (`candy:` entries carrying `base:`/`from:`)
- `/charly-build:docs` — the generator that publishes this card and the box's reference page
