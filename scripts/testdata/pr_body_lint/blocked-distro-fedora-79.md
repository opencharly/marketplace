## Summary

The `check-tutorial-shell` bed's `description:` described a box that no longer exists. It said:

- "Builds the **two-candy** box (ripgrep + sshd)";
- "The box composes **NO init**".

`box/tutorial-shell/charly.yml` lists three candies, `layer-supervisord`, `layer-ripgrep` and `pod-sshd`. It names the supervisord candy explicitly so that the assembled `/etc/supervisord.conf` is deterministic, and its own plan asserts that sshd became a supervisord program.

The description now matches the box. This text matters because it is the bed that proves the teaching example opencharly.ai quotes verbatim.

Part of opencharly/charly#747 (README and docs truth audit).

## How tested

Head `77f6ad9b2004531deb9e5728fd2c01894606728d`, based on `origin/main` `9d7e972`:

```
 charly.yml | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
```

The new description, checked against the box on this tree:

```
candies: ['layer-supervisord', 'layer-ripgrep', 'pod-sshd']
plan asserts: {'file': '/etc/supervisord.conf', 'contains': [{'contains': '[program:sshd]'}]}
desc ok: True True        # contains "supervisord + ripgrep + sshd"; no longer contains "NO init"
```

`charly box validate`, run with a binary built from charly `main` (`2026.273.0744`), stops at the schema floor before it reads any content:

```
charly: error: command "validate": validation error: <repo>/charly.yml: schema 2026.261.1747 is required (found "2026.249.2125"). Run: charly migrate
```

This is the org-wide condition on current `main`: the identical error appears for `--repo opencharly/distro-fedora` on unmodified `main`, and in every repo whose `charly.yml` carries the 2026.249.2125 stamp. It is owned by the schema-versioning-removal wave (opencharly/charly#714, #745), and #745 records it as blocking #747.

## Rulebook compliance

- **R0:** `/charly-internals:git-workflow` and `/charly-check:check` were loaded before the edit.
- **R1:** the `box validate` failure was traced to its owner (#745).
- **R5:** the stale "two-candy" / "NO init" claims are removed; this was their only occurrence in the repo.
- **R6:** a feat branch, a single push, no force push.
- **Rule 9:** no other session's work is touched; the work is coordinated on #747.
- **R10:** no runtime path changed; only a description string changes.

## Change classification

- **Change class:** documentation only (a bed `description:` string). The bed's configuration and plan are unchanged.
- **Verification gate:** the description is checked against the box above. `box validate` is blocked upstream by #745.
- **Attribution tier:** documentation reviewed.

*Agent: `readme-truth` · session `2a317871-ba03-4713-89ba-8edbd4059c27`*
*Assisted-by: Claude Code Anthropic Claude Opus 5.5 (documentation reviewed)*
