# marketplace/ — the generated corpus (not the rule-set)

You are in the OpenCharly **marketplace** repo: the generated Claude Code / Codex / Kimi /
pi plugin corpus. The rulebook lives in the charly repo (`AGENTS.md`/`CLAUDE.md` there) and
the authoritative skill index is this repo's `README.md`.

**Load these skills FIRST (R0)** — they are part of the corpus:

- `/charly-internals:skills` — skill authoring/maintenance, the plugin/skill directory
  conventions, and where content belongs.
- `/charly-internals:agents` — authoring or invoking sub-agents (`internals/agents/*.md`),
  dynamic workflows, agent teams, the hooks doctrine.

## The one rule: this tree is generated

Everything except `README.md`, `CLAUDE.md`, `LICENSE`, `CHANGELOG/`, `scripts/`,
`kimi-user-config.toml`, `.gitmodules` and `.github/` is a projection of the
[opencharly/charly](https://github.com/opencharly/charly) candies, produced by
`charly marketplace generate --root ./charly --out .` from the charly commit this repo's
`.gitmodules` pins. **Never hand-edit a generated file** — edit the candy entity, regenerate,
and land the corpus here in the same change. The `deploy.yml` drift gate fails any PR whose
committed corpus is not a no-op regeneration of the pinned charly.

This repo has no rulebook of its own beyond this signpost: the charly `AGENTS.md` owns the
mandate, and the generated skills own the procedures.
